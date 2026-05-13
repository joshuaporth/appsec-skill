---
name: appsec
version: 0.2.0
spec_version: 1
description: >-
  Performs senior-grade application security code review: three-pass methodology,
  OWASP/CWE-oriented vulnerability analysis, language-specific dangerous patterns,
  cryptography checks, structured findings, and concrete remediations. Use when
  analyzing source code for security vulnerabilities, reviewing changes for
  AppSec issues, or when the user asks for a security review, threat modeling
  of implementation, or secure coding feedback.
---

# AppSec Skill

When this skill is active, you conduct secure code review with the rigor of a senior application security engineer. Analyze source code for security vulnerabilities accordingly.

## When to use

- Security review of files, directories, or pull requests
- Any request to find vulnerabilities, unsafe patterns, or crypto misuse
- Structured reporting that matches this repository’s finding schema

## Before touching application code

Read these modules **in order** (paths are relative to this skill folder). They define mindset, methodology, coverage, and output rules.

1. [references/00-identity.md](references/00-identity.md) — mindset, expertise scope, hard rules  
2. [references/01-methodology.md](references/01-methodology.md) — three-pass code review  
3. [references/02-vulnerability-classes.md](references/02-vulnerability-classes.md) — vulnerability catalog and detection  
4. [references/03-language-specific.md](references/03-language-specific.md) — per-language dangerous patterns  
5. [references/04-cryptography.md](references/04-cryptography.md) — cryptography checks  
6. [references/05-output-format.md](references/05-output-format.md) — structured findings  
7. [references/06-remediation.md](references/06-remediation.md) — code-level remediations  

## Invocation examples

**Single file:** load this skill, then analyze `<path/to/file>` for security vulnerabilities.

**Directory:** load this skill, then analyze all source files under `<path/to/dir/>` for security vulnerabilities.

Editors that support the [Agent Skills](https://cursor.com/docs/skills) layout discover this folder as a skill; load [`SKILL.md`](SKILL.md) first, then the `references/` chain it lists.
