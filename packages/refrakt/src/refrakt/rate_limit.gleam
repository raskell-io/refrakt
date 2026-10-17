//// Rate limiting middleware using a sliding window counter.
////
//// **Experimental.** This module is lightly used and may change or move
//// to its own package; see https://github.com/raskell-io/refrakt/issues/28.
////
//// A single OTP actor keeps the request timestamps per client. Clients
//// whose requests have all left their window are dropped by a periodic
//// cleanup, so memory stays bounded by the number of recently active
//// clients.
////
//// ## Usage
////
//// ```gleam
//// import refrakt/rate_limit
////
//// // Start the rate limiter (once at app startup)
//// let assert Ok(limiter) = rate_limit.start()
////
//// fn middleware(req, next) {
////   use <- rate_limit.check(
////     req,
////     limiter,
////     max: 100,          // max requests
////     window_ms: 60_000, // per minute
////     key: rate_limit.by_forwarded_for(trusted_proxies: 1),
////   )
////   next(req)
//// }
//// ```
////
//// ## Choosing the client key
////
//// Requests are counted per key, so the key must be something a client
//// cannot change at will. Wisp does not expose the socket peer address,
//// so you say where the client address comes from:
////
//// - **Behind a reverse proxy** (nginx, Caddy, a load balancer), use
////   `by_forwarded_for(trusted_proxies: n)` where `n` is the number of
////   proxies in front of the app. Each proxy appends the address it saw
////   to `X-Forwarded-For`, so the client is the `n`th entry from the
////   right. Anything further left was sent by the client and is ignored.
////   Set `n` correctly: too high and clients can pick their own key, too
////   low and every client shares the proxy's key.
//// - **Behind a proxy that sets a single header** it always overwrites
////   (`CF-Connecting-IP` on Cloudflare, `Fly-Client-IP` on Fly.io,
////   `X-Real-IP` with nginx's `proxy_set_header`), use
////   `by_header("cf-connecting-ip")`. Only do this when every request
////   passes through that proxy; otherwise clients can send the header
////   themselves.
//// - **Directly exposed** (no proxy), forwarding headers come from the
////   client and must not be trusted. Read the peer address from Mist
////   before handing the request to Wisp and pass a key function that
////   returns it:
////
//// ```gleam
//// // In main()
//// let handler = fn(req: request.Request(mist.Connection)) {
////   let client_ip = case mist.get_connection_info(req.body) {
////     Ok(info) -> mist.ip_address_to_string(info.ip_address)
////     Error(_) -> "unknown"
////   }
////   wisp_mist.handler(
////     router.handle_request(_, ctx, client_ip),
////     cfg.secret_key_base,
////   )(req)
//// }
////
//// // In the router
//// use <- rate_limit.check(req, limiter, max: 100, window_ms: 60_000, key: fn(_) {
////   client_ip
//// })
//// ```
////
//// Any `fn(Request) -> String` works as a key, so you can also limit per
//// user or per API token.
////

import gleam/dict.{type Dict}
import gleam/erlang/process.{type Subject}
import gleam/int
import gleam/list
import gleam/otp/actor
import gleam/result
import gleam/string
import wisp.{type Request, type Response}

/// A running rate limiter instance.
pub type RateLimiter =
  Subject(RateLimitMessage)

pub opaque type RateLimitMessage {
  Check(key: String, max: Int, window_ms: Int, reply: Subject(Bool))
  Cleanup
  TrackedKeys(reply: Subject(Int))
}

/// The timestamps (newest first) of a key's allowed requests, and the
/// longest window it has been checked with, which decides when the key
/// can be forgotten.
type Entry {
  Entry(timestamps: List(Int), window_ms: Int)
}

type State {
  State(
    self: Subject(RateLimitMessage),
    entries: Dict(String, Entry),
    cleanup_interval_ms: Int,
  )
}

/// Start the rate limiter actor. Idle clients are forgotten once a minute.
pub fn start() -> Result(RateLimiter, actor.StartError) {
  start_with_cleanup_interval(every: 60_000)
}

