# Testing

Refrakt generates tests alongside every resource and auth system.
Tests run with Gleam's built-in test runner.

## Running tests

```bash
gleam test
```

Gleam automatically discovers and runs all public functions ending
in `_test` in the `test/` directory.

## Generated tests

### Router tests

`refrakt new` generates `test/<app>/router_test.gleam`, which sends
requests through `router.handle_request` with `wisp/simulate`. It checks
that the home page renders, that a POST from another site is rejected
with 403 by the CSRF check, and that a same-origin POST gets past it:

```gleam
pub fn cross_site_post_is_rejected_test() {
  let response =
    simulate.request(http.Post, "/")
    |> simulate.header("origin", "https://evil.example")
    |> router.handle_request(test_context())

  response.status
  |> should.equal(403)
}
```

`simulate.browser_request` sends an `Origin` header matching the host,
like a browser submitting one of your forms; use it for POST, PUT and
DELETE requests that should succeed.

### Resource tests

`refrakt gen resource posts title:string body:text published:bool`
generates tests in `test/<app>/web/post_handler_test.gleam`:

```gleam
pub fn empty_form_has_no_id_test() {
  let form = post_form.empty()
  form.id |> should.be_none
}

pub fn decode_valid_form_test() {
  let data = wisp.FormData(
    values: [
      #("title", "test value"),
      #("body", "test value"),
      #("published", "on"),
    ],
    files: [],
  )
  post_form.decode(data) |> should.be_ok
}

pub fn decode_missing_title_returns_error_test() {
  let data = wisp.FormData(values: [], files: [])
  post_form.decode(data) |> should.be_error
}
```

Through the router, they also check that a cross-site `POST /posts` is
rejected with 403 and that a same-origin `POST /posts` with an empty
form re-renders the form with 422. Neither request reaches the
database.

