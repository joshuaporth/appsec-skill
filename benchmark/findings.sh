#!/usr/bin/env bash
# Stage each challenge (excluding blind Findings paths per BENCHMARK.md), copy the
# AppSec skill into the stage as project-local Claude skills, run Claude Code with
# cwd = temp directory (standalone project root), stdin: /appsec
#
# Layout after staging:
#   <stage>/.claude/skills/appsec/SKILL.md
#   <stage>/.claude/skills/appsec/references/*.md   (mirror of repo skill/)
#   <stage>/...challenge files...
#
# stdout is saved as benchmark/artifacts/findings/NN.txt.
#
# Watching long runs (--print + text waits for the full turn; no partial stdout):
#   CLAUDE_TRACE=1 ./benchmark/findings.sh
# Enables --verbose (stderr) and --debug-file benchmark/artifacts/findings/NN.trace.log —
# tail that file while the invocation runs:
#   tail -f benchmark/artifacts/findings/01.trace.log
#
# Optional: narrow debug noise — CLAUDE_DEBUG_FILTER=api,hooks  (passed to `claude -d`)
#
# If a challenge never completes (looks like bash "won't exit"), this script is blocked
# on the Claude Code child. Cap wall time per challenge (GNU coreutils timeout(1)):
#   CLAUDE_LIMIT_SEC=1800 START=1 END=1 ./benchmark/findings.sh
# CLAUDE_LIMIT_KILL_GRACE (default 5) is SIGTERM→SIGKILL seconds for timeout -k.
#
# Parallelism (same pattern as benchmark/scoring.sh; cap concurrent Claude workers):
#   MAX_PARALLEL=8 ./benchmark/findings.sh
# Serial (one challenge at a time — previous default behavior):
#   MAX_PARALLEL=1 ./benchmark/findings.sh
#
# Usage:
#   ./benchmark/findings.sh
#   START=1 END=5 MAX_PARALLEL=4 ./benchmark/findings.sh
#   CLAUDE_TRACE=1 START=1 END=1 ./benchmark/findings.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
BENCH_ROOT="${SCRIPT_DIR}"
OUT_DIR="${BENCH_ROOT}/artifacts/findings"
CLAUDE_BIN="${CLAUDE:-claude}"

START="${START:-1}"
END="${END:-30}"
MAX_PARALLEL="${MAX_PARALLEL:-30}"
CONTINUE_ON_ERROR="${CONTINUE_ON_ERROR:-0}"

# Set CLAUDE_TRACE=1 for progress-style logs alongside the final NN.txt transcript.
CLAUDE_TRACE="${CLAUDE_TRACE:-0}"
CLAUDE_DEBUG_FILTER="${CLAUDE_DEBUG_FILTER:-}"

# Optional per-challenge wall clock (requires timeout(1), e.g. /usr/bin/timeout).
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
    echo "findings: progress [${bar}] ${done}/${total} (${pct}%) ok=${ok} failed=${failed} active=${active} elapsed=$(format_duration "${elapsed}") eta=$(format_duration "${eta}")" >&2
  else
    echo "findings: progress [${bar}] ${done}/${total} (${pct}%) ok=${ok} failed=${failed} active=${active} elapsed=$(format_duration "${elapsed}") eta=--:--:--" >&2
  fi
}

stage_challenge() {
  local src="$1"
  local dst="$2"
  mkdir -p "${dst}"
  if ! command -v rsync >/dev/null 2>&1; then
    echo "findings: rsync is required for staging (excludes)" >&2
    return 1
  fi
  rsync -a \
    --exclude 'README.md' \
    --exclude 'solution*' \
    --exclude '*exploit*' \
    --exclude 'safe*' \
    --exclude 'Safe*' \
    "${src}/" "${dst}/"
}

# Repo canonical skill lives at skill/. Install as Claude Code discovery path.
install_skill_in_stage() {
  local stage="$1"
  mkdir -p "${stage}/.claude/skills/appsec"
  rsync -a "${REPO_ROOT}/skill/" "${stage}/.claude/skills/appsec/" || return 1
}

