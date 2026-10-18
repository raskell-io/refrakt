//// `refrakt diff` — show how the app differs from what the current
//// templates generate.
////
//// Generated code belongs to the app, so upgrading refrakt_cli never
//// changes it. `refrakt diff` renders the app again with the installed
//// refrakt_cli into a temporary directory: `refrakt new` with the app's
//// name and database, then every generator recorded in
//// `.refrakt/generated.toml`, in order. It then prints a unified diff of
//// each file against the app's copy. It never writes into the app.
////
//// Apps created before the manifest existed have none; their generators
//// are inferred from the app's files (see `infer`).
////

import gleam/int
import gleam/io
import gleam/list
import gleam/option.{None, Some}
import gleam/order
import gleam/result
import gleam/string
import refrakt_cli/deploy
import refrakt_cli/gen
import refrakt_cli/manifest.{type Manifest, Manifest}
import refrakt_cli/new
import refrakt_cli/project
import simplifile

@external(erlang, "refrakt_cli_diff_ffi", "make_temp_dir")
fn make_temp_dir() -> Result(String, Nil)

@external(erlang, "refrakt_cli_diff_ffi", "run_in")
fn run_in(dir: String, f: fn() -> Nil) -> Result(String, String)

@external(erlang, "refrakt_cli_diff_ffi", "unified_diff")
fn unified_diff(
  file_a: String,
  file_b: String,
  label_a: String,
  label_b: String,
) -> Result(String, Nil)

@external(erlang, "refrakt_cli_diff_ffi", "halt")
fn halt(status: Int) -> Nil

/// Entry point for `refrakt diff`: runs and exits with its status.
pub fn main(args: List(String)) -> Nil {
  halt(run(args))
}

type Options {
  Options(stat: Bool, print_manifest: Bool, paths: List(String))
}

/// One file the templates generate, and the app's copy of it.
type Entry {
  Entry(
    /// The path in the app, relative to its root
    path: String,
    /// The rendered file, an absolute path in the temporary directory
    rendered: String,
  )
}

type Change {
  Changed(path: String, diff: String)
  Missing(path: String, diff: String)
}

/// The outcome of comparing the app with the rendered templates.
pub type Report {
  Report(
    /// Generated files whose content differs from the app's copy
    changed: List(String),
    /// Generated files the app does not have
    missing: List(String),
    /// App files under src/, test/ and priv/ that no generator writes
    only_in_app: List(String),
    /// How many generated files were compared
    compared: Int,
    /// Generators that could not be replayed
    problems: List(String),
  )
}

type Comparison {
  Comparison(
    changes: List(Change),
    only_in_app: List(String),
    compared: Int,
    problems: List(String),
  )
}

/// Run `refrakt diff` in the app in the current directory. Returns the
/// exit status: 0 when the app matches the templates, 1 when files differ
/// or are missing from the app, 2 on usage errors.
pub fn run(args: List(String)) -> Int {
  case parse_args(args, Options(False, False, [])) {
    Error(message) -> {
      io.println_error("Error: " <> message)
      io.println_error("Usage: refrakt diff [path...] [--stat]")
      2
    }
    Ok(options) ->
      case simplifile.is_file("gleam.toml") {
        Ok(True) -> run_in_app(options)
        _ -> {
          io.println_error(
            "Error: no gleam.toml here. Run refrakt diff in the root of a Refrakt app.",
          )
          2
        }
      }
  }
}

fn parse_args(args: List(String), options: Options) -> Result(Options, String) {
  case args {
    [] -> Ok(Options(..options, paths: list.reverse(options.paths)))
    ["--stat", ..rest] -> parse_args(rest, Options(..options, stat: True))
    ["--print-manifest", ..rest] ->
      parse_args(rest, Options(..options, print_manifest: True))
    [arg, ..rest] ->
      case string.starts_with(arg, "-") {
        True -> Error("unknown option " <> arg)
        False ->
          parse_args(
            rest,
            Options(..options, paths: [normalize_path(arg), ..options.paths]),
          )
      }
  }
}

fn normalize_path(path: String) -> String {
  let path = case string.starts_with(path, "./") {
    True -> string.drop_start(path, 2)
    False -> path
  }
  case string.ends_with(path, "/") && path != "/" {
    True -> normalize_path(string.drop_end(path, 1))
    False -> path
  }
}