One more test runs against [the test database](#tests-against-the-database):
`create_show_update_delete_test` creates a post through the router,
follows the redirect to its page, updates it, deletes it and checks
that it is gone:

```gleam
pub fn create_show_update_delete_test() {
  use ctx <- test_db.with_context()

  let created =
    simulate.browser_request(http.Post, "/posts")
    |> simulate.form_body(form_values())
    |> router.handle_request(ctx)
  created.status |> should.equal(303)
  let assert Ok(path) = response.get_header(created, "location")

  let shown = get(path, ctx)
  shown.status |> should.equal(200)
  simulate.read_body(shown)
  |> string.contains("test value")
  |> should.be_true

  // ... PUT path, then DELETE path, then GET path is a 404
}
```

`--api` resources get the same test with JSON requests.

### Auth tests

`refrakt gen auth` generates password hashing tests:

```gleam
pub fn hash_password_round_trip_test() {
  let assert Ok(hash) = auth.hash_password("secret123")
  auth.verify_password("secret123", hash) |> should.be_true
}

pub fn wrong_password_test() {
  let assert Ok(hash) = auth.hash_password("secret123")
  auth.verify_password("wrong", hash) |> should.be_false
}

pub fn hashes_are_salted_test() {
  let assert Ok(first) = auth.hash_password("secret123")
  let assert Ok(second) = auth.hash_password("secret123")
  first |> should.not_equal(second)
}
```

They also check that hashes are Argon2id, that a malformed hash never
verifies, that `auth.dummy_hash` is a real Argon2id hash (so logins for
unknown emails take as long as wrong passwords) and that
`auth.authenticate` accepts only the right password.

Against the test database, `register_then_log_in_test` registers
through `POST /register`, logs in through `POST /login` (both must set
the session cookie) and checks that a wrong password and an unknown
email get 422; `register_with_a_taken_email_test` registers the same
email twice.

`test/<app>/web/session_test.gleam` checks that a session cookie
round-trips to the user id, that signing out and forged tokens give no
user, and that the cookie is `HttpOnly`, `SameSite=Lax`, has a
`Max-Age`, and is `Secure` in production.

## Test helpers

The `refrakt/testing` module provides request builders for testing
handlers without a running server:

```gleam
import refrakt/testing

// Build requests
let req = testing.get("/posts")
let req = testing.post("/posts")
let req = testing.put("/posts/1")
let req = testing.delete("/posts/1")

// With headers
let req = testing.get("/posts")
  |> testing.with_header("accept", "application/json")

// With body
let req = testing.post("/posts")
  |> testing.with_body("title=hello")

// As sent by a page of this app, or by another site (for refrakt/csrf)
let req = testing.post("/posts") |> testing.same_origin
let req = testing.post("/posts") |> testing.cross_site(from: "https://evil.example")

// Check responses
testing.assert_status(response, 200)
testing.assert_header(response, "content-type", "text/html")
```

`testing.json_request` builds a `wisp.Request` with a JSON body and
`content-type: application/json`, ready to pass to a handler. The body
is a string, so you can send malformed JSON too:

```gleam
import gleam/http
import gleam/json
import refrakt/testing
import wisp/simulate

pub fn create_with_blank_title_returns_422_test() {
  let body = json.object([#("title", json.string(""))]) |> json.to_string

  let response =
    testing.json_request(http.Post, "/api/posts", body)
    |> post_handler.create(test_context())

  response.status |> should.equal(422)
  simulate.read_body(response)
  |> string.contains("Title is required")
  |> should.be_true
}
```

`refrakt gen resource ... --api` generates tests like this for each
resource. They stop before the database (bad bodies, ids that are not
numbers), so they pass without one.

## Tests against the database

`gen resource` and `gen auth` write `test/<app>/support/test_db.gleam`
the first time (later runs leave your copy alone). Its `with_context`
runs a test with a `Context` on a real database with the app's
migrations applied, and leaves nothing behind, also when the test
fails:

```gleam
import my_app/router
import my_app/support/test_db

pub fn create_post_test() {
  use ctx <- test_db.with_context()

  let response =
    simulate.browser_request(http.Post, "/posts")
    |> simulate.form_body([#("title", "Hello"), #("body", "World")])
    |> router.handle_request(ctx)

  response.status |> should.equal(303)
}
```

`simulate.browser_request` sends a same-origin `Origin` header, so
unsafe requests pass `refrakt/csrf`.

**SQLite.** Every test gets its own in-memory database
(`file:<app>_test_<n>?mode=memory&cache=shared`). The repos open a
connection per query from `ctx.db_path`; the shared cache makes those
connections see one database while `with_context` keeps a connection
open, and the database disappears when the test ends. Nothing to set up.

**Postgres.** Every test runs in one transaction on the test database
that is always rolled back; the migrations run inside it, so the
database itself stays empty. The test database is `DATABASE_URL`, or
`postgres://postgres@localhost:5432/<app>_test` when it is unset.
Create it once:

```bash
createdb -h localhost -U postgres my_app_test
```

In CI, start a Postgres service and create the database before
`gleam test`, for example
`psql postgres://postgres@localhost:5432/postgres -c "CREATE DATABASE my_app_test"`.
Without a reachable database the tests that use `with_context` fail
with a message naming the URL. Two things follow from the transaction:
code under test must not call `pog.transaction` itself (its `COMMIT`
would end the test's transaction), and after a failing query, such as a
unique constraint violation, Postgres refuses further queries in that
transaction, so make it the last one in a test.

`with_context` is built on `testing.with_database(open:, close:, run:)`
from `refrakt/testing`, which opens a database, runs the test and always
closes it (also after a failed assertion), and on
`migrate.run_quietly`, which applies migrations without printing. The
library knows no database driver; the app's own `pog` or `sqlight`
dependency does the work in `test_db.gleam`, which you can change like
any generated file.

## Writing handler tests

To test a handler directly, you need a `Context` and a request. Tests
that never reach a repo can use a context with an unused database, as
the generated `test_context()` does; the others use
`test_db.with_context`.

### Unit testing forms (no database needed)

```gleam
import gleeunit/should
import my_app/web/forms/post_form
import wisp

pub fn valid_post_decodes_test() {
  let data = wisp.FormData(
    values: [#("title", "Hello"), #("body", "World")],
    files: [],
  )

  let assert Ok(params) = post_form.decode(data)
  params.title |> should.equal("Hello")
  params.body |> should.equal("World")
}

pub fn short_title_fails_validation_test() {
  let data = wisp.FormData(
    values: [#("title", "Hi"), #("body", "World")],
    files: [],
  )

  post_form.decode(data) |> should.be_error
}
```

### Testing domain logic (no database needed)

```gleam
import my_app/domain/auth

pub fn password_roundtrip_test() {
  let hash = auth.hash_password("my-secret")
  auth.verify_password("my-secret", hash) |> should.be_true
  auth.verify_password("wrong", hash) |> should.be_false
}
```

### Testing validation helpers

```gleam
import refrakt/validate

pub fn required_rejects_empty_test() {
  []
  |> validate.required("", "email", "Required")
  |> should.equal([#("email", "Required")])
}

pub fn min_length_accepts_long_string_test() {
  []
  |> validate.min_length("hello world", "name", 3, "Too short")
  |> should.equal([])
}
```

## Test structure

Tests mirror the source structure:

```
test/
  my_app_test.gleam                   ← entry point (runs gleeunit)
  my_app/support/
    test_db.gleam                     ← real database for tests
  my_app/web/
    post_handler_test.gleam           ← resource tests
    auth_handler_test.gleam           ← auth tests
    home_handler_test.gleam           ← page tests
```

## Tips

- Test forms and domain logic first — they don't need a database
- Generated tests cover the happy path, missing required fields and,
  against the test database, create/show/update/delete
- Add edge case tests for your specific validation rules
- Use `wisp.FormData` to build test form submissions
- Keep domain modules free of framework imports so they're easy to test
