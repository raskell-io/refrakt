import exception
import gleam/dynamic/decode
import gleam/erlang/process
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

pub fn with_database_passes_the_database_and_closes_it_test() {
  let closed = process.new_subject()

  testing.with_database(
    open: fn() { Ok("db") },
    close: fn(db) { process.send(closed, db) },
    run: fn(db) { db <> " used" },
  )
  |> should.equal("db used")
  process.receive(closed, 0) |> should.equal(Ok("db"))
}

pub fn with_database_closes_when_the_body_panics_test() {
  let closed = process.new_subject()

  exception.rescue(fn() {
    testing.with_database(
      open: fn() { Ok("db") },
      close: fn(db) { process.send(closed, db) },
      run: fn(_) { panic as "assertion failed" },
    )
  })
  |> should.be_error
  process.receive(closed, 0) |> should.equal(Ok("db"))
}

pub fn with_database_fails_the_test_when_open_fails_test() {
  let closed = process.new_subject()

  exception.rescue(fn() {
    testing.with_database(
      open: fn() { Error("connection refused") },
      close: fn(db) { process.send(closed, db) },
      run: fn(_) { Nil },
    )
  })
  |> should.be_error
  process.receive(closed, 0) |> should.equal(Error(Nil))
}
