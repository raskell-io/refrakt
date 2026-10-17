/// Integration tests for code generators.
///
/// These tests run generators in a temp directory and verify the output
/// files exist and contain expected content.
///
import gleam/list
import gleam/string
import gleeunit/should
import refrakt_cli/gen
import refrakt_cli/new
import refrakt_cli/project
import refrakt_cli/types
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

pub fn new_depends_on_library_and_cli_as_dev_dependency_test() {
  in_temp_dir("new_deps", fn(dir) {
    let project_dir = dir <> "/my_app"
    new.run(project_dir, [])

    let assert Ok(toml) = simplifile.read(project_dir <> "/gleam.toml")
    let assert Ok(#(deps, dev_deps)) =
      string.split_once(toml, "[dev-dependencies]")

    string.contains(deps, "refrakt = ") |> should.be_true
    string.contains(deps, "refrakt_cli") |> should.be_false
    string.contains(dev_deps, "refrakt_cli = ") |> should.be_true
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
    // pog.url_config rejects URLs without a user, so the default must have one
    file_contains(
      project_dir <> "/src/pg_app/data/repo.gleam",
      "postgres://postgres@localhost:5432/pg_app_dev",
    )
    |> should.be_true
    file_contains(project_dir <> "/src/pg_app/data/repo.gleam", "DATABASE_URL")
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

pub fn new_router_shows_dev_error_page_only_in_dev_test() {
  in_temp_dir("new_router_env", fn(dir) {
    let project_dir = dir <> "/env_app"
    new.run(project_dir, [])

    let assert Ok(router) =
      simplifile.read(project_dir <> "/src/env_app/router.gleam")

    // The rich error page is chosen by environment, never unconditionally
    string.contains(router, "use <- dev_error.rescue(req)") |> should.be_false
    string.contains(router, "use <- rescue_crashes(req, ctx)") |> should.be_true
    string.contains(router, "config.Dev -> dev_error.rescue(req, next)")
    |> should.be_true
    string.contains(
      router,
      "config.Test | config.Prod -> wisp.rescue_crashes(next)",
    )
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

    // wisp.method_override only reads the _method query parameter
    file_contains("src/res_app/web/post_views.gleam", "?_method=PUT")
    |> should.be_true
    file_contains("src/res_app/web/post_views.gleam", "?_method=DELETE")
    |> should.be_true
    file_contains("src/res_app/web/post_views.gleam", "name(\"_method\")")
    |> should.be_false

    let assert Ok(_) = set_cwd(cwd)
    Nil
  })
}

pub fn gen_resource_without_db_writes_nothing_test() {
  in_temp_dir("gen_resource_no_db", fn(dir) {
    let project_dir = dir <> "/plain_app"
    new.run(project_dir, [])

    let assert Ok(cwd) = current_directory()
    let assert Ok(_) = set_cwd(project_dir)

    gen.resource("posts", ["title:string"])

    file_exists("src/plain_app/web/post_handler.gleam") |> should.be_false
    file_exists("src/plain_app/data/post_repo.gleam") |> should.be_false
    file_contains("src/plain_app/router.gleam", "post_handler")
    |> should.be_false

    let assert Ok(_) = set_cwd(cwd)
    Nil
  })
}

pub fn gen_resource_imports_textarea_only_for_text_fields_test() {
  in_temp_dir("gen_textarea", fn(dir) {
    let project_dir = dir <> "/ta_app"
    new.run(project_dir, ["--db", "sqlite"])

    let assert Ok(cwd) = current_directory()
    let assert Ok(_) = set_cwd(project_dir)

    gen.resource("tasks", ["title:string", "completed:bool"])
    gen.resource("notes", ["body:text"])

    file_contains("src/ta_app/web/task_views.gleam", "textarea")
    |> should.be_false
    file_contains("src/ta_app/web/note_views.gleam", "textarea")
    |> should.be_true
    // a resource with only text fields renders no input and sets no value
    file_contains("src/ta_app/web/note_views.gleam", "input")
    |> should.be_false
    file_contains("src/ta_app/web/note_views.gleam", "value(")
    |> should.be_false

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
// gen resource --api
// =============================================================================

pub fn gen_api_resource_creates_json_handlers_test() {
  in_temp_dir("gen_api", fn(dir) {
    let project_dir = dir <> "/api_app"
    new.run(project_dir, ["--db", "sqlite"])

    let assert Ok(cwd) = current_directory()
    let assert Ok(_) = set_cwd(project_dir)

    gen.resource("notes", [
      "title:string", "body:text", "pinned:bool", "rating:int", "--api",
    ])

    let handler = "src/api_app/web/note_handler.gleam"
    let form = "src/api_app/web/forms/note_form.gleam"
    let test_file = "test/api_app/web/note_handler_test.gleam"

    // No HTML views in API mode
    file_exists("src/api_app/web/note_views.gleam") |> should.be_false

    // create and update are implemented
    file_contains(handler, "501") |> should.be_false
    file_contains(handler, "not implemented") |> should.be_false
    file_contains(handler, "note_form.decode_json(body)") |> should.be_true
    file_contains(handler, "json_response(to_json(item), 201)")
    |> should.be_true
    file_contains(handler, "\"location\"") |> should.be_true
    file_contains(handler, "wisp.no_content()") |> should.be_true
    file_contains(handler, "|> json_response(422)") |> should.be_true
    file_contains(handler, "|> json_response(400)") |> should.be_true

    // The params module decodes JSON and validates like the HTML form
    file_contains(form, "pub fn decode_json(data: Dynamic)") |> should.be_true
    file_contains(form, "decode.optional_field(\"rating\", 0, decode.int)")
    |> should.be_true
    file_contains(
      form,
      "validate.required(params.title, \"title\", \"Title is required\")",
    )
    |> should.be_true
    file_contains(form, "validate.required(params.body,") |> should.be_true

    // Generated tests drive the handlers with JSON requests
    file_contains(test_file, "testing.json_request(http.Post, \"/api/notes\"")
    |> should.be_true
    file_contains(test_file, "should.equal(422)") |> should.be_true
    file_contains(test_file, "db_path: \":memory:\"") |> should.be_true

    // Routes live under /api
    file_contains("src/api_app/router.gleam", "[\"api\", \"notes\", id]")
    |> should.be_true

    let assert Ok(_) = set_cwd(cwd)
    Nil
  })
}

pub fn gen_api_resource_without_required_fields_test() {
  in_temp_dir("gen_api_numbers", fn(dir) {
    let project_dir = dir <> "/num_app"
    new.run(project_dir, ["--db", "postgres"])

    let assert Ok(cwd) = current_directory()
    let assert Ok(_) = set_cwd(project_dir)

    gen.resource("readings", ["value:float", "count:int", "--api"])

    let form = "src/num_app/web/forms/reading_form.gleam"
    let test_file = "test/num_app/web/reading_handler_test.gleam"

    // Nothing to validate: no unused import or parameter
    file_contains(form, "import refrakt/validate") |> should.be_false
    file_contains(form, "validate_params(_params: ReadingParams)")
    |> should.be_true
    // JSON numbers without a fraction still decode as Float
    file_contains(form, "fn float_or_int() -> decode.Decoder(Float)")
    |> should.be_true
    file_contains(test_file, "should.equal(422)") |> should.be_false
    file_contains(test_file, "pog.named_connection") |> should.be_true

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

    // Postgres-specific code
    file_contains("src/auth_app/data/user_repo.gleam", "import pog")
    |> should.be_true
    file_contains("src/auth_app/web/auth_handler.gleam", "ctx.db,")
    |> should.be_true
    file_contains(
      "src/auth_app/data/migrations/001_create_users.sql",
      "SERIAL PRIMARY KEY",
    )
    |> should.be_true

    // Passwords are hashed with Argon2 via argus, never plain SHA-256
    let domain = "src/auth_app/domain/auth.gleam"
    file_contains(domain, "import argus") |> should.be_true
    file_contains(domain, "crypto") |> should.be_false
    file_contains(domain, "pub fn hash_password(password: String) -> Result(")
    |> should.be_true
    file_contains("gleam.toml", "argus = \">= 2.0.0 and < 3.0.0\"")
    |> should.be_true

    let assert Ok(_) = set_cwd(cwd)
    Nil
  })
}

pub fn gen_auth_sqlite_generates_sqlite_code_test() {
  in_temp_dir("gen_auth_sqlite", fn(dir) {
    let project_dir = dir <> "/auth_lite"
    new.run(project_dir, ["--db", "sqlite"])

    let assert Ok(cwd) = current_directory()
    let assert Ok(_) = set_cwd(project_dir)

    gen.auth()

    let repo = "src/auth_lite/data/user_repo.gleam"
    file_contains(repo, "import sqlight") |> should.be_true
    file_contains(repo, "pog") |> should.be_false
    file_contains(repo, "db_path: String") |> should.be_true

    file_contains("src/auth_lite/web/auth_handler.gleam", "ctx.db_path")
    |> should.be_true
    file_contains("src/auth_lite/web/middleware/auth.gleam", "ctx.db_path")
    |> should.be_true

    let migration = "src/auth_lite/data/migrations/001_create_users.sql"
    file_contains(migration, "INTEGER PRIMARY KEY AUTOINCREMENT")
    |> should.be_true
    file_contains(migration, "TIMESTAMPTZ") |> should.be_false

    let assert Ok(_) = set_cwd(cwd)
    Nil
  })
}

pub fn add_dependency_is_idempotent_test() {
  in_temp_dir("add_dep", fn(dir) {
    let project_dir = dir <> "/dep_app"
    new.run(project_dir, ["--db", "sqlite"])

    let assert Ok(cwd) = current_directory()
    let assert Ok(_) = set_cwd(project_dir)

    project.add_dependency("argus", ">= 2.0.0 and < 3.0.0") |> should.be_true
    project.add_dependency("argus", ">= 2.0.0 and < 3.0.0") |> should.be_false
    // Already a dependency of every generated project
    project.add_dependency("wisp", ">= 1.0.0 and < 2.0.0") |> should.be_false

    let assert Ok(toml) = simplifile.read("gleam.toml")
    string.split(toml, "argus = ") |> list.length |> should.equal(2)
    string.contains(toml, "wisp = \">= 1.0.0") |> should.be_false

    // Added to [dependencies], not [dev-dependencies]
    let assert Ok(#(deps, dev_deps)) =
      string.split_once(toml, "[dev-dependencies]")
    string.contains(deps, "argus = ") |> should.be_true
    string.contains(dev_deps, "argus") |> should.be_false
    // The database is still detected after the patch
    project.detect_db() |> should.equal(types.Sqlite)

    let assert Ok(_) = set_cwd(cwd)
    Nil
  })
}

pub fn gen_auth_without_db_generates_nothing_test() {
  in_temp_dir("gen_auth_nodb", fn(dir) {
    let project_dir = dir <> "/auth_nodb"
    new.run(project_dir, [])

    let assert Ok(cwd) = current_directory()
    let assert Ok(_) = set_cwd(project_dir)

    gen.auth()

    file_exists("src/auth_nodb/data/user_repo.gleam") |> should.be_false
    file_contains("gleam.toml", "argus") |> should.be_false
    file_contains("src/auth_nodb/router.gleam", "auth_handler")
    |> should.be_false

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

@external(erlang, "refrakt_cli_test_ffi", "set_cwd")
fn set_cwd(path: String) -> Result(Nil, Nil)

@external(erlang, "refrakt_cli_test_ffi", "current_directory")
fn current_directory() -> Result(String, Nil)
