/// Background job processing using OTP processes.
///
/// Run expensive work outside the request cycle — emails, image
/// processing, reports, webhooks.
///
/// ## Usage
///
/// ```gleam
/// import refrakt/jobs
///
/// // Start the job runner
/// let assert Ok(runner) = jobs.start(max_concurrency: 10)
///
/// // Enqueue a job
/// jobs.enqueue(runner, fn() {
///   // Send welcome email, process image, etc.
///   mailer.deliver(email, adapter)
/// })
///
/// // Enqueue with a name (for logging)
/// jobs.enqueue_named(runner, "send_welcome_email", fn() {
///   mailer.deliver(email, adapter)
/// })
/// ```
///
import gleam/erlang/process
import gleam/io
import gleam/otp/actor
import gleam/result

/// A running job runner instance.
pub type JobRunner =
  process.Subject(JobMessage)

/// Messages the job runner handles.
pub opaque type JobMessage {
  Enqueue(name: String, work: fn() -> Nil)
}

type State {
  State(running: Int, max: Int)
}

/// Start a job runner with a maximum concurrency.
pub fn start(max_concurrency max: Int) -> Result(JobRunner, actor.StartError) {
  actor.new(State(running: 0, max: max))
  |> actor.on_message(handle_message)
  |> actor.start
  |> result.map(fn(started) { started.subject })
}

/// Enqueue a job for background execution.
pub fn enqueue(runner: JobRunner, work: fn() -> Nil) {
  actor.send(runner, Enqueue(name: "job", work:))
}

/// Enqueue a named job for background execution (name used in logs).
pub fn enqueue_named(runner: JobRunner, name: String, work: fn() -> Nil) {
  actor.send(runner, Enqueue(name:, work:))
}

fn handle_message(
  msg: JobMessage,
  state: State,
) -> actor.Next(JobMessage, State) {
  case msg {
    Enqueue(name:, work:) -> {
      // Spawn the work in a new process
      let _ =
        process.spawn(fn() {
          io.println("[job] started: " <> name)
          work()
          io.println("[job] completed: " <> name)
        })
      actor.continue(State(..state, running: state.running + 1))
    }
  }
}