/// Compare the app in the current directory with what the templates
/// generate, limited to `paths` (all files when empty), without printing.
pub fn check(paths: List(String)) -> Result(Report, String) {
  let app = project.app_name()
  let #(the_manifest, _) = load_manifest(app)
  use comparison <- result.map(compare(
    app,
    the_manifest,
    list.map(paths, normalize_path),
  ))
  Report(
    changed: list.filter_map(comparison.changes, fn(change) {
      case change {
        Changed(path, _) -> Ok(path)
        Missing(..) -> Error(Nil)
      }
    }),
    missing: list.filter_map(comparison.changes, fn(change) {
      case change {
        Missing(path, _) -> Ok(path)
        Changed(..) -> Error(Nil)
      }
    }),
    only_in_app: comparison.only_in_app,
    compared: comparison.compared,
    problems: comparison.problems,
  )
}

/// The recorded manifest, or one inferred from the app's files (`True`).
fn load_manifest(app: String) -> #(Manifest, Bool) {
  case manifest.read(".") {
    Ok(recorded) -> #(Manifest(..recorded, name: app), False)
    Error(_) -> #(
      Manifest(name: app, db: project.detect_db(), gens: infer(app)),
      True,
    )
  }
}

fn run_in_app(options: Options) -> Int {
  let app = project.app_name()
  let #(the_manifest, inferred) = load_manifest(app)

  case options.print_manifest {
    True -> {
      io.print(manifest.to_toml(the_manifest))
      0
    }
    False -> {
      case inferred {
        True -> print_inferred_note(the_manifest)
        False -> Nil
      }
      case compare(app, the_manifest, options.paths) {
        Error(message) -> {
          io.println_error("Error: " <> message)
          2
        }
        Ok(comparison) -> {
          list.each(comparison.problems, fn(problem) {
            io.println_error("Warning: " <> problem)
          })
          case options.stat {
            True -> print_stat(comparison.changes)
            False ->
              list.each(comparison.changes, fn(change) { io.print(change.diff) })
          }
          print_summary(
            comparison.changes,
            comparison.only_in_app,
            comparison.compared,
          )
          case comparison.changes {
            [] -> 0
            _ -> 1
          }
        }
      }
    }
  }
}

fn print_inferred_note(the_manifest: Manifest) -> Nil {
  io.println_error(
    "No " <> manifest.path <> " (the app predates refrakt_cli 0.7).",
  )
  io.println_error("Inferred these generators from the app's files:")
  io.println_error(
    "  new "
    <> the_manifest.name
    <> " --db "
    <> manifest.db_name(the_manifest.db),
  )
  list.each(the_manifest.gens, fn(args) {
    io.println_error("  gen " <> string.join(args, " "))
  })
  io.println_error(
    "If that is wrong, save `refrakt diff --print-manifest` as "
    <> manifest.path
    <> " and correct it.",
  )
  io.println_error("")
}

// =============================================================================
// Rendering
// =============================================================================

/// Render the app into `tmp`, replaying `refrakt new` and the generators.
/// Returns the rendered app's root and the generators that could not be
/// replayed.
fn render(
  app: String,
  the_manifest: Manifest,
  tmp: String,
) -> #(String, List(String)) {
  let root = tmp <> "/" <> app
  let new_flags = ["--db", manifest.db_name(the_manifest.db)]
  let new_problem = case run_in(tmp, fn() { new.run(root, new_flags) }) {
    Ok(_) -> []
    Error(output) -> ["refrakt new failed: " <> output]
  }
  let problems =
    list.fold(the_manifest.gens, new_problem, fn(problems, args) {
      let command = "gen " <> string.join(args, " ")
      case replay(args) {
        Error(Nil) -> [
          command <> ": not a generator refrakt diff replays",
          ..problems
        ]
        Ok(generate) ->
          case run_in(root, generate) {
            Ok(_) -> problems
            Error(output) -> [command <> " failed: " <> output, ..problems]
          }
      }
    })
  #(root, list.reverse(problems))
}

