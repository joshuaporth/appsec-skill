#!/usr/bin/env bash
# Score frozen Findings from benchmark/artifacts/findings/NN.txt against authoritative
# answer material for the same NN, per BENCHMARK.md (two-phase blind find ->
# judge). Staged workspace contains exactly two files: verbatim findings plus
# one solution file from benchmark/challenges/challenge-NN/.
#
# stdout is saved as benchmark/artifacts/scoring/NN.txt.
#
# Watching long runs (--print): same pattern as benchmark/findings.sh:
#   CLAUDE_TRACE=1 ./benchmark/scoring.sh
#   tail -f benchmark/artifacts/scoring/NN.trace.log
#
# Parallelism (default: run many workers at once — cap via MAX_PARALLEL):
#   MAX_PARALLEL=8 ./benchmark/scoring.sh
# Serial (easier debugging):
#   MAX_PARALLEL=1 ./benchmark/scoring.sh
#
# Optional wall clock per worker (requires timeout(1)):
#   CLAUDE_LIMIT_SEC=600 START=1 END=1 ./benchmark/scoring.sh
#
# Usage:
#   ./benchmark/scoring.sh
#   START=1 END=5 MAX_PARALLEL=4 ./benchmark/scoring.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
BENCH_ROOT="${SCRIPT_DIR}"
FINDINGS_DIR="${FINDINGS_DIR:-${BENCH_ROOT}/artifacts/findings}"
OUT_DIR="${BENCH_ROOT}/artifacts/scoring"
CLAUDE_BIN="${CLAUDE:-claude}"

START="${START:-1}"
END="${END:-30}"
MAX_PARALLEL="${MAX_PARALLEL:-30}"
CONTINUE_ON_ERROR="${CONTINUE_ON_ERROR:-0}"

CLAUDE_TRACE="${CLAUDE_TRACE:-0}"
CLAUDE_DEBUG_FILTER="${CLAUDE_DEBUG_FILTER:-}"
CLAUDE_LIMIT_SEC="${CLAUDE_LIMIT_SEC:-}"
CLAUDE_LIMIT_KILL_GRACE="${CLAUDE_LIMIT_KILL_GRACE:-5}"

mkdir -p "${OUT_DIR}"

format_duration() {
  local total="$1"
  local h m s
  h=$((total / 3600))
  m=$(((total % 3600) / 60))
  s=$((total % 60))
  printf '%02d:%02d:%02d' "${h}" "${m}" "${s}"
}

print_progress() {
  local done="$1"
  local total="$2"
  local ok="$3"
  local failed="$4"
  local active="$5"
  local started_at="$6"
  local now elapsed pct filled width eta avg remaining
  local bar

  now="$(date +%s)"
  elapsed=$((now - started_at))
  width=24

  if [[ "${total}" -gt 0 ]]; then
    pct=$((done * 100 / total))
    filled=$((done * width / total))
  else
    pct=0
    filled=0
  fi

  bar="$(printf '%*s' "${filled}" '' | tr ' ' '#')"
  bar="${bar}$(printf '%*s' "$((width - filled))" '' | tr ' ' '-')"

  if [[ "${done}" -gt 0 ]]; then
    avg=$((elapsed / done))
    remaining=$((total - done))
    eta=$((avg * remaining))
    echo "scoring: progress [${bar}] ${done}/${total} (${pct}%) ok=${ok} failed=${failed} active=${active} elapsed=$(format_duration "${elapsed}") eta=$(format_duration "${eta}")" >&2
  else
    echo "scoring: progress [${bar}] ${done}/${total} (${pct}%) ok=${ok} failed=${failed} active=${active} elapsed=$(format_duration "${elapsed}") eta=--:--:--" >&2
  fi
}

# Prefer solution.md; otherwise first benchmark/challenges/challenge-NN/solution* file.
solution_src_for_challenge() {
  local chal="$1"
  if [[ -f "${chal}/solution.md" ]]; then
    printf '%s\n' "${chal}/solution.md"
    return 0
  fi
  local f
  for f in "${chal}"/solution*; do
    if [[ -f "${f}" ]]; then
      printf '%s\n' "${f}"
      return 0
    fi
  done
  return 1
}

