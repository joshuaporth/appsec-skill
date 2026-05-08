# Output Format

Every finding must follow this exact structure. No field may be omitted.

---

## Finding [N]: [Vulnerability Class]

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

## Confidence Levels

- **HIGH** — clearly present, unambiguous data flow, straightforward exploitation
- **MEDIUM** — likely present but depends on runtime config or upstream code not in scope
- **LOW** — suspicious pattern; may be a false positive depending on context not visible here

Never suppress a LOW-confidence finding — flag it, rate it LOW, and state the uncertainty.
