import gleam/erlang/process
import gleam/http
import gleam/http/request
import gleeunit/should
import refrakt/rate_limit
import wisp
import wisp/simulate

fn request_with(headers: List(#(String, String))) -> wisp.Request {
  let req = simulate.browser_request(http.Get, "/")
  request.Request(..req, headers:)
}

fn ok() -> wisp.Response {
  wisp.ok()
}

fn status(
  limiter: rate_limit.RateLimiter,
  req: wisp.Request,
  key: fn(wisp.Request) -> String,
) -> Int {
  let response =
    rate_limit.check(req, limiter, max: 2, window_ms: 60_000, key:, next: ok)
  response.status
}

// =============================================================================
// Limiting
// =============================================================================

pub fn limits_requests_per_key_test() {
  let assert Ok(limiter) = rate_limit.start()
  let alice = fn(_) { "alice" }
  let bob = fn(_) { "bob" }
  let req = request_with([])

  status(limiter, req, alice) |> should.equal(200)
  status(limiter, req, alice) |> should.equal(200)
  status(limiter, req, alice) |> should.equal(429)
  // Other keys have their own bucket
  status(limiter, req, bob) |> should.equal(200)
}

pub fn spoofed_forwarded_for_does_not_reset_the_limit_test() {
  let assert Ok(limiter) = rate_limit.start()
  let key = rate_limit.by_forwarded_for(trusted_proxies: 1)
  // The client makes up the left part; the proxy appends 203.0.113.7
  let spoofed = fn(fake) {
    request_with([#("x-forwarded-for", fake <> ", 203.0.113.7")])
  }

  status(limiter, spoofed("10.0.0.1"), key) |> should.equal(200)
  status(limiter, spoofed("10.0.0.2"), key) |> should.equal(200)
  status(limiter, spoofed("10.0.0.3"), key) |> should.equal(429)
}

// =============================================================================
// Key selection
// =============================================================================

pub fn by_forwarded_for_takes_entry_appended_by_trusted_proxy_test() {
  let req = request_with([#("x-forwarded-for", "1.1.1.1, 2.2.2.2 , 3.3.3.3")])

  rate_limit.by_forwarded_for(trusted_proxies: 1)(req)
  |> should.equal("3.3.3.3")
  rate_limit.by_forwarded_for(trusted_proxies: 2)(req)
  |> should.equal("2.2.2.2")
  rate_limit.by_forwarded_for(trusted_proxies: 3)(req)
  |> should.equal("1.1.1.1")
  // More proxies than entries: fall back to the left-most entry
  rate_limit.by_forwarded_for(trusted_proxies: 5)(req)
  |> should.equal("1.1.1.1")
}

pub fn by_forwarded_for_reads_repeated_headers_in_order_test() {
  let req =
    request_with([
      #("x-forwarded-for", "1.1.1.1"),
      #("x-forwarded-for", "2.2.2.2"),
    ])

  rate_limit.by_forwarded_for(trusted_proxies: 1)(req)
  |> should.equal("2.2.2.2")
}

pub fn by_forwarded_for_without_header_is_unknown_test() {
  rate_limit.by_forwarded_for(trusted_proxies: 1)(request_with([]))
  |> should.equal("unknown")
}

pub fn by_header_reads_proxy_header_test() {
  let req =
    request_with([
      #("x-forwarded-for", "9.9.9.9"),
      #("cf-connecting-ip", " 198.51.100.4 "),
    ])

  rate_limit.by_header("CF-Connecting-IP")(req)
  |> should.equal("198.51.100.4")
  rate_limit.by_header("fly-client-ip")(req)
  |> should.equal("unknown")
}

// =============================================================================
// Eviction
// =============================================================================

pub fn cleanup_forgets_idle_clients_test() {
  let assert Ok(limiter) = rate_limit.start_with_cleanup_interval(every: 20)
  let check = fn(key, window_ms) {
    rate_limit.check(
      request_with([]),
      limiter,
      max: 10,
      window_ms:,
      key: fn(_) { key },
      next: ok,
    )
  }

  check("short-lived", 10)
  check("long-lived", 60_000)
  rate_limit.tracked_keys(limiter) |> should.equal(2)

  // After the short window and a cleanup pass, only the active key remains
  process.sleep(100)
  rate_limit.tracked_keys(limiter) |> should.equal(1)

  // The remaining key still counts its earlier request
  check("long-lived", 60_000)
  rate_limit.tracked_keys(limiter) |> should.equal(1)
}

pub fn cleanup_keeps_key_checked_with_a_longer_window_test() {
  let assert Ok(limiter) = rate_limit.start_with_cleanup_interval(every: 20)
  let check = fn(window_ms) {
    rate_limit.check(
      request_with([]),
      limiter,
      max: 10,
      window_ms:,
      key: fn(_) { "shared" },
      next: ok,
    )
  }

  // The same key is limited per minute elsewhere, so a short window here
  // must not make cleanup forget it.
  check(60_000)
  check(10)
  process.sleep(100)
  rate_limit.tracked_keys(limiter) |> should.equal(1)
}
