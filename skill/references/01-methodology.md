# Analysis Methodology

Every code review uses three passes. Never skip a pass, even for short files.

## Pass 1 — Triage (Map the Attack Surface)

1. Identify language(s) and frameworks
2. Map entry points: HTTP routes, CLI args, file uploads, API endpoints, message consumers — and any in-scope routing/cache/deploy config that can change request handling before application code runs
3. Map trust boundaries: what originates from users, from other services, from the filesystem?
4. Identify sensitive operations: auth checks, DB queries, file I/O, subprocess calls, crypto, sessions
5. Note third-party libraries — flag those that are dangerous if misused
6. If more than one layer is in scope (for example edge, gateway, app), trace path/Host/cache behavior at each hop; do not assume layers agree on normalization unless evidence shows they do. Compare encoding, `.` / `..` segments, trailing slashes, case, and byte handling only as needed by observed signals.

Output: an internal mental model of the attack surface (not shown to user).

## Pass 2 — Deep Scan (Hunt for Vulnerabilities)

For each entry point and sensitive operation:

1. Trace data flows: untrusted input → through transformations → to sinks
2. Check every sink against `02-vulnerability-classes.md`
3. Check all crypto against `04-cryptography.md`
4. Apply language checks from `03-language-specific.md`
5. Look for logic flaws: TOCTOU, race conditions, missing authorization on specific verbs
6. Look for information disclosure: stack traces in responses, secrets in comments, PII in logs
7. When both edge and app configs exist, validate how each layer parses the same request rather than relying on one layer's view. If redirects/response headers are built from request-derived values, evaluate CRLF (`\r\n`) header-injection risk (see `02-vulnerability-classes.md`).

### Deep-Dive Heuristics for Edge/App Nuance (conditional)

Run these checks only when code/config evidence suggests multi-layer routing/proxy behavior, request-derived redirect/header construction, or parser mismatch risk. Do not prioritize this section over other vulnerability classes without such signals.

1. **Re-parse path identity across hops:** compare edge rule semantics (`=`, prefix, regex) vs framework routing (`/admin`, `/admin/`, decoded forms) when route protection appears layer-dependent.
2. **Map normalization differences explicitly:** reason about percent-decoding depth, dot-segment handling (`.` / `..`), repeated slashes, case sensitivity, and byte acceptance/rejection only where those differences could change authorization or routing outcomes.
3. **Validate cross-layer authorization consistency:** if sensitive routes are protected at one layer, verify equivalent controls at other layers; report mismatch risk with confidence tied to available evidence.
4. **Audit header-construction sinks in config:** if redirects or headers concatenate request-derived values (URI/path variables, host, upstream-provided strings), analyze whether CRLF/control bytes can reach the **actually emitted response** — and classify CWE from that sink versus a separate SSRF outbound-fetch path (see `HTTP Response Splitting / Header Injection` in `02-vulnerability-classes.md`).
5. **Look for string-built redirect anti-patterns:** treat request-derived `Location` construction as open-redirect/header-injection risk unless strict allowlists or safe platform escaping is evident.
6. **Preserve uncertainty boundaries:** if exploitability depends on runtime parsing/version details not visible in scope, report with MEDIUM confidence and explicit assumptions.

### Deep-Dive Triggers for Other High-Risk Classes (conditional)

When evidence points to these areas, run targeted deep checks with the same rigor as edge/proxy analysis:

1. **Authorization and tenancy:** missing object/function-level auth, tenant boundary checks, and server-side ownership enforcement on every sensitive action.
2. **Deserialization and template execution:** untrusted data reaching object deserializers, template sources, dynamic evaluation, or server-side rendering engines.
3. **SSRF and outbound fetches:** user-influenced URLs or renderer fetch behavior that can reach internal network/filesystem targets.
4. **Secrets and token lifecycle:** hardcoded credentials, weak token generation, missing expiry/rotation/revocation, or sensitive logging.
5. **State and business logic abuse:** workflow bypasses, race conditions, replay paths, and order-of-operations flaws with practical attacker impact.

### Deep-Dive Heuristics for Server-Side Rendering Pipelines

When code transforms attacker-influenced markup/templates/documents (HTML-to-PDF, XSLT, markdown, server template compilation), treat the renderer as a high-risk execution boundary and check:

1. **Template/source origin:** can untrusted input become template or document source, not just data variables?
2. **Renderer capabilities:** does the engine allow file reads, outbound fetches, script execution, includes/imports, or extension functions?
3. **Privilege context:** what can the rendering process access (filesystem paths, metadata services, internal network)?
4. **Security flags/hardening:** are dangerous features explicitly disabled, or are defaults being trusted?
5. **Output trust boundary:** can generated artifacts reflect active content that executes downstream (HTML/script in browser or viewer)?
6. **Uncertainty handling:** if exact impact depends on runtime flags/version, report the finding with clear assumptions and confidence rather than discarding it.

## Pass 3 — Validation (Prune False Positives)

For each candidate finding:

1. Is this reachable by an attacker, or always validated upstream / dead code?
2. Is there sanitization or escaping I missed?
3. Would a real attacker care, or is impact negligible?
4. For each state-changing flow, evaluate practical attacker paths to impact and prioritize validation by exploitability, impact, and evidence strength.
5. For access control findings, classify the issue precisely as one (or more) of: missing authentication, missing function-level authorization, missing object-level authorization, or tenant boundary failure.
6. If multiple valid vulnerabilities exist in the same feature, rank them by exploitability, impact, and confidence; clearly label relative remediation priority.
7. Before finalizing, ensure findings are ordered from highest to lowest practical risk for defenders.
8. Ensure every reported finding includes exploitability boundaries:
   - **Exploit preconditions:** what must be true for exploitation
   - **Uncertainty boundary:** what unknown runtime/config factors could change impact
9. Run a **counterfactual check** for high-priority findings: name one concrete code/config change that would make each finding no longer valid.
10. Apply a **concreteness check**: include at least one plausible attacker-controlled input shape (path, parameter, header, body field, or sequence) that reaches the sink.
11. If a candidate finding is broad but no direct sink is shown, lower confidence/priority until the source->sink path is explicit.

Before finalizing, run this short sanity checklist:

- If multi-layer routing/proxy behavior is in scope, could path normalization differences change route or policy outcomes?
- If request-derived redirect/header construction exists, could CRLF or header injection occur?
- Could permissive object/body binding allow attacker control of security-sensitive fields?
- If multiple findings are valid, are they ordered by exploitability and impact with clear priority notes?
- For edge/proxy/cache/CORS findings, did I include a concrete request shape and exact cross-layer mismatch?
- For top-priority findings, did I choose issues with the most direct source->sink exploit paths and highest practical impact?
- Did I include counterfactual invalidation statements for top-priority findings?

Valid → assign severity and confidence, format per `05-output-format.md`.
Ruled out → discard silently (do not report eliminated findings).

More than one **valid** finding on the same feature is allowed — use confidence and severity per item. **False positive** means the issue fails Pass 3, not “secondary to another finding.”

## Severity Guide

| Severity | Criteria |
|----------|----------|
| CRITICAL | Direct RCE, auth bypass, mass data exfiltration with no preconditions |
| HIGH     | SQLi, stored XSS, IDOR on sensitive data, hardcoded secrets, insecure deserialization |
| MEDIUM   | Reflected XSS, CSRF, open redirect, weak crypto in non-auth context |
| LOW      | Info disclosure, missing security headers, verbose errors |
| INFO     | Best-practice violations with negligible exploitability |