/// The generator for a manifest entry.
fn replay(args: List(String)) -> Result(fn() -> Nil, Nil) {
  case args {
    ["page", name] -> Ok(fn() { gen.page(name) })
    ["resource", name, ..rest] -> Ok(fn() { gen.resource(name, rest) })
    ["auth"] -> Ok(fn() { gen.auth() })
    ["island", name] -> Ok(fn() { gen.island(name) })
    ["live", name] -> Ok(fn() { gen.live(name) })
    ["deploy", ..flags] -> Ok(fn() { deploy.run(flags) })
    _ -> Error(Nil)
  }
}

// =============================================================================
// Comparing
// =============================================================================

/// Render the app into a temporary directory and compare it with the app.
fn compare(
  app: String,
  the_manifest: Manifest,
  paths: List(String),
) -> Result(Comparison, String) {
  use tmp <- result.map(
    make_temp_dir()
    |> result.replace_error("cannot create a temporary directory"),
  )
  let comparison = compare_rendered(app, the_manifest, tmp, paths)
  let _ = simplifile.delete_all([tmp])
  comparison
}

fn compare_rendered(
  app: String,
  the_manifest: Manifest,
  tmp: String,
  paths: List(String),
) -> Comparison {
  let #(root, problems) = render(app, the_manifest, tmp)

  let rendered_files =
    simplifile.get_files(root)
    |> result.unwrap([])
    |> list.map(fn(file) { string.drop_start(file, string.length(root) + 1) })
    |> list.filter(fn(path) { !string.starts_with(path, ".refrakt/") })

  let entries =
    rendered_files
    |> list.map(fn(path) { Entry(app_path(path), root <> "/" <> path) })
    |> list.filter(fn(entry) { in_scope(entry.path, paths) })
    |> list.sort(fn(a, b) { compare_paths(app, a.path, b.path) })

  let changes = list.filter_map(entries, compare_entry)

  let generated = list.map(entries, fn(entry) { entry.path })
  let only_in_app =
    app_files()
    |> list.filter(fn(path) {
      in_scope(path, paths) && !list.contains(generated, path)
    })
    |> list.sort(fn(a, b) { compare_paths(app, a, b) })

  Comparison(
    changes: changes,
    only_in_app: only_in_app,
    compared: list.length(entries),
    problems: problems,
  )
}

/// The app's path for a rendered file. Migration numbers depend on how
/// many migrations existed when the generator ran, so a rendered
/// `003_create_posts.sql` matches the app's `*_create_posts.sql`.
fn app_path(rendered: String) -> String {
  case string.contains(rendered, "/data/migrations/") {
    False -> rendered
    True ->
      case simplifile.is_file(rendered) {
        Ok(True) -> rendered
        _ -> find_migration(rendered) |> result.unwrap(rendered)
      }
  }
}

