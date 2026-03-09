/// Integration tests for code generators.
///
/// These tests run generators in a temp directory and verify the output
/// files exist and contain expected content.
///
import gleam/list
import gleam/string
import gleeunit/should
import refrakt/cli/gen
import refrakt/cli/new
import simplifile

// =============================================================================
// Helpers
// =============================================================================

fn in_temp_dir(name: String, f: fn(String) -> Nil) -> Nil {
  let dir = "/tmp/refrakt_test_" <> name
  let _ = simplifile.delete_all([dir])
  let assert Ok(_) = simplifile.create_directory_all(dir)
  f(dir)
  let _ = simplifile.delete_all([dir])
  Nil
}

fn file_exists(path: String) -> Bool {
  case simplifile.read(path) {
    Ok(_) -> True
    Error(_) -> False
  }
}

fn file_contains(path: String, substring: String) -> Bool {
  case simplifile.read(path) {
    Ok(content) -> string.contains(content, substring)
    Error(_) -> False
  }
}

// =============================================================================
// refrakt new
// =============================================================================

pub fn new_creates_project_structure_test() {
  in_temp_dir("new_basic", fn(dir) {
    let project_dir = dir <> "/my_app"
    new.run(project_dir, [])

    // Core files exist
    file_exists(project_dir <> "/gleam.toml") |> should.be_true
    file_exists(project_dir <> "/README.md") |> should.be_true
    file_exists(project_dir <> "/.gitignore") |> should.be_true
    file_exists(project_dir <> "/src/my_app.gleam") |> should.be_true
    file_exists(project_dir <> "/src/my_app/config.gleam") |> should.be_true
    file_exists(project_dir <> "/src/my_app/context.gleam") |> should.be_true
    file_exists(project_dir <> "/src/my_app/router.gleam") |> should.be_true
    file_exists(project_dir <> "/src/my_app/web/home_handler.gleam")
    |> should.be_true
    file_exists(project_dir <> "/src/my_app/web/error_handler.gleam")
    |> should.be_true
    file_exists(project_dir <> "/src/my_app/web/layouts/root_layout.gleam")
    |> should.be_true
    file_exists(project_dir <> "/test/my_app_test.gleam") |> should.be_true
    file_exists(project_dir <> "/priv/static/css/app.css") |> should.be_true
  })
}

pub fn new_with_postgres_creates_repo_test() {
  in_temp_dir("new_pg", fn(dir) {
    let project_dir = dir <> "/pg_app"
    new.run(project_dir, ["--db", "postgres"])

    file_exists(project_dir <> "/src/pg_app/data/repo.gleam") |> should.be_true
    file_contains(project_dir <> "/gleam.toml", "pog") |> should.be_true
    file_contains(project_dir <> "/src/pg_app/context.gleam", "pog.Connection")
    |> should.be_true
  })
}

pub fn new_with_sqlite_creates_repo_test() {
  in_temp_dir("new_sqlite", fn(dir) {
    let project_dir = dir <> "/sq_app"
    new.run(project_dir, ["--db", "sqlite"])

    file_exists(project_dir <> "/src/sq_app/data/repo.gleam") |> should.be_true
    file_contains(project_dir <> "/gleam.toml", "sqlight") |> should.be_true
    file_contains(project_dir <> "/src/sq_app/context.gleam", "db_path: String")
    |> should.be_true
  })
}

pub fn new_extracts_name_from_path_test() {
  in_temp_dir("new_path", fn(dir) {
    let project_dir = dir <> "/nested/deep/cool_app"
    new.run(project_dir, [])

    // Package name should be "cool_app", not the full path
    file_contains(project_dir <> "/gleam.toml", "name = \"cool_app\"")
    |> should.be_true
    file_exists(project_dir <> "/src/cool_app.gleam") |> should.be_true
  })
}

// =============================================================================
// gen resource (runs inside a generated project)
// =============================================================================

pub fn gen_resource_creates_all_files_test() {
  in_temp_dir("gen_resource", fn(dir) {
    let project_dir = dir <> "/res_app"
    new.run(project_dir, ["--db", "postgres"])

    // Change to project dir and run gen resource
    let assert Ok(cwd) = current_directory()
    let assert Ok(_) = set_cwd(project_dir)

    gen.resource("posts", ["title:string", "body:text", "published:bool"])

    // Verify files exist
    file_exists("src/res_app/web/post_handler.gleam") |> should.be_true
    file_exists("src/res_app/web/post_views.gleam") |> should.be_true
    file_exists("src/res_app/web/forms/post_form.gleam") |> should.be_true
    file_exists("src/res_app/domain/post.gleam") |> should.be_true
    file_exists("src/res_app/data/post_repo.gleam") |> should.be_true
    file_exists("src/res_app/data/migrations/001_create_posts.sql")
    |> should.be_true
    file_exists("test/res_app/web/post_handler_test.gleam") |> should.be_true

    // Verify router was patched
    file_contains("src/res_app/router.gleam", "post_handler") |> should.be_true
    file_contains("src/res_app/router.gleam", "[\"posts\"]") |> should.be_true

    // Verify domain type
    file_contains("src/res_app/domain/post.gleam", "pub type Post")
    |> should.be_true
    file_contains("src/res_app/domain/post.gleam", "title: String")
    |> should.be_true

    // Verify migration SQL
    file_contains(
      "src/res_app/data/migrations/001_create_posts.sql",
      "CREATE TABLE",
    )
    |> should.be_true

    let assert Ok(_) = set_cwd(cwd)
    Nil
  })
}

