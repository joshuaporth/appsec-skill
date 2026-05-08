---
name: scoreboard
description: >-
  Builds the benchmark markdown scoreboard (table and Pulse) from
  `benchmark/artifacts/scoring/*.txt`. Use when the user asks for a scoreboard from current
  scoring artifacts without rerunning findings or scoring.
disable-model-invocation: true
---

# Scoreboard

Generate the scoreboard from existing scoring artifacts only.

## Inputs

- Read `benchmark/artifacts/scoring/*.txt`.
- Each scoring artifact is expected to contain:
  - `Challenge: NN`
  - `Primary intended issue: ...`
  - `Verdict: correct|partially_correct|incorrect`
  - `Rationale: ...`
  - `Bonus findings: ...` (optional)
- Do not read `benchmark/challenges/` or rewrite findings during scoreboard generation.

## Output format

### Title block

```text
# Benchmark scoreboard

━━━━━━━━━━━━━━━━━━━━━━  scored challenges · blind find -> judge  ━━━━━━━━━━━━━━━━━━━━━━
```

### Glyphs

| Glyph | Meaning |
|:-----:|---------|
| 🟢 | Hit (`correct`) |
| 🟡 | Part (`partially_correct`) |
| 🔴 | Miss (`incorrect`) |
| ⚪ | Unknown (missing or malformed scoring artifact) |

### Results table

Use this header exactly:

```markdown
|  #  |     | Intended issue (<=72 chars) | Judge notes (<=96 chars) |
| :-: | :-: | :--------------------------- | :----------------------- |
```

Rows:
- Include discovered challenge rows only.
- Sort rows by challenge id ascending.
- One glyph per row (`🟢/🟡/🔴/⚪`).
- Keep ASCII pipes and table column order unchanged.

### Pulse

After the table, emit:

```markdown
### Pulse

**🟢 n · 🟡 p · 🔴 m** - <one sentence>
```

Replace `n`, `p`, `m` with counts from the rendered table. If any unknown rows
exist, mention the unknown count (`⚪`) in the sentence.

## Parsing and row construction

1. Scan `benchmark/artifacts/scoring/*.txt`.
2. For each file, extract `NN` from filename and/or `Challenge:`.
3. Determine row status:
   - `🟢` for `Verdict: correct`
   - `🟡` for `Verdict: partially_correct`
   - `🔴` for `Verdict: incorrect`
   - `⚪` if required fields are missing/malformed
4. Build columns:
   - `#`: two-digit `NN`
   - `Intended issue`: `Primary intended issue` (truncate to 72 chars)
   - `Judge notes`: `Rationale` (optionally enrich with `Bonus findings`,
     non-redundant only, truncate to 96 chars)
5. Unknown-row fallback text:
   - Intended issue: `- (unknown scoring artifact)`
   - Judge notes: `Unknown scoring output for this challenge.`
6. If two files map to the same `NN`, keep the newest file and mention
   deduplication in the pulse sentence.

## What not to do

- Do not output unsorted or duplicate challenge rows.
- Do not add/remove/reorder table columns.
- Do not change glyph meanings.
