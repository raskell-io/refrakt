//// `refrakt dev` — run the app in development with rebuilds and live reload.
////
//// Sets `APP_ENV=dev`, builds the app and starts it with `gleam run`.
//// Then it watches `src/` and `priv/`:
////
//// - A change under `src/` rebuilds. When the build succeeds the server
////   restarts; when it fails the compiler error is printed and the old
////   server keeps running until the next successful build.
//// - After a restart, or a change under `priv/` (served as is), open pages
////   reload: `refrakt dev` runs a small Server-Sent Events server on
////   `REFRAKT_LIVE_RELOAD_PORT` (35729 by default) and sends it a `reload`
////   event. The root layout's `refrakt/live_reload.script()` listens to it
////   and renders only under `refrakt dev` with `APP_ENV=dev`.
////
//// Files are watched with `fswatch` when it is installed, else with
//// `inotifywait` on Linux, else by polling every 500ms. Bursts of events
//// (an editor saving several files) are debounced into one rebuild.
////
//// The process work (ports, sockets, polling) lives in
//// `refrakt_cli_dev_ffi.erl`; the decisions it makes are the functions
//// below, so they can be unit-tested.
////

import gleam/dict.{type Dict}
import gleam/int
import gleam/io
import gleam/list
import gleam/result
import gleam/string

/// How `refrakt dev` notices file changes.
pub type Watcher {
  /// `fswatch` (macOS, BSD, Linux), given its path.
  Fswatch(executable: String)
  /// `inotifywait` from inotify-tools (Linux), given its path.
  Inotifywait(executable: String)
  /// Compare file sizes, times and contents every `interval_ms`.
  Polling(interval_ms: Int)
}

/// What a batch of file changes calls for.
pub type Change {
  /// Something under `src/` changed: rebuild and restart.
  Rebuild
  /// Only files under `priv/` changed: they are served as they are, so
  /// reloading the browser is enough.
  ReloadOnly
  /// Only editor scratch files changed.
  NoChange
}

/// The default port of the live reload event stream.
pub const default_live_reload_port = 35_729

/// How long to wait for more file events before acting on a burst.
pub const debounce_ms = 200

/// How often the polling watcher compares snapshots.
pub const poll_interval_ms = 500

pub fn run() {
  let watcher =
    choose_watcher(
      os: os_family(),
      fswatch: find_executable("fswatch"),
      inotifywait: find_executable("inotifywait"),
    )
  let live_reload_port = live_reload_port(getenv("REFRAKT_LIVE_RELOAD_PORT"))
  let app_port =
    getenv("PORT")
    |> result.try(int.parse)
    |> result.unwrap(4000)

  io.println("Starting dev server (APP_ENV=dev)...")
  io.println("Watching src/ and priv/ " <> describe_watcher(watcher))
  run_dev(watcher, live_reload_port, app_port, debounce_ms)
}

/// Prefer `fswatch`, then `inotifywait` on Linux, then polling.
pub fn choose_watcher(
  os os: String,
  fswatch fswatch: Result(String, Nil),
  inotifywait inotifywait: Result(String, Nil),
) -> Watcher {
  case fswatch, inotifywait, os {
    Ok(path), _, _ -> Fswatch(path)
    Error(_), Ok(path), "linux" -> Inotifywait(path)
    _, _, _ -> Polling(poll_interval_ms)
  }
}

pub fn describe_watcher(watcher: Watcher) -> String {
  case watcher {
    Fswatch(_) -> "with fswatch"
    Inotifywait(_) -> "with inotifywait"
    Polling(interval) ->
      "by polling every "
      <> int.to_string(interval)
      <> "ms (install fswatch, or inotify-tools on Linux, for instant updates)"
  }
}

/// The port from `REFRAKT_LIVE_RELOAD_PORT`, or the default when it is
/// unset or not a port number.
pub fn live_reload_port(value: Result(String, Nil)) -> Int {
  case result.try(value, int.parse) {
    Ok(port) if port > 0 && port < 65_536 -> port
    _ -> default_live_reload_port
  }
}

/// Decide what a debounced batch of `#(watched_dir, path)` changes calls
/// for. Editor scratch files (swap files, backups, dotfiles) are ignored.
pub fn classify(changes: List(#(String, String))) -> Change {
  let relevant = list.filter(changes, fn(change) { is_relevant(change.1) })
  case
    list.any(relevant, fn(change) { change.0 == "src" }),
    list.any(relevant, fn(change) { change.0 == "priv" })
  {
    True, _ -> Rebuild
    False, True -> ReloadOnly
    False, False -> NoChange
  }
}

/// False for files editors write while saving: dotfiles (`.post.swp`,
/// `.#post.gleam`), backups (`post.gleam~`), and vim's `4913` probe.
pub fn is_relevant(path: String) -> Bool {
  let name =
    path
    |> string.split("/")
    |> list.last
    |> result.unwrap(path)
  let scratch =
    name == ""
    || name == "4913"
    || string.starts_with(name, ".")
    || string.ends_with(name, "~")
    || string.ends_with(name, ".swp")
    || string.ends_with(name, ".swx")
  !scratch
}

/// The paths that were added, removed or changed between two polling
/// snapshots, sorted.
pub fn changed_paths(
  before: Dict(String, stamp),
  after: Dict(String, stamp),
) -> List(String) {
  let changed_or_added =
    dict.fold(after, [], fn(acc, path, stamp) {
      case dict.get(before, path) {
        Ok(old) if old == stamp -> acc
        _ -> [path, ..acc]
      }
    })
  let removed =
    dict.fold(before, [], fn(acc, path, _) {
      case dict.has_key(after, path) {
        True -> acc
        False -> [path, ..acc]
      }
    })
  list.append(changed_or_added, removed)
  |> list.sort(string.compare)
}

@external(erlang, "refrakt_cli_dev_ffi", "run_dev")
fn run_dev(
  watcher: Watcher,
  live_reload_port: Int,
  app_port: Int,
  debounce_ms: Int,
) -> Nil

@external(erlang, "refrakt_cli_dev_ffi", "os_family")
fn os_family() -> String

@external(erlang, "refrakt_cli_dev_ffi", "find_executable")
fn find_executable(name: String) -> Result(String, Nil)

@external(erlang, "refrakt_cli_dev_ffi", "getenv")
fn getenv(name: String) -> Result(String, Nil)