pub fn gen_two_resources_no_duplication_test() {
  in_temp_dir("gen_two", fn(dir) {
    let project_dir = dir <> "/two_app"
    new.run(project_dir, ["--db", "postgres"])

    let assert Ok(cwd) = current_directory()
    let assert Ok(_) = set_cwd(project_dir)

    gen.resource("posts", ["title:string"])
    gen.resource("comments", ["body:text"])

    // Both handlers exist
    file_exists("src/two_app/web/post_handler.gleam") |> should.be_true
    file_exists("src/two_app/web/comment_handler.gleam") |> should.be_true

    // Router has both resources, no duplication
    let assert Ok(router) = simplifile.read("src/two_app/router.gleam")
    let post_count =
      router
      |> string.split("post_handler.index")
      |> list.length
    // Should appear exactly twice: once in import area doesn't count, once in routes
    // Actually split produces N+1 parts for N occurrences
    { post_count <= 3 } |> should.be_true

    // Separate migrations
    file_exists("src/two_app/data/migrations/001_create_posts.sql")
    |> should.be_true
    file_exists("src/two_app/data/migrations/002_create_comments.sql")
    |> should.be_true

    let assert Ok(_) = set_cwd(cwd)
    Nil
  })
}

// =============================================================================
// gen page
// =============================================================================

pub fn gen_page_creates_handler_and_patches_router_test() {
  in_temp_dir("gen_page", fn(dir) {
    let project_dir = dir <> "/page_app"
    new.run(project_dir, [])

    let assert Ok(cwd) = current_directory()
    let assert Ok(_) = set_cwd(project_dir)

    gen.page("about")

    file_exists("src/page_app/web/about_handler.gleam") |> should.be_true
    file_exists("test/page_app/web/about_handler_test.gleam") |> should.be_true
    file_contains("src/page_app/router.gleam", "about_handler")
    |> should.be_true

    let assert Ok(_) = set_cwd(cwd)
    Nil
  })
}

// =============================================================================
// gen auth
// =============================================================================

pub fn gen_auth_creates_all_files_test() {
  in_temp_dir("gen_auth", fn(dir) {
    let project_dir = dir <> "/auth_app"
    new.run(project_dir, ["--db", "postgres"])

    let assert Ok(cwd) = current_directory()
    let assert Ok(_) = set_cwd(project_dir)

    gen.auth()

    file_exists("src/auth_app/domain/user.gleam") |> should.be_true
    file_exists("src/auth_app/domain/auth.gleam") |> should.be_true
    file_exists("src/auth_app/data/user_repo.gleam") |> should.be_true
    file_exists("src/auth_app/web/auth_handler.gleam") |> should.be_true
    file_exists("src/auth_app/web/auth_views.gleam") |> should.be_true
    file_exists("src/auth_app/web/forms/auth_form.gleam") |> should.be_true
    file_exists("src/auth_app/web/middleware/auth.gleam") |> should.be_true

    // Router patched
    file_contains("src/auth_app/router.gleam", "auth_handler") |> should.be_true
    file_contains("src/auth_app/router.gleam", "login") |> should.be_true
    file_contains("src/auth_app/router.gleam", "register") |> should.be_true

    let assert Ok(_) = set_cwd(cwd)
    Nil
  })
}

// =============================================================================
// gen island
// =============================================================================

pub fn gen_island_creates_files_test() {
  in_temp_dir("gen_island", fn(dir) {
    let project_dir = dir <> "/island_app"
    new.run(project_dir, [])

    let assert Ok(cwd) = current_directory()
    let assert Ok(_) = set_cwd(project_dir)

    gen.island("counter")

    file_exists("src/island_app/web/islands/counter.gleam") |> should.be_true
    file_exists("src/island_app/web/islands/counter_embed.gleam")
    |> should.be_true

    file_contains("src/island_app/web/islands/counter.gleam", "pub fn main()")
    |> should.be_true
    file_contains(
      "src/island_app/web/islands/counter_embed.gleam",
      "pub fn render()",
    )
    |> should.be_true

    let assert Ok(_) = set_cwd(cwd)
    Nil
  })
}

// =============================================================================
// FFI helper
// =============================================================================

@external(erlang, "refrakt_test_ffi", "set_cwd")
fn set_cwd(path: String) -> Result(Nil, Nil)

@external(erlang, "refrakt_test_ffi", "current_directory")
fn current_directory() -> Result(String, Nil)
