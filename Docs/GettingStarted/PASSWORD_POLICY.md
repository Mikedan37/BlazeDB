# Database password policy

BlazeDB encrypts data at rest. The encryption key is derived from the password you pass to `BlazeDB.open(...)`, `BlazeDBClient.open(...)`, or `BlazeDBClient(name:fileURL:password:)` using PBKDF2 and a per-database salt.

**There is no separate “create database password” step.** The same rules apply on first open (new file) and every later open.

---

## What is enforced

Implementation: `PasswordStrengthValidator.validate(_:requirements:)` with **`PasswordStrengthValidator.Requirements.recommended`** (see `BlazeDB/Security/PasswordStrengthValidator.swift`).

| Rule | Value |
|------|--------|
| Minimum length | **12** characters |
| Uppercase letter | **Required** |
| Lowercase letter | **Required** |
| Digit | **Required** |
| Symbol / punctuation | **Optional** (recommended for user-facing apps) |
| Minimum strength score | **`PasswordStrength.good`** (internal scoring; common weak patterns are penalized) |

If validation fails, key derivation does not run and initialization throws **`BlazeDBError.passwordTooWeak`**.  
`LocalizedError.errorDescription` includes the dynamic recommendations string from `PasswordStrengthValidator.analyze(_:)`.

---

## What this is not

- **Not** “at least 8 characters only.” Older docs or comments may say that; the runtime policy is the table above.
- **Not** silent: a weak password does **not** create an empty client or fall back to an unencrypted database.

---

## Avoiding “silent” failures in your own code

| Anti-pattern | Problem |
|--------------|---------|
| `try? BlazeDB.open(...)` | Failure becomes `nil` with no error to log |
| Ignoring `throw` in a closure | Same |
| Assuming `openForTesting()` default password is weak-but-OK | Defaults must still satisfy **`Requirements.recommended`** |

**Do this instead:** use `try` / `catch`, switch on `BlazeDBError.passwordTooWeak`, or log `error.localizedDescription`.

---

## Examples

**Valid (meets recommended):**

- `DemoPass123!`
- `My-Secure-Password-2026!`
- `TestPassword-123!`

**Invalid:**

- `short` — too short, missing classes
- `all-lowercase-words-here` — no uppercase, no digits
- `ALLUPPERCASE123` — no lowercase
- `NoDigitsHere!!` — no digits

---

## Testing helpers

`BlazeDBClient.openForTesting(...)` uses the same validation as production. The default password is chosen to satisfy **`Requirements.recommended`** so `try BlazeDBClient.openForTesting()` works without arguments.

For custom passwords in tests, reuse patterns like `TestPassword-123!`.

---

## Stricter mode (advanced)

`PasswordStrengthValidator.Requirements.strict` (16+ chars, symbols required, higher strength floor) exists for high-security scenarios. Production open paths today use **`.recommended`** unless you extend the API.