fn find_migration(rendered: String) -> Result(String, Nil) {
  let parts = string.split(rendered, "/")
  use file <- result.try(list.last(parts))
  use #(_number, suffix) <- result.try(string.split_once(file, "_"))
  let dir = parts |> list.take(list.length(parts) - 1) |> string.join("/")
  use files <- result.try(
    simplifile.read_directory(dir) |> result.replace_error(Nil),
  )
  files
  |> list.sort(string.compare)
  |> list.find(fn(name) {
    case string.split_once(name, "_") {
      Ok(#(number, rest)) -> rest == suffix && is_digits(number)
      Error(_) -> False
    }
  })
  |> result.map(fn(name) { dir <> "/" <> name })
}

fn is_digits(s: String) -> Bool {
  s != ""
  && string.to_graphemes(s)
  |> list.all(fn(c) { string.contains("0123456789", c) })
}

fn in_scope(path: String, paths: List(String)) -> Bool {
  case paths {
    [] -> True
    _ ->
      list.any(paths, fn(scope) {
        scope == "." || path == scope || string.starts_with(path, scope <> "/")
      })
  }
}

/// Files in the app that the templates could have written: everything
/// under src/, test/ and priv/, the files in the root, and the files of
/// `gen deploy` (Dockerfile, .dockerignore, fly.toml, bin/migrate).
fn app_files() -> List(String) {
  let nested =
    ["src", "test", "priv"]
    |> list.flat_map(fn(dir) { simplifile.get_files(dir) |> result.unwrap([]) })
  let top =
    [
      ".gitignore",
      "README.md",
      "gleam.toml",
      "Dockerfile",
      ".dockerignore",
      "fly.toml",
      "bin/migrate",
    ]
    |> list.filter(fn(path) { simplifile.is_file(path) == Ok(True) })
  list.append(top, nested)
}

fn compare_entry(entry: Entry) -> Result(Change, Nil) {
  let rendered = simplifile.read(entry.rendered) |> result.unwrap("")
  case simplifile.read(entry.path) {
    Ok(content) if content == rendered -> Error(Nil)
    Ok(content) ->
      Ok(Changed(
        entry.path,
        file_diff(entry.path, content, entry.rendered, rendered),
      ))
    Error(_) -> Ok(Missing(entry.path, new_file_diff(entry.path, rendered)))
  }
}

fn file_diff(
  path: String,
  content: String,
  rendered_file: String,
  rendered: String,
) -> String {
  case unified_diff(path, rendered_file, "a/" <> path, "b/" <> path) {
    Ok(output) -> output
    Error(Nil) -> line_diff("a/" <> path, "b/" <> path, content, rendered)
  }
}

fn new_file_diff(path: String, rendered: String) -> String {
  line_diff("/dev/null", "b/" <> path, "", rendered)
}

// =============================================================================
// A small unified diff, for systems without `diff`
// =============================================================================

/// One hunk covering everything between the common prefix and suffix,
/// with up to three lines of context.
@internal
pub fn line_diff(
  label_a: String,
  label_b: String,
  a: String,
  b: String,
) -> String {
  let a_lines = lines(a)
  let b_lines = lines(b)
  let prefix = common_prefix(a_lines, b_lines, 0)
  let a_rest = list.drop(a_lines, prefix)
  let b_rest = list.drop(b_lines, prefix)
  let suffix = common_prefix(list.reverse(a_rest), list.reverse(b_rest), 0)
  let context_before = int.min(prefix, 3)
  let start = prefix - context_before
  let a_changed = list.take(a_rest, list.length(a_rest) - suffix)
  let b_changed = list.take(b_rest, list.length(b_rest) - suffix)
  let context_after =
    list.drop(a_rest, list.length(a_rest) - suffix) |> list.take(3)
  let before = a_lines |> list.drop(start) |> list.take(context_before)

  let a_count =
    context_before + list.length(a_changed) + list.length(context_after)
  let b_count =
    context_before + list.length(b_changed) + list.length(context_after)
  let range = fn(count) {
    case count {
      0 -> int.to_string(start) <> ",0"
      _ -> int.to_string(start + 1) <> "," <> int.to_string(count)
    }
  }
  let body =
    list.flatten([
      list.map(before, fn(line) { " " <> line }),
      list.map(a_changed, fn(line) { "-" <> line }),
      list.map(b_changed, fn(line) { "+" <> line }),
      list.map(context_after, fn(line) { " " <> line }),
    ])
  string.join(
    [
      "--- " <> label_a,
      "+++ " <> label_b,
      "@@ -" <> range(a_count) <> " +" <> range(b_count) <> " @@",
      ..body
    ],
    "\n",
  )
  <> "\n"
}

fn lines(content: String) -> List(String) {
  case content {
    "" -> []
    _ ->
      case string.ends_with(content, "\n") {
        True -> string.split(string.drop_end(content, 1), "\n")
        False -> string.split(content, "\n")
      }
  }
}

fn common_prefix(a: List(String), b: List(String), count: Int) -> Int {
  case a, b {
    [x, ..a_rest], [y, ..b_rest] if x == y ->
      common_prefix(a_rest, b_rest, count + 1)
    _, _ -> count
  }
}

// =============================================================================
// Output
// =============================================================================

fn print_stat(changes: List(Change)) -> Nil {
  let width =
    changes
    |> list.map(fn(change) { string.length(change.path) })
    |> list.fold(0, int.max)
  list.each(changes, fn(change) {
    let #(added, removed) = count_lines(change.diff)
    let note = case change {
      Changed(..) ->
        "+" <> int.to_string(added) <> " -" <> int.to_string(removed)
      Missing(..) -> "missing from the app (+" <> int.to_string(added) <> ")"
    }
    io.println(" " <> string.pad_end(change.path, width, " ") <> " | " <> note)
  })
}

/// Added and removed lines of a unified diff.
fn count_lines(diff: String) -> #(Int, Int) {
  diff
  |> string.split("\n")
  |> list.fold(#(0, 0), fn(counts, line) {
    case line {
      "+++ " <> _ | "--- " <> _ -> counts
      "+" <> _ -> #(counts.0 + 1, counts.1)
      "-" <> _ -> #(counts.0, counts.1 + 1)
      _ -> counts
    }
  })
}