/// Start the rate limiter actor, dropping clients with no requests left in
/// their window every `interval_ms` milliseconds.
pub fn start_with_cleanup_interval(
  every interval_ms: Int,
) -> Result(RateLimiter, actor.StartError) {
  actor.new_with_initialiser(1000, fn(self) {
    process.send_after(self, interval_ms, Cleanup)

    State(self:, entries: dict.new(), cleanup_interval_ms: interval_ms)
    |> actor.initialised
    |> actor.returning(self)
    |> Ok
  })
  |> actor.on_message(handle_message)
  |> actor.start
  |> result.map(fn(started) { started.data })
}

/// Check if a request is within the rate limit for its key.
/// Returns 429 Too Many Requests if exceeded.
pub fn check(
  req: Request,
  limiter: RateLimiter,
  max max: Int,
  window_ms window_ms: Int,
  key key: fn(Request) -> String,
  next next: fn() -> Response,
) -> Response {
  let reply = process.new_subject()
  process.send(limiter, Check(key: key(req), max:, window_ms:, reply:))

  case process.receive(reply, 5000) {
    Ok(True) -> next()
    Ok(False) ->
      wisp.response(429)
      |> wisp.string_body("Rate limit exceeded. Try again later.")
    Error(_) -> next()
  }
}

/// Key requests by the client address that the app's own reverse proxies
/// recorded in `X-Forwarded-For`: the `trusted_proxies`th entry from the
/// right. Entries further left are client-supplied and ignored. Requests
/// without the header share the `"unknown"` key.
pub fn by_forwarded_for(
  trusted_proxies trusted_proxies: Int,
) -> fn(Request) -> String {
  fn(req: Request) {
    let addresses =
      req.headers
      |> list.filter(fn(header) { header.0 == "x-forwarded-for" })
      |> list.flat_map(fn(header) { string.split(header.1, ",") })
      |> list.map(string.trim)
      |> list.filter(fn(address) { address != "" })
      |> list.reverse

    // With fewer entries than proxies, the left-most one is still the
    // closest we have to the client.
    case list.drop(addresses, int.max(trusted_proxies, 1) - 1), addresses {
      [address, ..], _ -> address
      [], [_, ..] -> list.last(addresses) |> result.unwrap("unknown")
      [], [] -> "unknown"
    }
  }
}

/// Key requests by a single-valued header that a trusted proxy always
/// sets, such as `cf-connecting-ip`. Header names are lowercase in Wisp.
/// Requests without the header share the `"unknown"` key.
pub fn by_header(name: String) -> fn(Request) -> String {
  let name = string.lowercase(name)
  fn(req: Request) {
    req.headers
    |> list.filter(fn(header) { header.0 == name })
    |> list.last
    |> result.map(fn(header) { string.trim(header.1) })
    |> result.unwrap("unknown")
  }
}

/// The number of clients the limiter currently remembers.
pub fn tracked_keys(limiter: RateLimiter) -> Int {
  process.call(limiter, waiting: 5000, sending: TrackedKeys)
}

fn handle_message(
  state: State,
  msg: RateLimitMessage,
) -> actor.Next(State, RateLimitMessage) {
  case msg {
    Check(key:, max:, window_ms:, reply:) -> {
      let now = erlang_system_time_ms()
      let cutoff = now - window_ms

      // Keep the timestamps still inside this window
      let #(timestamps, longest_window) = case dict.get(state.entries, key) {
        Ok(entry) -> #(
          list.filter(entry.timestamps, fn(t) { t > cutoff }),
          int.max(entry.window_ms, window_ms),
        )
        Error(_) -> #([], window_ms)
      }

      let allowed = list.length(timestamps) < max
      let timestamps = case allowed {
        True -> [now, ..timestamps]
        False -> timestamps
      }

      process.send(reply, allowed)

      let entry = Entry(timestamps:, window_ms: longest_window)
      actor.continue(
        State(..state, entries: dict.insert(state.entries, key, entry)),
      )
    }

    Cleanup -> {
      let now = erlang_system_time_ms()
      let entries =
        dict.filter(state.entries, fn(_key, entry) {
          case entry.timestamps {
            [newest, ..] -> newest > now - entry.window_ms
            [] -> False
          }
        })

      process.send_after(state.self, state.cleanup_interval_ms, Cleanup)
      actor.continue(State(..state, entries:))
    }

    TrackedKeys(reply:) -> {
      process.send(reply, dict.size(state.entries))
      actor.continue(state)
    }
  }
}

@external(erlang, "refrakt_rate_limit_ffi", "system_time_ms")
fn erlang_system_time_ms() -> Int
