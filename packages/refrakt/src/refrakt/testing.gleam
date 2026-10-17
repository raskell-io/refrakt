/// Test helpers for Refrakt applications.
///
/// Build test requests without a running HTTP server.
///
/// ## Example
///
/// ```gleam
/// import refrakt/testing
///
/// pub fn index_returns_200_test() {
///   let req = testing.get("/posts")
///   let resp = post_handler.index(req, test_ctx())
///   resp.status |> should.equal(200)
/// }
/// ```
///
import gleam/http
import gleam/http/request
import gleam/http/response.{type Response}

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

/// Set the body of a test request.
pub fn with_body(
  req: request.Request(String),
  body: String,
) -> request.Request(String) {
  request.set_body(req, body)
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
