/// `refrakt dev` — start the dev server.
///
/// Wraps `gleam run` with APP_ENV=dev set.
///
import gleam/io

@external(erlang, "refrakt_dev_ffi", "run_gleam")
fn run_gleam() -> Nil

pub fn run() {
  io.println("Starting dev server (APP_ENV=dev)...")
  io.println("")
  run_gleam()
}
