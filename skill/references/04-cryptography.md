# Cryptography Checks

Apply every check here to any code handling secrets, passwords, tokens, or encrypted data.

## Password Storage
**Flag:**
- MD5, SHA1, SHA256, SHA512 used directly for passwords — fast hashing functions, not password hashing functions
- Passwords stored in plaintext, base64, or hex
- Passwords encrypted with a symmetric key (key leak = all passwords exposed)
- Static / hardcoded salt

**Safe:** bcrypt (cost ≥ 12), Argon2id (OWASP preferred), scrypt, PBKDF2 (≥ 600k iterations SHA-256)
Reference: https://crackstation.net/hashing-security.htm

## Random Number Generation
**Flag when used for session tokens, password reset links, CSRF tokens, keys, or IVs:**
- `Math.random()` (JS), `random.random()` (Python), `rand()` / `mt_rand()` (C/PHP), `java.lang.Math.random()`

**Safe:** Python `secrets`; Node `crypto.randomBytes()`; PHP `random_bytes()`; Java `SecureRandom`; Go `crypto/rand`; C `/dev/urandom` / `getrandom()`
Reference: http://sockpuppet.org/blog/2014/02/25/safely-generate-random-numbers/

## Symmetric Encryption
**Flag:**
- ECB mode — deterministic, leaks data patterns (HIGH)
- Hardcoded encryption keys or IVs in source code
- Reused IV/nonce with the same key (catastrophic for GCM)
- RC4, DES, 3DES — broken or deprecated (HIGH)
- AES key length < 128 bits

**Safe:** AES-256-GCM with randomly generated nonce per encryption; ChaCha20-Poly1305; keys derived via Argon2/scrypt/PBKDF2

## Asymmetric / Signatures
**Flag:**
- RSA keys < 2048 bits (HIGH)
- RSA PKCS#1 v1.5 padding for encryption — use OAEP
- JWT libraries accepting `alg: none` or not validating the `alg` header (CRITICAL)
- Signature verification using non-constant-time comparison

## Timing Attacks — CWE-208
**Flag any secret comparison using standard equality:**
- Python: `if token == expected:` → use `hmac.compare_digest()`
- PHP: `===` for tokens → use `hash_equals()`
- Java: `.equals()` for tokens → use `MessageDigest.isEqual()` on hash bytes

Standard equality short-circuits on first mismatch, leaking how many bytes matched.

## TLS / Transport
**Flag:**
- `verify=False`, `InsecureSkipVerify: true`, `NODE_TLS_REJECT_UNAUTHORIZED=0`
- TLS < 1.2 explicitly allowed
- Weak cipher suites explicitly configured

## Secrets Management
**Flag:**
- Keys, tokens, passwords hardcoded anywhere in source (including test files and comments)
- `.env` files that appear committed to the repository
- Credentials logged at any log level