fn print_summary(
  changes: List(Change),
  only_in_app: List(String),
  generated: Int,
) -> Nil {
  let changed =
    list.filter_map(changes, fn(change) {
      case change {
        Changed(path, _) -> Ok(path)
        Missing(..) -> Error(Nil)
      }
    })
  let missing =
    list.filter_map(changes, fn(change) {
      case change {
        Missing(path, _) -> Ok(path)
        Changed(..) -> Error(Nil)
      }
    })
  io.println("")
  case changes {
    [] ->
      io.println(
        "No differences: the app's "
        <> int.to_string(generated)
        <> " generated files match what this refrakt_cli generates.",
      )
    _ -> {
      print_list("Differ from the templates", changed)
      print_list("Only in the templates (missing from the app)", missing)
    }
  }
  print_list("Only in the app (not generated; not compared)", only_in_app)
  case changes {
    [] -> Nil
    _ -> {
      io.println("")
      io.println(
        "Lines with + are what this refrakt_cli generates; lines with - are the app's.",
      )
    }
  }
}

fn print_list(title: String, paths: List(String)) -> Nil {
  case paths {
    [] -> Nil
    _ -> {
      io.println(title <> " (" <> int.to_string(list.length(paths)) <> "):")
      list.each(paths, fn(path) { io.println("  " <> path) })
    }
  }
}

/// Framework files first (router, config, entry point, layouts,
/// middleware, session, test support), then the rest by path.
fn compare_paths(app: String, a: String, b: String) -> order.Order {
  case int.compare(rank(app, a), rank(app, b)) {
    order.Eq -> string.compare(a, b)
    other -> other
  }
}

fn rank(app: String, path: String) -> Int {
  let src = "src/" <> app
  let web = src <> "/web/"
  let is = fn(file) { path == file }
  let under = fn(dir) { string.starts_with(path, dir) }
  let ranks = [
    is(src <> "/router.gleam"),
    is(src <> "/config.gleam") || is(src <> "/context.gleam"),
    is(src <> ".gleam"),
    under(web <> "layouts/"),
    under(web <> "middleware/"),
    is(web <> "session.gleam"),
    under("test/" <> app <> "/support/") || is("test/" <> app <> "_test.gleam"),
    is("gleam.toml")
      || is(web <> "error_handler.gleam")
      || under(web <> "components/")
      || is(src <> "/data/repo.gleam"),
  ]
  first_true(ranks, 0)
}

fn first_true(conditions: List(Bool), index: Int) -> Int {
  case conditions {
    [] -> index
    [True, ..] -> index
    [False, ..rest] -> first_true(rest, index + 1)
  }
}

// =============================================================================
// Inferring the generators of apps without a manifest
// =============================================================================

type Inferred {
  Inferred(module: String, args: List(String))
}

