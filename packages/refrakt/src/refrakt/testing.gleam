//// Test helpers for Refrakt applications.
////
//// Build test requests without a running HTTP server.
////
//// ## Example
////
//// ```gleam
//// import refrakt/testing
////
//// pub fn index_returns_200_test() {
////   let req = testing.get("/posts")
////   let resp = post_handler.index(req, test_ctx())
////   resp.status |> should.equal(200)
//// }
//// ```
////
//// ## Tests against a real database
////
//// `with_database` runs a test body against a database that is set up
//// for it and torn down after it, also when an assertion fails. It knows
//// nothing about any database driver: generated apps call it from
//// `test/<app>/support/test_db.gleam`, which opens the database with the
//// app's own `pog` or `sqlight` dependency, applies the migrations and
//// keeps every test's writes from reaching the next test.
////

import exception
import gleam/http
import gleam/http/request
import gleam/http/response.{type Response}
import wisp
import wisp/simulate

/// Create a GET request for testing.
pub fn get(path: String) -> request.Request(String) {
  request.new()
  |> request.set_method(http.Get)
  |> request.set_path(path)
}

/// Create a POST request for testing.
pub fn post(path: String) -> request.Request(String) {
  request.new()
  |> request.set_method(http.Post)
  |> request.set_path(path)
}

/// Create a PUT request for testing.
pub fn put(path: String) -> request.Request(String) {
  request.new()
  |> request.set_method(http.Put)
  |> request.set_path(path)
}

/// Create a DELETE request for testing.
pub fn delete(path: String) -> request.Request(String) {
  request.new()
  |> request.set_method(http.Delete)
  |> request.set_path(path)
}

/// Create a request with a specific method and path.
pub fn request(method: http.Method, path: String) -> request.Request(String) {
  request.new()
  |> request.set_method(method)
  |> request.set_path(path)
}

/// Add a header to a test request.
pub fn with_header(
  req: request.Request(String),
  name: String,
  value: String,
) -> request.Request(String) {
  request.set_header(req, name, value)
}

/// Mark a test request as sent by a page of this app, the way a browser
/// submits a form: sets the `host` header (from the request's host, if
/// it is missing) and a matching `origin` header. Unsafe requests need
/// these to get past `refrakt/csrf.protect` with their cookies.
pub fn same_origin(req: request.Request(body)) -> request.Request(body) {
  let host = host_header(req)
  req
  |> request.set_header("host", host)
  |> request.set_header(
    "origin",
    http.scheme_to_string(req.scheme) <> "://" <> host,
  )
}

/// Mark a test request as sent by a page on another site, such as
/// `"https://evil.example"`. `refrakt/csrf.protect` rejects it with 403
/// unless the method is safe.
pub fn cross_site(
  req: request.Request(body),
  from origin: String,
) -> request.Request(body) {
  req
  |> request.set_header("host", host_header(req))
  |> request.set_header("origin", origin)
}

fn host_header(req: request.Request(body)) -> String {
  case request.get_header(req, "host") {
    Ok(host) -> host
    Error(_) -> req.host
  }
}

/// Set the body of a test request.
pub fn with_body(
  req: request.Request(String),
  body: String,
) -> request.Request(String) {
  request.set_body(req, body)
}

/// Create a request with a JSON body, ready to pass straight to a handler.
///
/// Unlike the builders above, this returns a `wisp.Request`, the type
/// handlers take. The body is a string so tests can send malformed JSON
/// too; build valid bodies with `gleam/json`. The `content-type` header
/// is `application/json`, as `wisp.require_json` expects.
///
/// ```gleam
/// let body = json.object([#("title", json.string("Hello"))])
///
/// testing.json_request(http.Post, "/api/posts", json.to_string(body))
/// |> post_handler.create(ctx)
/// ```
pub fn json_request(
  method: http.Method,
  path: String,
  body: String,
) -> wisp.Request {
  simulate.request(method, path)
  |> simulate.string_body(body)
  |> simulate.header("content-type", "application/json")
}

/// Check that a response has a specific status code.
pub fn assert_status(resp: Response(String), expected: Int) -> Bool {
  resp.status == expected
}

/// Check that a response has a specific header value.
pub fn assert_header(
  resp: Response(String),
  name: String,
  expected: String,
) -> Bool {
  case response.get_header(resp, name) {
    Ok(value) -> value == expected
    Error(_) -> False
  }
}

/// Run `body` with a database opened by `open`, then close it with
/// `close`. `close` always runs: also when `body` panics, as a failing
/// `should` assertion does, so one failing test cannot leave its data
/// behind for the next.
///
/// When `open` fails, the test fails with a panic that shows its error,
/// so explain there how to make the database reachable.
///
/// ```gleam
/// pub fn with_db(body: fn(sqlight.Connection) -> a) -> a {
///   testing.with_database(
///     open: fn() {
///       sqlight.open("file:test?mode=memory&cache=shared")
///       |> result.map_error(fn(error) { error.message })
///     },
///     close: fn(conn) {
///       let _ = sqlight.close(conn)
///       Nil
///     },
///     run: body,
///   )
/// }
/// ```
pub fn with_database(
  open open: fn() -> Result(db, String),
  close close: fn(db) -> Nil,
  run body: fn(db) -> a,
) -> a {
  case open() {
    Error(message) ->
      panic as { "Could not open the test database: " <> message }
    Ok(db) -> {
      use <- exception.defer(fn() { close(db) })
      body(db)
    }
  }
}
