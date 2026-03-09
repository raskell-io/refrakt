# Authentication

`refrakt gen auth` generates a complete authentication system —
registration, login, logout, password hashing, and session management.
It's real code in your project, not a library. You own it and can
modify everything.

## Generate auth

```bash
refrakt gen auth
```

This creates 9 files:

| File | Purpose |
|------|---------|
| `domain/user.gleam` | User type |
| `domain/auth.gleam` | Password hashing and verification |
| `data/user_repo.gleam` | User database queries |
| `data/migrations/NNN_create_users.sql` | Users table |
| `web/auth_handler.gleam` | Login, register, logout handlers |
| `web/auth_views.gleam` | Login and register forms |
| `web/forms/auth_form.gleam` | Credential validation |
| `web/middleware/auth.gleam` | Session middleware |
| `test/.../auth_handler_test.gleam` | Password hashing tests |

And adds 5 routes to the router:

```
GET     /login              Login page
POST    /login              Submit login
GET     /register           Register page
POST    /register           Submit registration
POST    /logout             Log out
```

## Run the migration

PostgreSQL:
```bash
psql my_app_dev < src/my_app/data/migrations/NNN_create_users.sql
```

SQLite:
```bash
sqlite3 my_app.db < src/my_app/data/migrations/NNN_create_users.sql
```

## How sessions work

Sessions use signed cookies. When a user logs in:

1. The handler verifies the password
2. Sets a `_user_id` cookie (signed, 7-day expiry)
3. Redirects to `/`

When checking auth:

1. The middleware reads the `_user_id` cookie
2. Verifies the signature
3. Looks up the user in the database
4. Passes the user to the handler or redirects to `/login`

## Protecting routes

Use the `require_auth` middleware in any handler:

```gleam
import my_app/web/middleware/auth

pub fn create(req: Request, ctx: Context) -> Response {
  use user <- auth.require_auth(req, ctx)
  // `user` is the authenticated User
  // ... create the post ...
}
```

If there's no valid session, `require_auth` redirects to `/login`.

### Get the current user (optional)

```gleam
import my_app/web/middleware/auth

pub fn index(req: Request, ctx: Context) -> Response {
  let current_user = auth.get_current_user(req, ctx)
  // Result(User, Nil) — Ok if logged in, Error if not
}
```

## Password hashing

The generated `auth.gleam` uses `gleam_crypto` SHA-256 hashing. This
is functional for development but **not production-grade**.

For production, replace with a proper password hashing library:

```bash
gleam add beecrypt
```

Then update `domain/auth.gleam`:

```gleam
import beecrypt

pub fn hash_password(password: String) -> String {
  beecrypt.hash(password)
}

pub fn verify_password(password: String, hash: String) -> Bool {
  beecrypt.verify(password, hash)
}
```

## Form validation

The auth form validates:
- Email is not empty
- Password is not empty
- Password is at least 8 characters (registration only)
- Password confirmation matches (registration only)

Modify `web/forms/auth_form.gleam` to add stricter validation:

```gleam
// Add to decode_register:
|> validate_email_format(email)

fn validate_email_format(errors, email) {
  case string.contains(email, "@") {
    True -> errors
    False -> [#("email", "Must be a valid email"), ..errors]
  }
}
```

## Customization

Since auth is generated code (not a library), you can:

- Add fields to the User type (name, role, avatar)
- Change the session duration
- Add email verification
- Add password reset
- Add OAuth (Google, GitHub)
- Change the login redirect target
- Add rate limiting to login attempts
- Use a different password hashing algorithm

Edit the files directly — they're yours.