run_challenge() {
  local nn="$1"
  (
    local chal="${BENCH_ROOT}/challenges/challenge-${nn}"
    local out="${OUT_DIR}/${nn}.txt"
    local out_tmp="${out}.tmp"
    local stage completed=0
    stage="$(mktemp -d "${TMPDIR:-/tmp}/appsec-challenge-${nn}.XXXXXX")"

    cleanup_stage() {
      if [[ "${completed}" -ne 1 ]] && [[ -f "${out_tmp}" ]]; then
        rm -f "${out_tmp}"
      fi
      if [[ -n "${stage:-}" ]] && [[ -d "${stage}" ]]; then
        rm -rf "${stage}"
      fi
    }
    trap cleanup_stage EXIT INT TERM

    if [[ ! -d "${chal}" ]]; then
      echo "findings: skip (missing ${chal})" >&2
      return 1
    fi

    if ! stage_challenge "${chal}" "${stage}"; then
      return 1
    fi

    if ! install_skill_in_stage "${stage}"; then
      return 1
    fi

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
      echo "findings: trace -> ${OUT_DIR}/${nn}.trace.log (tail -f in another terminal)" >&2
    fi

    echo "findings: challenge-${nn} project=${stage} -> /appsec -> ${out}" >&2

    local -a run
    if [[ -n "${CLAUDE_LIMIT_SEC}" ]]; then
      if ! command -v timeout >/dev/null 2>&1; then
        echo "findings: CLAUDE_LIMIT_SEC is set but timeout(1) not found on PATH" >&2
        return 1
      fi
      echo "findings: per-challenge time limit CLAUDE_LIMIT_SEC=${CLAUDE_LIMIT_SEC}s" >&2
      run=( timeout "-k${CLAUDE_LIMIT_KILL_GRACE}" "${CLAUDE_LIMIT_SEC}" "${CLAUDE_BIN}" "${cc_args[@]}" )
    else
      run=( "${CLAUDE_BIN}" "${cc_args[@]}" )
    fi

    # cwd = staged project root; stdin is only /appsec (skill + codebase both under stage).
    if ! (
      cd "${stage}"
      printf '/appsec\n' | "${run[@]}"
    ) >"${out_tmp}"; then
      return 1
    fi

    mv "${out_tmp}" "${out}"
    completed=1
    echo "findings: wrote ${out}" >&2
  )
}

main() {
  if ! command -v "${CLAUDE_BIN}" >/dev/null 2>&1; then
    echo "findings: '${CLAUDE_BIN}' not found. Install Claude Code or set CLAUDE=/path/to/claude" >&2
    exit 127
  fi

  if [[ "${MAX_PARALLEL}" -lt 1 ]]; then
    echo "findings: MAX_PARALLEL must be >= 1" >&2
    exit 2
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

  echo "findings: starting ${total} challenge(s) (START=${START} END=${END} MAX_PARALLEL=${MAX_PARALLEL})" >&2
  print_progress "${done}" "${total}" "${ok_count}" "${fail_count}" 0 "${started_at}"

  if [[ "${MAX_PARALLEL}" -eq 1 ]]; then
    for nn in "${run_list[@]}"; do
      if run_challenge "${nn}"; then
        ok_count=$((ok_count + 1))
      elif [[ "${CONTINUE_ON_ERROR}" == "1" ]]; then
        fail_count=$((fail_count + 1))
        echo "findings: FAILED challenge-${nn} (continuing)" >&2
      else
        fail_count=$((fail_count + 1))
        done=$((done + 1))
        print_progress "${done}" "${total}" "${ok_count}" "${fail_count}" 0 "${started_at}"
        echo "findings: FAILED challenge-${nn}" >&2
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
          echo "findings: a worker exited non-zero while throttling (${pids[0]})" >&2
        fi
      else
        ok_count=$((ok_count + 1))
      fi
      done=$((done + 1))
      pids=("${pids[@]:1}")
      active_count=$((active_count - 1))
      print_progress "${done}" "${total}" "${ok_count}" "${fail_count}" "${active_count}" "${started_at}"
    done
    ( run_challenge "${nn}" ) &
    pids+=("$!")
    active_count=$((active_count + 1))
    print_progress "${done}" "${total}" "${ok_count}" "${fail_count}" "${active_count}" "${started_at}"
  done
  for pid in "${pids[@]}"; do
    if ! wait "${pid}"; then
      failed=1
      fail_count=$((fail_count + 1))
      if [[ "${CONTINUE_ON_ERROR}" != "1" ]]; then
        echo "findings: worker pid ${pid} exited non-zero" >&2
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
