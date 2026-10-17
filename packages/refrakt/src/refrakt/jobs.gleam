//// Background job processing using OTP processes.
////
//// **Experimental.** This module is lightly used and may change or move
//// to its own package; see https://github.com/raskell-io/refrakt/issues/28.
////
//// Run expensive work outside the request cycle — emails, image
//// processing, reports, webhooks.
////
//// ## Usage
////
//// ```gleam
//// import refrakt/jobs
////
//// // Start the job runner
//// let assert Ok(runner) = jobs.start(max_concurrency: 10)
////
//// // Enqueue a job
//// jobs.enqueue(runner, fn() {
////   // Send welcome email, process image, etc.
////   mailer.deliver(email, adapter)
//// })
////
//// // Enqueue with a name (for logging)
//// jobs.enqueue_named(runner, "send_welcome_email", fn() {
////   mailer.deliver(email, adapter)
//// })
//// ```
////
//// At most `max_concurrency` jobs run at once; further jobs wait in a
//// queue. A job that crashes is logged and does not affect the runner.
////

import exception
import gleam/erlang/process.{type Subject}
import gleam/io
import gleam/list
import gleam/otp/actor
import gleam/result

/// A running job runner instance.
pub type JobRunner =
  Subject(JobMessage)

/// Messages the job runner handles.
pub opaque type JobMessage {
  Enqueue(job: Job)
  Finished
}

type Job {
  Job(name: String, work: fn() -> Nil)
}

type State {
  State(self: Subject(JobMessage), running: Int, max: Int, queue: List(Job))
}

/// Start a job runner with a maximum concurrency.
pub fn start(max_concurrency max: Int) -> Result(JobRunner, actor.StartError) {
  actor.new_with_initialiser(1000, fn(self) {
    State(self:, running: 0, max:, queue: [])
    |> actor.initialised
    |> actor.returning(self)
    |> Ok
  })
  |> actor.on_message(handle_message)
  |> actor.start
  |> result.map(fn(started) { started.data })
}

/// Enqueue a job for background execution.
pub fn enqueue(runner: JobRunner, work: fn() -> Nil) -> Nil {
  process.send(runner, Enqueue(Job(name: "job", work:)))
}

/// Enqueue a named job for background execution (name used in logs).
pub fn enqueue_named(
  runner: JobRunner,
  name: String,
  work: fn() -> Nil,
) -> Nil {
  process.send(runner, Enqueue(Job(name:, work:)))
}

fn handle_message(
  state: State,
  msg: JobMessage,
) -> actor.Next(State, JobMessage) {
  case msg {
    Enqueue(job) ->
      case state.running < state.max {
        True -> {
          run(job, state.self)
          actor.continue(State(..state, running: state.running + 1))
        }
        False ->
          actor.continue(State(..state, queue: list.append(state.queue, [job])))
      }

    Finished ->
      case state.queue {
        [next, ..rest] -> {
          run(next, state.self)
          actor.continue(State(..state, queue: rest))
        }
        [] -> actor.continue(State(..state, running: state.running - 1))
      }
  }
}

/// Run a job in its own unlinked process, reporting back when it ends
/// so the runner can start the next queued job.
fn run(job: Job, runner: Subject(JobMessage)) -> Nil {
  process.spawn_unlinked(fn() {
    io.println("[job] started: " <> job.name)
    case exception.rescue(job.work) {
      Ok(Nil) -> io.println("[job] completed: " <> job.name)
      Error(_) -> io.println("[job] crashed: " <> job.name)
    }
    process.send(runner, Finished)
  })
  Nil
}
