import gleam/http
import gleam/http/request
import gleam/list
import gleeunit/should
import refrakt/csrf
import refrakt/testing
import wisp

fn post() -> request.Request(String) {
  testing.post("/posts")
  |> testing.with_header("host", "app.example")
}

fn assert_rejected(verdict: csrf.Verdict) -> Nil {
  case verdict {
    csrf.Rejected(_) -> Nil
    _ -> panic as "expected the request to be rejected"
  }
}

fn handler(req: request.Request(String)) -> wisp.Response {
  case request.get_header(req, "cookie") {
    Ok(_) -> wisp.response(200)
    Error(_) -> wisp.response(204)
  }
}

pub fn get_is_allowed_test() {
  testing.get("/posts")
  |> testing.cross_site(from: "https://evil.example")
  |> csrf.check
  |> should.equal(csrf.Allowed)
}

pub fn same_origin_post_is_allowed_test() {
  testing.post("/posts")
  |> testing.same_origin
  |> csrf.check
  |> should.equal(csrf.Allowed)
}

pub fn origin_with_port_matches_host_test() {
  testing.post("/posts")
  |> testing.with_header("host", "localhost:4000")
  |> testing.with_header("origin", "http://localhost:4000")
  |> csrf.check
  |> should.equal(csrf.Allowed)
}

pub fn origin_comparison_ignores_case_test() {
  post()
  |> testing.with_header("origin", "https://APP.example")
  |> csrf.check
  |> should.equal(csrf.Allowed)
}

pub fn cross_site_post_is_rejected_test() {
  post()
  |> testing.cross_site(from: "https://evil.example")
  |> csrf.check
  |> assert_rejected
}

pub fn other_port_is_rejected_test() {
  testing.post("/posts")
  |> testing.with_header("host", "localhost:4000")
  |> testing.with_header("origin", "http://localhost:5000")
  |> csrf.check
  |> assert_rejected
}

pub fn subdomain_is_rejected_test() {
  post()
  |> testing.with_header("origin", "https://evil.app.example")
  |> csrf.check
  |> assert_rejected
}

pub fn null_origin_is_rejected_test() {
  post()
  |> testing.with_header("origin", "null")
  |> csrf.check
  |> assert_rejected
}

pub fn origin_without_host_header_is_rejected_test() {
  testing.post("/posts")
  |> testing.with_header("origin", "https://app.example")
  |> csrf.check
  |> assert_rejected
}

pub fn put_delete_and_patch_are_checked_test() {
  [http.Put, http.Delete, http.Patch]
  |> list.each(fn(method) {
    testing.request(method, "/posts/1")
    |> testing.with_header("host", "app.example")
    |> testing.cross_site(from: "https://evil.example")
    |> csrf.check
    |> assert_rejected
  })
}

pub fn sec_fetch_site_same_origin_wins_over_origin_test() {
  // A proxy may rewrite Host; Sec-Fetch-Site does not depend on it.
  post()
  |> testing.with_header("origin", "https://public.example")
  |> testing.with_header("sec-fetch-site", "same-origin")
  |> csrf.check
  |> should.equal(csrf.Allowed)
}

pub fn sec_fetch_site_cross_site_is_rejected_test() {
  post()
  |> testing.with_header("sec-fetch-site", "cross-site")
  |> csrf.check
  |> assert_rejected
}

pub fn sec_fetch_site_same_site_is_rejected_test() {
  post()
  |> testing.with_header("sec-fetch-site", "same-site")
  |> csrf.check
  |> assert_rejected
}

pub fn matching_referer_is_allowed_test() {
  post()
  |> testing.with_header("referer", "https://app.example/posts/new")
  |> csrf.check
  |> should.equal(csrf.Allowed)
}

pub fn foreign_referer_is_rejected_test() {
  post()
  |> testing.with_header("referer", "https://evil.example/attack")
  |> csrf.check
  |> assert_rejected
}

pub fn no_provenance_headers_drops_cookies_test() {
  post()
  |> csrf.check
  |> should.equal(csrf.AllowedWithoutCookies)
}

pub fn protect_rejects_cross_site_with_403_test() {
  let resp =
    post()
    |> testing.with_header("cookie", "_session=abc")
    |> testing.cross_site(from: "https://evil.example")
    |> csrf.protect(handler)

  resp.status
  |> should.equal(403)
}

pub fn protect_keeps_cookies_for_same_origin_test() {
  let resp =
    post()
    |> testing.with_header("cookie", "_session=abc")
    |> testing.same_origin
    |> csrf.protect(handler)

  resp.status
  |> should.equal(200)
}

pub fn protect_strips_cookies_without_provenance_test() {
  let resp =
    post()
    |> testing.with_header("cookie", "_session=abc")
    |> csrf.protect(handler)

  resp.status
  |> should.equal(204)
}
