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

Run from repo root:

```bash
START=1 END=30 MAX_PARALLEL=30 ./benchmark/findings.sh
START=1 END=30 MAX_PARALLEL=30 ./benchmark/scoring.sh
```

Notes:

- Findings must fully finish before Scoring starts.
- Use script-level parallelism (`MAX_PARALLEL=30`) for both phases.
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
