/// Rate limiting middleware using a sliding window counter.
///
/// Uses an ETS table for fast concurrent access.
///
/// ## Usage
///
/// ```gleam
/// import refrakt/rate_limit
///
/// // Start the rate limiter (once at app startup)
/// let assert Ok(limiter) = rate_limit.start()
///
/// fn middleware(req, next) {
///   use <- rate_limit.check(
///     req,
///     limiter,
///     max: 100,          // max requests
///     window_ms: 60_000, // per minute
///   )
///   next(req)
/// }
/// ```
///
import gleam/dict.{type Dict}
import gleam/erlang/process.{type Subject}
import gleam/list
import gleam/otp/actor
import gleam/result
import wisp.{type Request, type Response}

/// A running rate limiter instance.
pub type RateLimiter =
  Subject(RateLimitMessage)

pub opaque type RateLimitMessage {
  Check(key: String, max: Int, window_ms: Int, reply: Subject(Bool))
  Cleanup
}

type Entry {
  Entry(timestamps: List(Int))
}

type State {
  State(entries: Dict(String, Entry))
}

/// Start the rate limiter actor.
pub fn start() -> Result(RateLimiter, actor.StartError) {
  actor.new(State(entries: dict.new()))
  |> actor.on_message(handle_message)
  |> actor.start
  |> result.map(fn(started) { started.subject })
}

/// Check if a request is within the rate limit.
/// Returns 429 Too Many Requests if exceeded.
pub fn check(
  req: Request,
  limiter: RateLimiter,
  max max: Int,
  window_ms window_ms: Int,
  next: fn() -> Response,
) -> Response {
  let key = get_client_ip(req)
  let reply = process.new_subject()
  actor.send(limiter, Check(key:, max:, window_ms:, reply:))

  case process.receive(reply, 5000) {
    Ok(True) -> next()
    Ok(False) ->
      wisp.response(429)
      |> wisp.string_body("Rate limit exceeded. Try again later.")
    Error(_) -> next()
  }
}

fn handle_message(
  msg: RateLimitMessage,
  state: State,
) -> actor.Next(RateLimitMessage, State) {
  case msg {
    Check(key:, max:, window_ms:, reply:) -> {
      let now = erlang_system_time_ms()
      let cutoff = now - window_ms

      // Get existing timestamps, filter expired
      let timestamps = case dict.get(state.entries, key) {
        Ok(entry) -> list.filter(entry.timestamps, fn(t) { t > cutoff })
        Error(_) -> []
      }

      let allowed = list.length(timestamps) < max
      let new_timestamps = case allowed {
        True -> [now, ..timestamps]
        False -> timestamps
      }

      process.send(reply, allowed)

      let entries =
        dict.insert(state.entries, key, Entry(timestamps: new_timestamps))
      actor.continue(State(entries:))
    }

    Cleanup -> {
      // Periodic cleanup of expired entries
      actor.continue(state)
    }
  }
}

fn get_client_ip(req: Request) -> String {
  case list.find(req.headers, fn(h) { h.0 == "x-forwarded-for" }) {
    Ok(#(_, ip)) -> ip
    Error(_) ->
      case list.find(req.headers, fn(h) { h.0 == "x-real-ip" }) {
        Ok(#(_, ip)) -> ip
        Error(_) -> "unknown"
      }
  }
}

@external(erlang, "refrakt_rate_limit_ffi", "system_time_ms")
fn erlang_system_time_ms() -> Int
