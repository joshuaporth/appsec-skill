# Language-Specific Pitfalls

Apply the relevant section(s) for the language(s) in the codebase.

## Python
**Flag:**
- `eval()` / `exec()` on user input — CRITICAL
- `subprocess.run(shell=True)` with user data — command injection
- `pickle.loads()` on untrusted data — insecure deserialization
- `yaml.load()` without `Loader=yaml.SafeLoader` — RCE
- `os.system()` with user data — command injection
- `hashlib.md5()` / `hashlib.sha1()` for passwords — too fast
- `random.random()` / `random.randint()` for tokens — not CSPRNG
- `open(user_path)` without canonicalization — path traversal
- `f"SELECT ... {user_id}"` — SQLi
- `render_template_string(user_input)` — SSTI
- `requests.get(url, verify=False)` — TLS disabled

**Safe alternatives:** `secrets` module for tokens; `subprocess.run([...], shell=False)`; `yaml.safe_load()`; `bcrypt` / `argon2-cffi` for passwords; parameterized DB queries

## JavaScript / Node.js
**Flag:**
- `eval(userInput)` — CRITICAL
- `child_process.exec(cmd)` with user data — use `execFile` with args array
- `innerHTML = userInput` — XSS
- `document.write(userInput)` — XSS
- `__proto__` / `constructor.prototype` mutation — prototype pollution
- JWT accepting `alg: none` — CRITICAL auth bypass
- `Math.random()` for tokens — use `crypto.randomBytes()`
- `require(userInput)` — path traversal / RCE
- `res.redirect(req.query.next)` without validation — open redirect
- **`package.json` / lockfile:** flag names that **typo or mimic** well-known packages or **core module names** — supply-chain and resolution surprises

**Framework:** Express — check `helmet` middleware and CSRF protection; Next.js — check `/api` routes for missing auth and `dangerouslySetInnerHTML`

## PHP
**Flag:**
- `eval($userInput)` — RCE
- `system()`, `exec()`, `shell_exec()`, `passthru()` with user data — command injection
- `unserialize($userInput)` — object injection
- `include($userInput)` / `require($userInput)` — file inclusion
- Raw string concatenation in `mysql_query()` / `mysqli` — SQLi
- `md5($password)` / `sha1($password)` for passwords
- `rand()` / `mt_rand()` for tokens — use `random_bytes()`
- `$_GET`/`$_POST` echoed without `htmlspecialchars()` — XSS
- `extract($_POST)` — variable injection

**Safe alternatives:** `password_hash($pass, PASSWORD_ARGON2ID)`; `random_bytes()` + `bin2hex()`; PDO prepared statements; `htmlspecialchars($out, ENT_QUOTES, 'UTF-8')`

## Java
**Flag:**
- `Runtime.getRuntime().exec()` with user data — command injection
- `ObjectInputStream.readObject()` on untrusted data — CRITICAL deserialization
- String concatenation in JDBC `Statement` — SQLi; use `PreparedStatement`
- `XMLDecoder` on untrusted data — insecure deserialization
- `DocumentBuilderFactory` without disabling external entities — XXE
- `MessageDigest.getInstance("MD5")` for passwords
- `new Random()` for tokens — use `SecureRandom`

## Ruby
**Flag:**
- `send(user_input)` / `public_send(user_input)` — arbitrary method dispatch
- `constantize(user_input)` — arbitrary class instantiation
- `Marshal.load(user_input)` — CRITICAL deserialization
- `eval(user_input)` — RCE
- Backtick or `system()` with user data — command injection
- `where("name = '#{input}'")` — SQLi; use `where(name: input)`
- Mass assignment without `permit()` (strong params)
- `render inline: user_input` — SSTI

## Go
**Flag:**
- `text/template` instead of `html/template` for HTML output — XSS
- String concatenation in `database/sql` queries — SQLi; use `?` placeholders
- `exec.Command("sh", "-c", userInput)` — command injection
- `math/rand` for security values — use `crypto/rand`
- `InsecureSkipVerify: true` in TLS config

## C / C++
**Flag:**
- `gets()`, `strcpy()`, `strcat()`, `sprintf()` — buffer overflow
- `scanf("%s", buf)` without width limit — buffer overflow
- `printf(user_input)` — format string vulnerability; use `printf("%s", user_input)`
- `system(cmd)` with user data — command injection
- Integer overflow leading to bad allocation sizes
- Use-after-free patterns
- `rand()` for security — use `/dev/urandom` or `getrandom()`

## Shell / Bash
**Flag:**
- Unquoted variable use in tests or command args (`[ $x = ... ]`, `cmd $input`) — word splitting/globbing/injection side effects
- Pattern matching with untrusted values where exact comparison was intended (`[[ $x == $user_input ]]`)
- Use of `[ ... ]` where `[[ ... ]]` semantics are safer/clearer for strings
- `eval`, backticks, or `bash -c` with untrusted input — command injection
- Authentication/authorization logic implemented with filename/glob-sensitive comparisons
- Unsafe temporary files without `mktemp` and strict permissions

**Quick checks:**
- For auth checks, verify whether wildcard/glob expansion can change pass/fail behavior.
- Confirm all security-sensitive variables are quoted unless arithmetic expansion is intentional.
- Prefer explicit string comparison and fixed allowlists over pattern-based matching.
