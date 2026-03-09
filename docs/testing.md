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

### Auth tests

`refrakt gen auth` generates password hashing tests:

```gleam
pub fn hash_password_test() {
  let hash = auth.hash_password("secret123")
  auth.verify_password("secret123", hash) |> should.be_true
}

pub fn wrong_password_test() {
  let hash = auth.hash_password("secret123")
  auth.verify_password("wrong", hash) |> should.be_false
}
```

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

// Check responses
testing.assert_status(response, 200)
testing.assert_header(response, "content-type", "text/html")
```

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
