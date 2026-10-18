/// Tests for `refrakt diff` and the generator manifest.
///
/// Each test generates an app in a temp directory with the generators
/// (in-process), then compares it with what `refrakt diff` renders.
///
import gleam/string
import gleeunit/should
import refrakt_cli/diff
import refrakt_cli/gen
import refrakt_cli/manifest
import refrakt_cli/new
import refrakt_cli/types
import simplifile

// =============================================================================
// Helpers
// =============================================================================

/// Generate `diff_app` (SQLite, a resource with a --belongs-to child, an
/// --api resource, a page and auth) in a fresh temp directory and run `f`
/// inside it.
fn in_generated_app(name: String, f: fn() -> Nil) -> Nil {
  let dir = "/tmp/refrakt_test_" <> name
  let _ = simplifile.delete_all([dir])
  let assert Ok(_) = simplifile.create_directory_all(dir)
  new.run(dir <> "/diff_app", ["--db", "sqlite"])

  let assert Ok(cwd) = current_directory()
  let assert Ok(_) = set_cwd(dir <> "/diff_app")
  gen.resource("posts", ["title:string", "body:text", "published:bool"])
  gen.resource("comments", ["body:text", "--belongs-to", "posts"])
  gen.resource("memos", ["title:string", "starts_on:optional(date)", "--api"])
  gen.page("about")
  gen.auth()

  f()

  let assert Ok(_) = set_cwd(cwd)
  let _ = simplifile.delete_all([dir])
  Nil
}

fn edit(path: String, from: String, to: String) -> Nil {
  let assert Ok(content) = simplifile.read(path)
  string.contains(content, from) |> should.be_true
  let assert Ok(_) = simplifile.write(path, string.replace(content, from, to))
  Nil
}

// =============================================================================
// refrakt diff
// =============================================================================

pub fn pristine_app_has_no_differences_test() {
  use <- in_generated_app("diff_pristine")
  let assert Ok(report) = diff.check([])
  report.changed |> should.equal([])
  report.missing |> should.equal([])
  report.problems |> should.equal([])
  report.only_in_app |> should.equal([])
  { report.compared > 30 } |> should.be_true
  diff.run(["--stat"]) |> should.equal(0)
}

pub fn edited_files_are_reported_router_first_test() {
  use <- in_generated_app("diff_edited")
  edit("src/diff_app/web/post_views.gleam", "text(\"Posts\")", "text(\"All\")")
  edit(
    "src/diff_app/router.gleam",
    "[\"about\"], http.Get",
    "[\"about-us\"], http.Get -> about_handler.index(req, ctx)\n    [\"about\"], http.Get",
  )

  let assert Ok(report) = diff.check([])
  report.changed
  |> should.equal([
    "src/diff_app/router.gleam",
    "src/diff_app/web/post_views.gleam",
  ])
  report.missing |> should.equal([])
  diff.run([]) |> should.equal(1)

  // Limited to a path
  let assert Ok(report) = diff.check(["src/diff_app/web/"])
  report.changed |> should.equal(["src/diff_app/web/post_views.gleam"])
  let assert Ok(report) = diff.check(["./src/diff_app/domain"])
  report.changed |> should.equal([])
  diff.run(["src/diff_app/domain"]) |> should.equal(0)
}

pub fn deleted_and_hand_written_files_are_reported_test() {
  use <- in_generated_app("diff_deleted")
  let assert Ok(_) = simplifile.delete("src/diff_app/web/session.gleam")
  // A hand-written migration shifts the numbers of later ones; it is only
  // in the app and is not a difference
  gen.migration("create_tags")
  gen.resource("notes", ["body:text"])
  let assert Ok(_) =
    simplifile.write("src/diff_app/web/helpers.gleam", "pub fn x() { 1 }\n")

  let assert Ok(report) = diff.check([])
  report.changed |> should.equal([])
  report.missing |> should.equal(["src/diff_app/web/session.gleam"])
  report.only_in_app
  |> should.equal([
    "src/diff_app/data/migrations/005_create_tags.sql",
    "src/diff_app/web/helpers.gleam",
  ])
  diff.run([]) |> should.equal(1)
}

pub fn unknown_option_is_a_usage_error_test() {
  diff.run(["--nope"]) |> should.equal(2)
}

// =============================================================================
// The manifest
// =============================================================================

pub fn new_and_generators_record_the_manifest_test() {
  use <- in_generated_app("diff_manifest")
  // Running a generator again records nothing new
  gen.page("about")

  let assert Ok(recorded) = manifest.read(".")
  recorded.name |> should.equal("diff_app")
  recorded.db |> should.equal(types.Sqlite)
  recorded.gens
  |> should.equal([
    ["resource", "posts", "title:string", "body:text", "published:bool"],
    ["resource", "comments", "body:text", "--belongs-to", "posts"],
    ["resource", "memos", "title:string", "starts_on:optional(date)", "--api"],
    ["page", "about"],
    ["auth"],
  ])
}

pub fn apps_without_a_manifest_are_inferred_test() {
  use <- in_generated_app("diff_inferred")
  let assert Ok(recorded) = manifest.read(".")
  let assert Ok(_) = simplifile.delete_all([".refrakt"])

  // gen records nothing when the app has no manifest
  gen.page("contact")
  simplifile.is_file(manifest.path) |> should.equal(Ok(False))

  // SQLite stores dates as TEXT and an --api resource has no tests with
  // date samples, so that one field is inferred as a string
  diff.infer("diff_app")
  |> should.equal(
    list_replace(
      recorded.gens,
      ["resource", "memos", "title:string", "starts_on:optional(date)", "--api"],
      [
        "resource",
        "memos",
        "title:string",
        "starts_on:optional(string)",
        "--api",
      ],
    )
    |> append([["page", "contact"]]),
  )

  let assert Ok(report) = diff.check([])
  report.changed |> should.equal([])
  report.missing |> should.equal([])
}

fn list_replace(items: List(a), old: a, new: a) -> List(a) {
  case items {
    [] -> []
    [item, ..rest] if item == old -> [new, ..list_replace(rest, old, new)]
    [item, ..rest] -> [item, ..list_replace(rest, old, new)]
  }
}

fn append(a: List(a), b: List(a)) -> List(a) {
  case a {
    [] -> b
    [x, ..rest] -> [x, ..append(rest, b)]
  }
}

pub fn line_diff_fallback_is_a_unified_diff_test() {
  let old = "a\nb\nc\nd\ne\nf\ng\nh\n"
  let new = "a\nb\nc\nd\nE\nf\ng\nh\n"
  diff.line_diff("a/x", "b/x", old, new)
  |> should.equal(
    "--- a/x\n+++ b/x\n@@ -2,7 +2,7 @@\n b\n c\n d\n-e\n+E\n f\n g\n h\n",
  )
  diff.line_diff("/dev/null", "b/x", "", "one\ntwo\n")
  |> should.equal("--- /dev/null\n+++ b/x\n@@ -0,0 +1,2 @@\n+one\n+two\n")
}

@external(erlang, "refrakt_cli_test_ffi", "set_cwd")
fn set_cwd(path: String) -> Result(Nil, Nil)

@external(erlang, "refrakt_cli_test_ffi", "current_directory")
fn current_directory() -> Result(String, Nil)
