//// Basic telemetry and request metrics.
////
//// **Experimental.** This module is lightly used and may change or move
//// to its own package; see https://github.com/raskell-io/refrakt/issues/28.
////
//// Tracks request counts, response times, and error rates.
//// Use as middleware to collect metrics automatically.
////
//// ## Usage
////
//// ```gleam
//// import refrakt/telemetry
////
//// // Start the metrics collector
//// let assert Ok(metrics) = telemetry.start()
////
//// // Add to middleware
//// fn middleware(req, next) {
////   use <- telemetry.track(req, metrics)
////   next(req)
//// }
////
//// // Get current metrics
//// let stats = telemetry.get_stats(metrics)
//// // stats.total_requests, stats.avg_response_ms, etc.
//// ```
////

import gleam/dict.{type Dict}
import gleam/erlang/process.{type Subject}
import gleam/otp/actor
import gleam/result
import wisp.{type Request, type Response}

/// A running telemetry collector.
pub type Metrics =
  Subject(MetricsMessage)

/// Collected statistics.
pub type Stats {
  Stats(
    total_requests: Int,
    total_errors: Int,
    status_counts: Dict(Int, Int),
    avg_response_ms: Int,
  )
}

pub opaque type MetricsMessage {
  RecordRequest(status: Int, duration_ms: Int)
  GetStats(reply: Subject(Stats))
}

type State {
  State(
    total_requests: Int,
    total_errors: Int,
    status_counts: Dict(Int, Int),
    total_duration_ms: Int,
  )
}

/// Start the telemetry collector.
pub fn start() -> Result(Metrics, actor.StartError) {
  actor.new(State(
    total_requests: 0,
    total_errors: 0,
    status_counts: dict.new(),
    total_duration_ms: 0,
  ))
  |> actor.on_message(handle_message)
  |> actor.start
  |> result.map(fn(started) { started.data })
}

/// Middleware that tracks request duration and status.
pub fn track(
  _req: Request,
  metrics: Metrics,
  next: fn() -> Response,
) -> Response {
  let start = system_time_ms()
  let resp = next()
  let duration = system_time_ms() - start

  process.send(
    metrics,
    RecordRequest(status: resp.status, duration_ms: duration),
  )
  resp
}

/// Get current metrics statistics.
pub fn get_stats(metrics: Metrics) -> Stats {
  let reply = process.new_subject()
  process.send(metrics, GetStats(reply:))
  case process.receive(reply, 5000) {
    Ok(stats) -> stats
    Error(_) ->
      Stats(
        total_requests: 0,
        total_errors: 0,
        status_counts: dict.new(),
        avg_response_ms: 0,
      )
  }
}

fn handle_message(
  state: State,
  msg: MetricsMessage,
) -> actor.Next(State, MetricsMessage) {
  case msg {
    RecordRequest(status:, duration_ms:) -> {
      let is_error = status >= 500
      let count = case dict.get(state.status_counts, status) {
        Ok(c) -> c + 1
        Error(_) -> 1
      }
      actor.continue(State(
        total_requests: state.total_requests + 1,
        total_errors: case is_error {
          True -> state.total_errors + 1
          False -> state.total_errors
        },
        status_counts: dict.insert(state.status_counts, status, count),
        total_duration_ms: state.total_duration_ms + duration_ms,
      ))
    }

    GetStats(reply:) -> {
      let avg = case state.total_requests {
        0 -> 0
        n -> state.total_duration_ms / n
      }
      process.send(
        reply,
        Stats(
          total_requests: state.total_requests,
          total_errors: state.total_errors,
          status_counts: state.status_counts,
          avg_response_ms: avg,
        ),
      )
      actor.continue(state)
    }
  }
}

@external(erlang, "refrakt_rate_limit_ffi", "system_time_ms")
fn system_time_ms() -> Int
