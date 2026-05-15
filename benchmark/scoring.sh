#!/usr/bin/env bash
# Score frozen Findings from benchmark/artifacts/findings/NN.txt against authoritative
# answer material for the same NN, per BENCHMARK.md (two-phase blind find ->
# judge). Staged workspace contains exactly two files: verbatim findings plus
# one solution file from benchmark/challenges/challenge-NN/.
#
# stdout is saved as benchmark/artifacts/scoring/NN.txt.
#
# Usage (defaults: start=1 end=30 parallel=30):
#   ./benchmark/scoring.sh --model sonnet
#   ./benchmark/scoring.sh --start 1 --end 5 --parallel 4 --model opus
#
# Optional: set CLAUDE=/path/to/claude if the binary is not on PATH.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
BENCH_ROOT="${SCRIPT_DIR}"
FINDINGS_DIR="${BENCH_ROOT}/artifacts/findings"
OUT_DIR="${BENCH_ROOT}/artifacts/scoring"
CLAUDE_BIN="${CLAUDE:-claude}"

mkdir -p "${OUT_DIR}"

parse_benchmark_cli() {
  local tag="scoring"

  START=1
  END=30
  MAX_PARALLEL=30
  CLAUDE_MODEL=""
  CLAUDE_TRACE=0

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --start)
        if [[ $# -lt 2 ]]; then echo "${tag}: --start requires a value" >&2; exit 2; fi
        START="$2"
        shift 2
        ;;
      --end)
        if [[ $# -lt 2 ]]; then echo "${tag}: --end requires a value" >&2; exit 2; fi
        END="$2"
        shift 2
        ;;
      --parallel)
        if [[ $# -lt 2 ]]; then echo "${tag}: --parallel requires a value" >&2; exit 2; fi
        MAX_PARALLEL="$2"
        shift 2
        ;;
      --model)
        if [[ $# -lt 2 ]]; then echo "${tag}: --model requires a value (e.g. sonnet, opus)" >&2; exit 2; fi
        CLAUDE_MODEL="$2"
        shift 2
        ;;
      --trace)
        CLAUDE_TRACE=1
        shift
        ;;
      -h|--help)
        cat <<EOF >&2
Usage: ./benchmark/scoring.sh [options]

Options:
  --start N       First challenge index (default: 1)
  --end N         Last challenge index (default: 30)
  --parallel N    Max concurrent workers (default: 30)
  --model ID      Pass-through to claude --model (alias or full id)
  --trace         Verbose claude logs + benchmark/artifacts/scoring/NN.trace.log

Optional env: CLAUDE=/path/to/claude
EOF
        exit 0
        ;;
      *)
        echo "${tag}: unknown argument: $1" >&2
        echo "Run: ./benchmark/scoring.sh --help" >&2
        exit 2
        ;;
    esac
  done

  if ! [[ "${START}" =~ ^[1-9][0-9]*$ ]]; then
    echo "${tag}: --start must be a positive integer (got: ${START})" >&2
    exit 2
  fi
  if ! [[ "${END}" =~ ^[1-9][0-9]*$ ]]; then
    echo "${tag}: --end must be a positive integer (got: ${END})" >&2
    exit 2
  fi
  if ! [[ "${MAX_PARALLEL}" =~ ^[1-9][0-9]*$ ]]; then
    echo "${tag}: --parallel must be a positive integer (got: ${MAX_PARALLEL})" >&2
    exit 2
  fi
  if [[ "${END}" -lt "${START}" ]]; then
    echo "${tag}: --end must be >= --start" >&2
    exit 2
  fi
}

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
    if [[ -n "${CLAUDE_MODEL}" ]]; then
      cc_args+=(--model "${CLAUDE_MODEL}")
    fi

    if [[ "${CLAUDE_TRACE}" == "1" ]]; then
      cc_args+=(--verbose)
      cc_args+=(--debug-file "${OUT_DIR}/${nn}.trace.log")
      echo "scoring: trace -> ${OUT_DIR}/${nn}.trace.log" >&2
    fi

    echo "scoring: challenge-${nn} project=${stage} -> ${out}" >&2

    local prompt
    prompt="$(build_prompt "${nn}" "${stage}" "${sol_base}")"

    if ! (
      cd "${stage}"
      printf '%s\n' "${prompt}" | "${CLAUDE_BIN}" "${cc_args[@]}"
    ) >"${out_tmp}"; then
      return 1
    fi
    mv "${out_tmp}" "${out}"
    completed=1
    echo "scoring: wrote ${out}" >&2
  )
}

main() {
  parse_benchmark_cli "$@"

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

  local total done ok_count fail_count started_at
  total="${#run_list[@]}"
  done=0
  ok_count=0
  fail_count=0
  started_at="$(date +%s)"

  echo "scoring: starting ${total} challenge(s) (start=${START} end=${END} parallel=${MAX_PARALLEL} model=${CLAUDE_MODEL:-default} trace=${CLAUDE_TRACE})" >&2
  print_progress "${done}" "${total}" "${ok_count}" "${fail_count}" 0 "${started_at}"

  if [[ "${MAX_PARALLEL}" -eq 1 ]]; then
    for nn in "${run_list[@]}"; do
      if run_one "${nn}"; then
        ok_count=$((ok_count + 1))
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
        echo "scoring: a worker exited non-zero while throttling (${pids[0]})" >&2
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
      echo "scoring: worker pid ${pid} exited non-zero" >&2
    else
      ok_count=$((ok_count + 1))
    fi
    done=$((done + 1))
    active_count=$((active_count - 1))
    print_progress "${done}" "${total}" "${ok_count}" "${fail_count}" "${active_count}" "${started_at}"
  done

  if [[ "${failed}" -eq 1 ]]; then
    exit 1
  fi
}

main "$@"