/// Infer the generators run in an app that has no manifest, from its
/// files:
///
/// - `gen resource`: a `data/migrations/NNN_create_<plural>.sql` with a
///   matching `web/<singular>_handler.gleam` and `domain/<singular>.gleam`.
///   Field names, `optional(...)`, `--belongs-to` (REFERENCES) and most
///   types come from the CREATE TABLE; the domain type tells Bool from
///   Int, the form view tells text (a textarea) from string, the tests
///   tell date and datetime from string on SQLite. No views means `--api`.
/// - `gen auth`: `create_users` with `web/auth_handler.gleam`
/// - `gen live`: `web/<name>_live_handler.gleam`
/// - `gen island`: `web/islands/<name>_embed.gleam`
/// - `gen page`: any other `web/<name>_handler.gleam`
///
/// They are ordered by where their routes appear in the router, which is
/// the order generators insert them in.
pub fn infer(app: String) -> List(List(String)) {
  let src = "src/" <> app
  let web = src <> "/web/"
  let migrations_dir = src <> "/data/migrations"
  let migrations =
    simplifile.read_directory(migrations_dir)
    |> result.unwrap([])
    |> list.sort(string.compare)

  let tables =
    list.filter_map(migrations, fn(file) {
      case string.split_once(file, "_create_") {
        Ok(#(number, rest)) ->
          case is_digits(number), string.ends_with(rest, ".sql") {
            True, True if rest != ".sql" ->
              Ok(#(string.drop_end(rest, 4), migrations_dir <> "/" <> file))
            _, _ -> Error(Nil)
          }
        Error(_) -> Error(Nil)
      }
    })

  let has_auth =
    exists(web <> "auth_handler.gleam")
    && list.any(tables, fn(table) { table.0 == "users" })

  let resources =
    list.filter(tables, fn(table) {
      let singular = gen.singularize(table.0)
      !{ table.0 == "users" && has_auth }
      && exists(web <> singular <> "_handler.gleam")
      && exists(src <> "/domain/" <> singular <> ".gleam")
    })
  let plurals =
    list.map(resources, fn(table) { #(gen.singularize(table.0), table.0) })

  let inferred_resources =
    list.map(resources, fn(table) {
      let singular = gen.singularize(table.0)
      Inferred(
        singular <> "_handler",
        infer_resource(app, table.0, table.1, plurals),
      )
    })
  let auth = case has_auth {
    True -> [Inferred("auth_handler", ["auth"])]
    False -> []
  }

  let handlers =
    simplifile.read_directory(web)
    |> result.unwrap([])
    |> list.filter_map(fn(file) {
      case string.ends_with(file, "_handler.gleam") {
        True -> Ok(string.drop_end(file, string.length("_handler.gleam")))
        False -> Error(Nil)
      }
    })
    |> list.sort(string.compare)
  let taken = ["home", "error", "auth", ..list.map(plurals, fn(p) { p.0 })]
  let pages_and_live =
    list.filter_map(handlers, fn(name) {
      case list.contains(taken, name), string.ends_with(name, "_live") {
        True, _ -> Error(Nil)
        False, True -> {
          let live = string.drop_end(name, string.length("_live"))
          Ok(Inferred(name <> "_handler", ["live", live]))
        }
        False, False -> Ok(Inferred(name <> "_handler", ["page", name]))
      }
    })

  let islands =
    simplifile.read_directory(web <> "islands")
    |> result.unwrap([])
    |> list.filter_map(fn(file) {
      case string.ends_with(file, "_embed.gleam") {
        True -> {
          let name = string.drop_end(file, string.length("_embed.gleam"))
          Ok(Inferred("", ["island", name]))
        }
        False -> Error(Nil)
      }
    })
    |> list.sort(fn(a, b) { string.compare(a.module, b.module) })

  let router =
    simplifile.read(src <> "/router.gleam")
    |> result.unwrap("")
    |> collapse_whitespace

  list.flatten([inferred_resources, auth, pages_and_live])
  |> list.index_map(fn(item, index) {
    #(route_position(router, item, index), item)
  })
  |> list.sort(fn(a, b) { int.compare(a.0, b.0) })
  |> list.map(fn(pair) {
    let #(_, item) = pair
    item.args
  })
  |> list.append(list.map(islands, fn(item) { item.args }))
}

/// Where the router first calls the generator's handler; items the router
/// does not mention keep their order after the others.
fn route_position(router: String, item: Inferred, index: Int) -> Int {
  case string.split_once(router, " " <> item.module <> ".") {
    Ok(#(before, _)) -> string.length(before)
    Error(_) -> string.length(router) + index
  }
}

fn infer_resource(
  app: String,
  plural: String,
  migration: String,
  plurals: List(#(String, String)),
) -> List(String) {
  let singular = gen.singularize(plural)
  let src = "src/" <> app
  let read_flat = fn(path) {
    simplifile.read(path) |> result.unwrap("") |> remove_whitespace
  }
  let views_path = src <> "/web/" <> singular <> "_views.gleam"
  let api = !exists(views_path)
  let views = read_flat(views_path)
  let domain = read_flat(src <> "/domain/" <> singular <> ".gleam")
  let tests =
    read_flat("test/" <> app <> "/web/" <> singular <> "_handler_test.gleam")

  let columns =
    simplifile.read(migration)
    |> result.unwrap("")
    |> table_columns

  let #(specs, parent) =
    list.fold(columns, #([], None), fn(acc, column) {
      let #(specs, parent) = acc
      let #(name, definition) = column
      case
        string.contains(definition, "REFERENCES "),
        string.ends_with(name, "_id")
      {
        True, True -> {
          let parent_singular = string.drop_end(name, 3)
          let parent_plural =
            list.key_find(plurals, parent_singular)
            |> result.unwrap(parent_singular <> "s")
          #(specs, Some(parent_plural))
        }
        _, _ -> {
          let base = column_type(name, definition, domain, views, tests)
          let spec = case string.contains(definition, "NOT NULL") {
            True -> name <> ":" <> base
            False -> name <> ":optional(" <> base <> ")"
          }
          #([spec, ..specs], parent)
        }
      }
    })

  list.flatten([
    ["resource", plural],
    list.reverse(specs),
    case api {
      True -> ["--api"]
      False -> []
    },
    case parent {
      Some(parent) -> ["--belongs-to", parent]
      None -> []
    },
  ])
}

/// The columns of the first CREATE TABLE, without id and the timestamps:
/// `#(name, rest of the definition)`.
fn table_columns(sql: String) -> List(#(String, String)) {
  let body = case string.split_once(sql, "(") {
    Ok(#(_, after)) -> after
    Error(_) -> ""
  }
  let body = case string.split_once(body, "\n);") {
    Ok(#(columns, _)) -> columns
    Error(_) -> body
  }
  body
  |> string.split("\n")
  |> list.filter_map(fn(line) {
    let line = line |> string.trim |> trim_comma
    case string.split_once(line, " ") {
      Ok(#(name, definition)) ->
        case name {
          "" | "id" | "inserted_at" | "updated_at" -> Error(Nil)
          _ -> Ok(#(name, string.uppercase(definition)))
        }
      Error(_) -> Error(Nil)
    }
  })
}

fn trim_comma(line: String) -> String {
  case string.ends_with(line, ",") {
    True -> string.drop_end(line, 1)
    False -> line
  }
}

fn column_type(
  name: String,
  definition: String,
  domain: String,
  views: String,
  tests: String,
) -> String {
  let starts = fn(prefix) { string.starts_with(definition, prefix) }
  let gleam_bool =
    string.contains(domain, name <> ":Bool")
    || string.contains(domain, name <> ":Option(Bool)")
  case Nil {
    _ if gleam_bool -> "bool"
    _ ->
      case starts("INTEGER"), starts("REAL") || starts("DOUBLE PRECISION") {
        True, _ -> "int"
        _, True -> "float"
        _, _ ->
          case starts("BOOLEAN"), starts("DATE"), starts("TIMESTAMPTZ") {
            True, _, _ -> "bool"
            _, True, _ -> "date"
            _, _, True -> "datetime"
            _, _, _ -> text_type(name, views, tests)
          }
      }
  }
}

/// string, text, date or datetime for a TEXT column.
fn text_type(name: String, views: String, tests: String) -> String {
  let sample = "#(\"" <> name <> "\",\"2026-01-01"
  case
    string.contains(views, "textarea([name(\"" <> name <> "\")]"),
    string.contains(tests, sample <> "T"),
    string.contains(tests, sample <> "\"")
  {
    True, _, _ -> "text"
    _, True, _ -> "datetime"
    _, _, True -> "date"
    _, _, _ -> "string"
  }
}

fn exists(path: String) -> Bool {
  simplifile.is_file(path) == Ok(True)
}

fn remove_whitespace(s: String) -> String {
  s
  |> string.replace(" ", "")
  |> string.replace("\n", "")
  |> string.replace("\t", "")
}

fn collapse_whitespace(s: String) -> String {
  s
  |> string.replace("\n", " ")
  |> string.replace("\t", " ")
}
