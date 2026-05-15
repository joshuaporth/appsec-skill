#!/usr/bin/env bash
# Stage each challenge (excluding blind Findings paths per BENCHMARK.md), copy the
# AppSec skill into the stage as project-local Claude skills, run Claude Code with
# cwd = temp directory (standalone project root), stdin: /appsec
#
# stdout is saved as benchmark/artifacts/findings/NN.txt.
#
# Usage (defaults: start=1 end=30 parallel=30):
#   ./benchmark/findings.sh --model sonnet
#   ./benchmark/findings.sh --start 1 --end 5 --parallel 4 --model opus
#   ./benchmark/findings.sh --trace --start 1 --end 1 --model sonnet
#
# Optional: set CLAUDE=/path/to/claude if the binary is not on PATH.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
BENCH_ROOT="${SCRIPT_DIR}"
OUT_DIR="${BENCH_ROOT}/artifacts/findings"
CLAUDE_BIN="${CLAUDE:-claude}"

mkdir -p "${OUT_DIR}"

parse_benchmark_cli() {
  local tag="findings"

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
Usage: ./benchmark/findings.sh [options]

Options:
  --start N       First challenge index (default: 1)
  --end N         Last challenge index (default: 30)
  --parallel N    Max concurrent workers (default: 30)
  --model ID      Pass-through to claude --model (alias or full id)
  --trace         Verbose claude logs + benchmark/artifacts/findings/NN.trace.log

Optional env: CLAUDE=/path/to/claude
EOF
        exit 0
        ;;
      *)
        echo "${tag}: unknown argument: $1" >&2
        echo "Run: ./benchmark/findings.sh --help" >&2
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
    if [[ -n "${CLAUDE_MODEL}" ]]; then
      cc_args+=(--model "${CLAUDE_MODEL}")
    fi

    if [[ "${CLAUDE_TRACE}" == "1" ]]; then
      cc_args+=(--verbose)
      cc_args+=(--debug-file "${OUT_DIR}/${nn}.trace.log")
      echo "findings: trace -> ${OUT_DIR}/${nn}.trace.log (tail -f in another terminal)" >&2
    fi

    echo "findings: challenge-${nn} project=${stage} -> /appsec -> ${out}" >&2

    if ! (
      cd "${stage}"
      printf '/appsec\n' | "${CLAUDE_BIN}" "${cc_args[@]}"
    ) >"${out_tmp}"; then
      return 1
    fi

    mv "${out_tmp}" "${out}"
    completed=1
    echo "findings: wrote ${out}" >&2
  )
}

main() {
  parse_benchmark_cli "$@"

  if ! command -v "${CLAUDE_BIN}" >/dev/null 2>&1; then
    echo "findings: '${CLAUDE_BIN}' not found. Install Claude Code or set CLAUDE=/path/to/claude" >&2
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

  echo "findings: starting ${total} challenge(s) (start=${START} end=${END} parallel=${MAX_PARALLEL} model=${CLAUDE_MODEL:-default} trace=${CLAUDE_TRACE})" >&2
  print_progress "${done}" "${total}" "${ok_count}" "${fail_count}" 0 "${started_at}"

  if [[ "${MAX_PARALLEL}" -eq 1 ]]; then
    for nn in "${run_list[@]}"; do
      if run_challenge "${nn}"; then
        ok_count=$((ok_count + 1))
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
        echo "findings: a worker exited non-zero while throttling (${pids[0]})" >&2
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
      echo "findings: worker pid ${pid} exited non-zero" >&2
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
