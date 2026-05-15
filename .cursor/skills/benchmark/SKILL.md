---
name: benchmark
description: >-
  Runs the full 30-challenge secure-code-review benchmark end-to-end via scripts:
  Findings (parallel across 01-30), then Scoring (parallel across 01-30), then
  scoreboard generation from frozen scoring artifacts.
  Invoke from Cursor Agent with /benchmark.
disable-model-invocation: true
---

# Benchmark (scripted full pipeline)

Run exactly one non-interactive workflow for challenges `01..30`:

1. Findings pass on all 30 challenges in parallel.
2. Scoring pass on all 30 challenges in parallel (after Findings finishes).
3. Scoreboard generation from scoring artifacts only.

Challenges `31` and `32` are out of scope.

## Preconditions (fail closed)

Before dispatch:

- Ensure `benchmark/challenges/challenge-01` .. `benchmark/challenges/challenge-30` exist.
- Ensure `benchmark/findings.sh` and `benchmark/scoring.sh` exist and are executable.
- Ensure `claude` is available on PATH (or set `CLAUDE=/path/to/claude`).

If any precondition fails, stop and report an abort block (no partial run output).

## Required execution order

Never interleave phases:

1. Findings script for all `01..30` (parallel workers).
2. Wait for Findings completion and verify artifacts.
3. Scoring script for all `01..30` (parallel workers).
4. Wait for Scoring completion and verify artifacts.
5. Generate scoreboard from `benchmark/artifacts/scoring/*.txt` only.

## Script commands (canonical)

Run from repo root. CLI flags only (see `./benchmark/findings.sh --help`):

| Flag | Default |
|------|---------|
| `--start` | `1` |
| `--end` | `30` |
| `--parallel` | `30` |
| `--model` | Claude default if omitted |
| `--trace` | off (debug: writes `NN.trace.log` under artifacts) |

Full run (`01..30`, 30 workers):

```bash
./benchmark/findings.sh --model sonnet
./benchmark/scoring.sh --model sonnet
```

Subset or retry (example: challenge 15 only, serial):

```bash
./benchmark/findings.sh --start 15 --end 15 --parallel 1 --model sonnet
./benchmark/scoring.sh --start 15 --end 15 --parallel 1 --model sonnet
```

Notes:

- Findings must fully finish before Scoring starts.
- Optional env: `CLAUDE=/path/to/claude` if the binary is not on PATH.
- Do not substitute with ad-hoc per-challenge Task orchestration for this skill.

## Artifact completeness gates

After Findings:

- Require exactly 30 findings files: `benchmark/artifacts/findings/01.txt` .. `30.txt`.
- If missing or malformed outputs are detected, abort before Scoring.

After Scoring:

- Require exactly 30 scoring files: `benchmark/artifacts/scoring/01.txt` .. `30.txt`.
- If missing or malformed outputs are detected, abort before scoreboard generation.

## Scoreboard step

After successful scoring completeness:

- Generate the canonical benchmark scoreboard from
  `benchmark/artifacts/scoring/*.txt` only.
- Use the `scoreboard` skill (`.cursor/skills/scoreboard/SKILL.md`) for rendering
  rules (table, glyphs, Pulse, ordering).

## Non-interactive run requirement

`/benchmark` should run continuously through all phases without midpoint prompts,
unless blocked by an external dependency (permissions/runtime/tool failure).
