import gleam/dict.{type Dict}
import gleam/list
import gleam/string
import gleeunit/should
import refrakt_cli/dev
import simplifile

// -- Watcher selection --------------------------------------------------------

pub fn fswatch_is_preferred_test() {
  dev.choose_watcher(
    os: "linux",
    fswatch: Ok("/usr/bin/fswatch"),
    inotifywait: Ok("/usr/bin/inotifywait"),
  )
  |> should.equal(dev.Fswatch("/usr/bin/fswatch"))
}

pub fn inotifywait_is_used_on_linux_without_fswatch_test() {
  dev.choose_watcher(
    os: "linux",
    fswatch: Error(Nil),
    inotifywait: Ok("/usr/bin/inotifywait"),
  )
  |> should.equal(dev.Inotifywait("/usr/bin/inotifywait"))
}

pub fn polling_is_the_fallback_test() {
  dev.choose_watcher(os: "linux", fswatch: Error(Nil), inotifywait: Error(Nil))
  |> should.equal(dev.Polling(500))

  dev.choose_watcher(
    os: "darwin",
    fswatch: Error(Nil),
    inotifywait: Ok("/opt/inotifywait"),
  )
  |> should.equal(dev.Polling(500))
}

pub fn startup_message_names_the_watcher_test() {
  dev.describe_watcher(dev.Fswatch("/usr/bin/fswatch"))
  |> should.equal("with fswatch")
  dev.describe_watcher(dev.Inotifywait("/usr/bin/inotifywait"))
  |> should.equal("with inotifywait")
  dev.describe_watcher(dev.Polling(500))
  |> string.starts_with("by polling every 500ms")
  |> should.be_true
}

pub fn live_reload_port_defaults_to_35729_test() {
  dev.live_reload_port(Error(Nil)) |> should.equal(35_729)
  dev.live_reload_port(Ok("nope")) |> should.equal(35_729)
  dev.live_reload_port(Ok("0")) |> should.equal(35_729)
  dev.live_reload_port(Ok("4100")) |> should.equal(4100)
}

// -- What a change calls for --------------------------------------------------

pub fn source_change_rebuilds_test() {
  dev.classify([#("src", "src/app/web/home_handler.gleam")])
  |> should.equal(dev.Rebuild)
}

pub fn source_and_static_change_rebuilds_test() {
  dev.classify([
    #("priv", "priv/static/css/app.css"),
    #("src", "/home/me/app/src/app/router.gleam"),
  ])
  |> should.equal(dev.Rebuild)
}

pub fn static_change_only_reloads_test() {
  dev.classify([#("priv", "/home/me/app/priv/static/css/app.css")])
  |> should.equal(dev.ReloadOnly)
}

pub fn editor_scratch_files_are_ignored_test() {
  dev.classify([
    #("src", "src/app/.home_handler.gleam.swp"),
    #("src", "src/app/home_handler.gleam~"),
    #("src", "src/app/4913"),
    #("src", "src/app/.#home_handler.gleam"),
  ])
  |> should.equal(dev.NoChange)

  dev.classify([]) |> should.equal(dev.NoChange)
}

// -- Polling ------------------------------------------------------------------

pub fn changed_paths_finds_added_changed_and_removed_files_test() {
  let before = dict.from_list([#("a", 1), #("b", 2), #("c", 3)])
  let after = dict.from_list([#("a", 1), #("b", 20), #("d", 4)])

  dev.changed_paths(before, after)
  |> should.equal(["b", "c", "d"])
}

pub fn changed_paths_is_empty_without_changes_test() {
  let snapshot = dict.from_list([#("a", 1)])
  dev.changed_paths(snapshot, snapshot) |> should.equal([])
}

pub fn snapshot_notices_a_rewrite_within_the_same_second_test() {
  let dir = "build/dev_test_snapshot"
  let file = dir <> "/handler.gleam"
  let _ = simplifile.delete(dir)
  let assert Ok(_) = simplifile.create_directory_all(dir <> "/nested")
  let assert Ok(_) = simplifile.write(file, "pub fn a() { 1 }")
  let assert Ok(_) = simplifile.write(dir <> "/nested/view.gleam", "x")

  let before = snapshot(dir)
  // Same size, very likely the same second: only the contents differ.
  let assert Ok(_) = simplifile.write(file, "pub fn a() { 2 }")
  let after = snapshot(dir)
  let assert Ok(_) = simplifile.delete(dir)

  dict.size(before) |> should.equal(2)
  dev.changed_paths(before, after) |> should.equal([file])
}

// -- Debounce -----------------------------------------------------------------

pub fn burst_of_events_is_collected_into_one_batch_test() {
  send_change("src", "src/a.gleam")
  send_change("src", "src/b.gleam")
  send_change_after(50, "priv", "priv/static/app.css")
  send_change_after(120, "src", "src/c.gleam")

  let changes = collect_changes([#("src", "src/first.gleam")], 150)

  changes
  |> list.map(fn(change) { change.1 })
  |> should.equal([
    "src/first.gleam",
    "src/a.gleam",
    "src/b.gleam",
    "priv/static/app.css",
    "src/c.gleam",
  ])
  flush_changes(0) |> should.equal(0)
}

pub fn events_after_a_quiet_window_start_a_new_batch_test() {
  send_change_after(300, "src", "src/later.gleam")

  collect_changes([#("src", "src/now.gleam")], 100)
  |> should.equal([#("src", "src/now.gleam")])

  flush_changes(500) |> should.equal(1)
}

// -- Live reload stream -------------------------------------------------------

pub fn reload_stream_sends_a_reload_event_test() {
  let received = reload_stream_receives()

  received |> string.contains("HTTP/1.1 200 OK") |> should.be_true
  received
  |> string.contains("Content-Type: text/event-stream")
  |> should.be_true
  received
  |> string.contains("Access-Control-Allow-Origin: *")
  |> should.be_true
  received
  |> string.contains("event: reload\ndata: reload\n\n")
  |> should.be_true
}

pub fn reload_server_answers_404_elsewhere_test() {
  reload_server_get("/") |> should.equal("HTTP/1.1 404 Not Found")
}

@external(erlang, "refrakt_cli_dev_ffi", "snapshot")
fn snapshot(dir: String) -> Dict(String, Stamp)

type Stamp

@external(erlang, "refrakt_cli_dev_ffi", "collect_changes")
fn collect_changes(
  first: List(#(String, String)),
  window_ms: Int,
) -> List(#(String, String))

@external(erlang, "refrakt_cli_dev_test_ffi", "send_change")
fn send_change(dir: String, path: String) -> Nil

@external(erlang, "refrakt_cli_dev_test_ffi", "send_change_after")
fn send_change_after(ms: Int, dir: String, path: String) -> Nil

@external(erlang, "refrakt_cli_dev_test_ffi", "flush_changes")
fn flush_changes(within_ms: Int) -> Int

@external(erlang, "refrakt_cli_dev_test_ffi", "reload_stream_receives")
fn reload_stream_receives() -> String

@external(erlang, "refrakt_cli_dev_test_ffi", "reload_server_get")
fn reload_server_get(path: String) -> String
