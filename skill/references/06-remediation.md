# Remediation Guidance

Every remediation must be concrete, language-specific, and include corrected code.

## Principles

1. Show the fix — always include a corrected code snippet in the same language
2. Fix the root cause, not the symptom — don't add an input filter when a parameterized query is the real solution
3. Preserve developer intent — accomplish the same goal, just securely
4. Explain why — one sentence on the security property the fix provides

## Templates by Vulnerability Class

### SQL Injection
```python
# Before
cursor.execute(f"SELECT * FROM users WHERE username = '{username}'")
# After
cursor.execute("SELECT * FROM users WHERE username = %s", (username,))
# Why: the driver treats the parameter as data, never as SQL syntax
```

### Command Injection
```python
# Before
subprocess.run(f"convert {filename}", shell=True)
# After
subprocess.run(["convert", filename], shell=False)
# Why: list args bypass shell interpretation entirely
```

### XSS
```javascript
// Before
res.send("<p>Hello " + req.query.name + "</p>");
// After — use a templating engine with auto-escaping, or:
res.send("<p>Hello " + escapeHtml(req.query.name) + "</p>");
// Why: encoding converts <, >, " to entities, preventing markup interpretation
```

### Weak Password Hashing
```python
# Before
hashed = hashlib.md5(password.encode()).hexdigest()
# After
import bcrypt
hashed = bcrypt.hashpw(password.encode(), bcrypt.gensalt(rounds=12))
# Verify: bcrypt.checkpw(password.encode(), hashed)
# Why: bcrypt is intentionally slow (cost-factor controlled) and auto-salted
```

### Insecure Randomness
```python
# Before
token = str(random.randint(100000, 999999))
# After
import secrets
token = secrets.token_urlsafe(32)
# Why: secrets uses the OS CSPRNG; random is seeded with time and predictable
```

### Path Traversal
```python
# Before
open(os.path.join(BASE_DIR, user_filename))
# After
safe = os.path.realpath(os.path.join(BASE_DIR, user_filename))
if not safe.startswith(os.path.realpath(BASE_DIR)):
    raise ValueError("Path traversal detected")
open(safe)
# Why: realpath resolves all ../ sequences; prefix check keeps path within bounds
```

### Timing Attack on Secret Comparison
```python
# Before
if token == expected_token:
# After
import hmac
if hmac.compare_digest(token.encode(), expected_token.encode()):
# Why: compare_digest always takes the same time, preventing byte-by-byte brute force
```

### XXE
```python
# Before
tree = etree.parse(xml_file)
# After
parser = etree.XMLParser(resolve_entities=False, no_network=True)
tree = etree.parse(xml_file, parser)
# Why: disabling entity resolution prevents external resource fetching
```

### Insecure Deserialization
```python
# Before
data = pickle.loads(user_bytes)
# After
data = json.loads(user_bytes)
# Why: JSON cannot instantiate arbitrary objects or execute code
```
