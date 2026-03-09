/// `refrakt dev` — start the dev server with file watching.
///
/// Sets APP_ENV=dev and runs `gleam run`. On file change, rebuilds
/// and restarts automatically using fswatch if available, otherwise
/// runs once.
///
import gleam/io

@external(erlang, "refrakt_dev_ffi", "run_dev")
fn run_dev() -> Nil

pub fn run() {
  io.println("Starting dev server (APP_ENV=dev)...")
  io.println("")
  run_dev()
}