build_prompt() {
  local nn="$1"
  local wd="$2"
  local sol_base="$3"

  cat <<EOF
SCORING ONLY.

Conformance: \`BENCHMARK.md\` Scoring Phase plus the **Scoring prompt template** from Appendix A — adapted here to a strictly two-file workspace (frozen Findings artifact + authoritative \`solution*\` excerpt only; no spoiler README batching for this scripted run).

Benchmark challenge index: ${nn}

You judge **only** the verbatim frozen Findings artifact for this index against answer material **for the same challenge** — pairing integrity: Findings(${nn}) paired with authoritative solution material for challenge-${nn}. Do not assume any other codebase or challenge directories exist beyond the staged files below.

## Staged workspace (strict)

Read ONLY these two paths (nothing else):

1. ${wd}/findings.txt — verbatim frozen Findings artifact for NN=${nn}.
2. ${wd}/${sol_base} — authoritative answer material (solution*, copied from the upstream challenge repo for this NN).

Forbidden: scanning parent directories of this workspace; reading invented paths; importing unrelated sessions; rewriting the frozen findings; reading any README or spoiler outside these two files (optional README beyond solution* is deliberately omitted from this staged run).

## Verdict taxonomy (semantic, not template matching)

Use exactly one verdict label:

- \`correct\` — intended primary issue from answer material is materially present and materially right in the findings.
- \`partially_correct\` — directionally right but incomplete/imprecise, or wrong specifics materially blur the intended primary issue.
- \`incorrect\` — intended primary issue missed or the findings are mostly unrelated/wrong.

Calibration (semantic policy):

- Generic but correct class / trust-boundary / fix direction aligned with the intended issue may still be \`correct\`.
- Specific but wrong exploitation mechanics should downgrade toward \`partially_correct\`.
- Valid secondary issues do **not** penalize alignment with the **primary** intended issue.

Then output clearly:

Challenge: ${nn}
Primary intended issue: <one sentence from answer material>
Verdict: correct|partially_correct|incorrect
Rationale: <one sentence grounded in both files>
Bonus findings: <one short line acknowledging valid extras, or "none">

Do not append WORKER_OK, WORKER_FAIL, or any machine footer lines after this body.
EOF
}

run_one() {
  local nn="$1"
  (
    local chal="${BENCH_ROOT}/challenges/challenge-${nn}"
    local findings_src="${FINDINGS_DIR}/${nn}.txt"
    local out="${OUT_DIR}/${nn}.txt"
    local out_tmp="${out}.tmp"
    local solution_src sol_base stage completed=0

    cleanup_stage() {
      if [[ "${completed}" -ne 1 ]] && [[ -f "${out_tmp}" ]]; then
        rm -f "${out_tmp}"
      fi
      if [[ -n "${stage:-}" ]] && [[ -d "${stage}" ]]; then
        rm -rf "${stage}"
      fi
    }
    trap cleanup_stage EXIT INT TERM

    if [[ ! -f "${findings_src}" ]]; then
      echo "scoring: skip (missing findings ${findings_src})" >&2
      return 1
    fi
    if [[ ! -d "${chal}" ]]; then
      echo "scoring: skip (missing ${chal})" >&2
      return 1
    fi
    if ! solution_src="$(solution_src_for_challenge "${chal}")"; then
      echo "scoring: no solution* under ${chal}" >&2
      return 1
    fi
    sol_base="$(basename "${solution_src}")"

    stage="$(mktemp -d "${TMPDIR:-/tmp}/appsec-scoring-${nn}.XXXXXX")"
    cp "${findings_src}" "${stage}/findings.txt"
    cp "${solution_src}" "${stage}/${sol_base}"

    local -a cc_args=(
      --print
      --no-session-persistence
      --output-format text
      --permission-mode dontAsk
    )

    if [[ "${CLAUDE_TRACE}" == "1" ]]; then
      cc_args+=(--verbose)
      cc_args+=(--debug-file "${OUT_DIR}/${nn}.trace.log")
      if [[ -n "${CLAUDE_DEBUG_FILTER}" ]]; then
        cc_args+=(-d "${CLAUDE_DEBUG_FILTER}")
      fi
      echo "scoring: trace -> ${OUT_DIR}/${nn}.trace.log" >&2
    fi

    echo "scoring: challenge-${nn} project=${stage} -> ${out}" >&2

    local prompt
    prompt="$(build_prompt "${nn}" "${stage}" "${sol_base}")"

    local -a run
    if [[ -n "${CLAUDE_LIMIT_SEC}" ]]; then
      if ! command -v timeout >/dev/null 2>&1; then
        echo "scoring: CLAUDE_LIMIT_SEC is set but timeout(1) not found on PATH" >&2
        return 1
      fi
      echo "scoring: per-worker time limit CLAUDE_LIMIT_SEC=${CLAUDE_LIMIT_SEC}s" >&2
      run=( timeout "-k${CLAUDE_LIMIT_KILL_GRACE}" "${CLAUDE_LIMIT_SEC}" "${CLAUDE_BIN}" "${cc_args[@]}" )
    else
      run=( "${CLAUDE_BIN}" "${cc_args[@]}" )
    fi

    if ! (
      cd "${stage}"
      printf '%s\n' "${prompt}" | "${run[@]}"
    ) >"${out_tmp}"; then
      return 1
    fi
    mv "${out_tmp}" "${out}"
    completed=1
    echo "scoring: wrote ${out}" >&2
  )
}

main() {
  if ! command -v "${CLAUDE_BIN}" >/dev/null 2>&1; then
    echo "scoring: '${CLAUDE_BIN}' not found. Install Claude Code or set CLAUDE=/path/to/claude" >&2
    exit 127
  fi

  declare -a run_list=()
  local i nn
  for i in $(seq "${START}" "${END}"); do
    nn="$(printf '%02d' "${i}")"
    run_list+=("${nn}")
  done

  if [[ "${MAX_PARALLEL}" -lt 1 ]]; then
    echo "scoring: MAX_PARALLEL must be >= 1" >&2
    exit 2
  fi

  local total done ok_count fail_count started_at
  total="${#run_list[@]}"
  done=0
  ok_count=0
  fail_count=0
  started_at="$(date +%s)"

  echo "scoring: starting ${total} challenge(s) (START=${START} END=${END} MAX_PARALLEL=${MAX_PARALLEL})" >&2
  print_progress "${done}" "${total}" "${ok_count}" "${fail_count}" 0 "${started_at}"

  if [[ "${MAX_PARALLEL}" -eq 1 ]]; then
    for nn in "${run_list[@]}"; do
      if run_one "${nn}"; then
        ok_count=$((ok_count + 1))
      elif [[ "${CONTINUE_ON_ERROR}" == "1" ]]; then
        fail_count=$((fail_count + 1))
        echo "scoring: FAILED challenge-${nn} (continuing)" >&2
      else
        fail_count=$((fail_count + 1))
        done=$((done + 1))
        print_progress "${done}" "${total}" "${ok_count}" "${fail_count}" 0 "${started_at}"
        echo "scoring: FAILED challenge-${nn}" >&2
        exit 1
      fi
      done=$((done + 1))
      print_progress "${done}" "${total}" "${ok_count}" "${fail_count}" 0 "${started_at}"
    done
    exit 0
  fi

  declare -a pids=()
  local pid failed=0 active_count=0
  for nn in "${run_list[@]}"; do
    while [[ "${#pids[@]}" -ge "${MAX_PARALLEL}" ]]; do
      if ! wait "${pids[0]}"; then
        failed=1
        fail_count=$((fail_count + 1))
        if [[ "${CONTINUE_ON_ERROR}" != "1" ]]; then
          echo "scoring: a worker exited non-zero while throttling (${pids[0]})" >&2
        fi
      else
        ok_count=$((ok_count + 1))
      fi
      done=$((done + 1))
      pids=("${pids[@]:1}")
      active_count=$((active_count - 1))
      print_progress "${done}" "${total}" "${ok_count}" "${fail_count}" "${active_count}" "${started_at}"
    done
    ( run_one "${nn}" ) &
    pids+=("$!")
    active_count=$((active_count + 1))
    print_progress "${done}" "${total}" "${ok_count}" "${fail_count}" "${active_count}" "${started_at}"
  done
  for pid in "${pids[@]}"; do
    if ! wait "${pid}"; then
      failed=1
      fail_count=$((fail_count + 1))
      if [[ "${CONTINUE_ON_ERROR}" != "1" ]]; then
        echo "scoring: worker pid ${pid} exited non-zero" >&2
      fi
    else
      ok_count=$((ok_count + 1))
    fi
    done=$((done + 1))
    active_count=$((active_count - 1))
    print_progress "${done}" "${total}" "${ok_count}" "${fail_count}" "${active_count}" "${started_at}"
  done

  if [[ "${failed}" -eq 1 ]] && [[ "${CONTINUE_ON_ERROR}" != "1" ]]; then
    exit 1
  fi
}

main "$@"
