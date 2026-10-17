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

## Writing handler tests

To test a handler directly, you need a `Context` and a request.
For database-dependent handlers, you'll need a test database.

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
  my_app/web/
    post_handler_test.gleam           ← resource tests
    auth_handler_test.gleam           ← auth tests
    home_handler_test.gleam           ← page tests
```

## Tips

- Test forms and domain logic first — they don't need a database
- Generated tests cover the happy path and missing required fields
- Add edge case tests for your specific validation rules
- Use `wisp.FormData` to build test form submissions
- Keep domain modules free of framework imports so they're easy to test
