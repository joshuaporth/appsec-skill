# Contributing

Small, focused pull requests are preferred. This repo encodes security-review guidance, so wording changes should stay precise, testable, and easy to audit.

## Before you open a PR

- Keep edits tightly scoped to the behavior or guidance you are changing.
- Preserve the numbered loading order in `skill/SKILL.md` unless you are intentionally introducing a new module.
- Prefer concrete attack paths, exact sinks, and explicit uncertainty boundaries over broader or more dramatic wording.
- When changing a vulnerability class, make sure the remediation guidance still matches the detection guidance.

## Which file should change?

- Update `skill/references/02-vulnerability-classes.md` when you are expanding an existing class or adding a closely related detection checklist.
- Add a new numbered reference only when the topic is large enough to deserve its own loading step and can stay coherent as a standalone module.
- Update `skill/references/03-language-specific.md` for language or framework foot-guns that fit the existing "Flag / Safe alternatives" pattern.
- Update `skill/references/05-output-format.md` when changing report schema or machine-readable mapping expectations.

## Evaluation harness (optional)

Most contributions target `skill/` and docs only. If you change benchmark artifacts or harness scripts:

- Benchmark challenges and fixtures live in submodules: [`benchmark/challenges/`](benchmark/challenges/) ([dub-flow/secure-code-review-challenges](https://github.com/dub-flow/secure-code-review-challenges)) and [`benchmark/synthetics/`](benchmark/synthetics/) ([secure-code-review-fixtures](https://github.com/joshuaporth/secure-code-review-fixtures)). Edit those upstream repos; bump the submodule pointer here only when pinning a new revision.
- Commit `benchmark/artifacts/findings/*.txt` and `benchmark/artifacts/scoring/*.txt` when they are intentional golden artifacts for comparison.
- Do not commit `*.trace.log` files or transient `*.txt.tmp` files from interrupted benchmark runs.
- Keep the maintainer harness frozen to challenges `01..30` unless the benchmark contract is intentionally revised.
- Run the harness via `./benchmark/findings.sh` and `./benchmark/scoring.sh` (see `--help` for flags).

## Validation

Run the repo validation script before opening a PR:

```bash
python3 scripts/validate_repo.py
```

This checks skill frontmatter, the ordered reference chain in `skill/SKILL.md`, and local markdown links used by the maintained docs.

After initializing `benchmark/synthetics`, CI and maintainers use the fixtures repo scripts directly (no wrappers in this repo):

```bash
python3 benchmark/synthetics/scripts/validate.py --core-only
./benchmark/synthetics/scripts/run_core_demos.sh
```
