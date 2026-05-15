# Output Format

Every finding must follow this exact structure. No field may be omitted.

---

## Finding [N]: [Vulnerability Class]

**Finding ID:** `APPSEC-[stable-id]`
**File:** `path/to/file.ext`
**Lines:** [start]–[end]
**CWE:** CWE-[ID] — [Name]
**OWASP Category:** [e.g., A03:2021 – Injection]
**Priority:** P1 | P2 | P3
**Severity:** CRITICAL | HIGH | MEDIUM | LOW | INFO
**Confidence:** HIGH | MEDIUM | LOW

### Vulnerable Code
```[language]
[exact snippet from the file — unmodified]
```

### Description
[2–4 sentences: what the vulnerability is, why this specific code is vulnerable,
what an attacker could do with it. Name the attack type, trace the data flow,
quantify the impact. Be specific.]

### Prioritization
[State this finding's relative priority for remediation using exploitability, impact,
and confidence. If not top priority, briefly note higher-priority findings.]

### Exploitability Notes
- **Exploit Preconditions:** [What must be true for exploitation]
- **Uncertainty Boundary:** [What unknown runtime/config factors might change impact]

### Remediation
[Language-appropriate fix with corrected code. See `06-remediation.md`.]

### References
- [Authoritative link — OWASP, CWE, or similar]

---

## After All Findings — Scan Summary

```
## Scan Summary

| Metric          | Value |
|-----------------|-------|
| Files Analyzed  | N     |
| Total Findings  | N     |
| Critical        | N     |
| High            | N     |
| Medium          | N     |
| Low             | N     |
| Info            | N     |

### Key Risks
[2–3 sentences on the most impactful issues and their combined risk.]
```

### Prioritization Notes (optional)
[Optional: 1-2 sentences explaining why findings are ordered this way (exploitability, impact, confidence).]

## Stable Finding IDs

Use a deterministic finding ID so reviews can be diffed across reruns and pull requests.

Recommended construction:

1. Start with the repository-relative file path.
2. Append the CWE id.
3. Append a normalized form of the vulnerable sink snippet (collapse whitespace; keep key function/operator names).
4. Hash that combined string with a stable hash (for example SHA-1 or SHA-256) and keep the first 10-12 hex characters.
5. Emit the final value as `APPSEC-<hash>`.

Guidance:

- The same issue in the same file should keep the same ID across wording changes in the report.
- If the vulnerable sink or file path materially changes, a new ID is acceptable.
- Never invent a random UUID for a finding; the ID must be reproducible from the evidence.

## Optional SARIF Mapping

When a downstream tool needs SARIF, preserve the human report above and map fields as follows:

| Report field | SARIF field |
|--------------|-------------|
| `Finding ID` | `partialFingerprints.primaryLocationLineHash` or `fingerprints.appsecFindingId` |
| `CWE` | `ruleId` and `taxa` |
| `Severity` | `level` (`error` for CRITICAL/HIGH, `warning` for MEDIUM, `note` for LOW/INFO) |
| `Description` | `message.text` |
| `File` + `Lines` | `locations[0].physicalLocation.artifactLocation.uri` and `region` |
| `OWASP Category`, `Confidence`, `Priority` | `properties.tags`, `properties.confidence`, `properties.priority` |

If emitting SARIF alongside markdown, keep the markdown report as the source of truth for defenders and use the deterministic finding ID to deduplicate results between formats.

## Confidence Levels

- **HIGH** — clearly present, unambiguous data flow, straightforward exploitation
- **MEDIUM** — likely present but depends on runtime config or upstream code not in scope
- **LOW** — suspicious pattern; may be a false positive depending on context not visible here

Never suppress a LOW-confidence finding — flag it, rate it LOW, and state the uncertainty.
