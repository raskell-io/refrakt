import gleam/dynamic/decode
import gleam/http
import gleam/http/request
import gleeunit/should
import refrakt/testing
import wisp

pub fn json_request_sets_method_path_and_content_type_test() {
  let req = testing.json_request(http.Put, "/api/posts/1", "{}")

  req.method |> should.equal(http.Put)
  req.path |> should.equal("/api/posts/1")
  request.get_header(req, "content-type")
  |> should.equal(Ok("application/json"))
}

pub fn json_request_body_reaches_require_json_test() {
  let response = {
    let req = testing.json_request(http.Post, "/", "{\"title\": \"Hello\"}")
    use data <- wisp.require_json(req)
    case decode.run(data, decode.at(["title"], decode.string)) {
      Ok("Hello") -> wisp.ok()
      _ -> wisp.bad_request("unexpected body")
    }
  }

  response.status |> should.equal(200)
}

pub fn json_request_with_malformed_body_is_rejected_test() {
  let response = {
    let req = testing.json_request(http.Post, "/", "{not json")
    use _ <- wisp.require_json(req)
    wisp.ok()
  }

  response.status |> should.equal(400)
}
