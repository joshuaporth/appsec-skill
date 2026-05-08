---
name: learn
description: >-
  Generates a post-run feedback learning brief from benchmark artifacts. Use
  after scoreboard/scoring outputs to extract recurring patterns, mistakes,
  wins, and next-step improvement actions for the benchmark process.
disable-model-invocation: true
---

# Learn

Create a separate feedback-learning output from benchmark artifacts. This skill
is intentionally independent from scoreboard generation.

## Purpose

Produce a concise learning brief that helps improve future benchmark runs.
Focus on patterns and actions, not rerunning scoring.

## Inputs (default)

- `benchmark/artifacts/scoring/*.txt` (required)
- `benchmark/artifacts/findings/*.txt` (optional but recommended)
- generated scoreboard output (optional context)

If an input set is missing, continue with available artifacts and state limits.

## Method

1. Read all available scoring artifacts.
2. Optionally correlate with findings artifacts for root-cause context.
3. Extract repeated themes:
   - where outcomes were strong,
   - where outcomes were partial/incorrect/unknown,
   - recurring reasoning or evidence-quality issues,
   - recurring remediation-quality issues.
4. Turn themes into concrete process improvements for the next run.

## Output format

Use this structure:

```markdown
# Learning brief

## Observed patterns
- <pattern 1>
- <pattern 2>
- <pattern 3>

## What improved outcomes
- <high-signal behaviors that correlated with correct judgments>

## What hurt outcomes
- <failure modes and recurring quality gaps>

## Next iteration actions
1. <specific action>
2. <specific action>
3. <specific action>

## Experiments for next run
- <small measurable process experiment>
- <small measurable process experiment>
```

## Rules

- Keep recommendations actionable and benchmark-specific.
- Ground claims in artifact content; do not invent evidence.
- Prefer 3-7 bullets per section and 3-5 actions total.
- Keep this output separate from scoreboard output.
