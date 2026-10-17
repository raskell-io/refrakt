/// Tests for field specs, optional(T) fields (#35) and --belongs-to
/// relations (#23).
///
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should
import refrakt_cli/gen
import refrakt_cli/new
import simplifile

// =============================================================================
// Field spec parsing
// =============================================================================

pub fn parse_field_plain_type_test() {
  gen.parse_field("title:string")
  |> should.equal(Ok(#("title", "string")))
}

pub fn parse_field_optional_type_test() {
  gen.parse_field("price:optional(float)")
  |> should.equal(Ok(#("price", "optional(float)")))
}

pub fn parse_field_optional_is_normalized_test() {
  gen.parse_field("stock:Optional( Int )")
  |> should.equal(Ok(#("stock", "optional(int)")))
}

pub fn parse_field_every_optional_type_test() {
  ["string", "text", "int", "float", "bool", "date", "datetime"]
  |> list.each(fn(t) {
    gen.parse_field("f:optional(" <> t <> ")")
    |> should.equal(Ok(#("f", "optional(" <> t <> ")")))
  })
}

pub fn parse_field_unknown_type_is_an_error_test() {
  let assert Error(message) = gen.parse_field("title:strin")
  string.contains(message, "Unknown type `strin` for field `title`")
  |> should.be_true
  string.contains(message, "optional(<type>)") |> should.be_true
}

pub fn parse_field_unknown_optional_type_is_an_error_test() {
  gen.parse_field("price:optional(money)") |> should.be_error
  gen.parse_field("price:optional(optional(int))") |> should.be_error
  gen.parse_field("price:optional(float") |> should.be_error
  gen.parse_field("price:optional()") |> should.be_error
}

pub fn parse_field_needs_a_type_test() {
  let assert Error(message) = gen.parse_field("title")
  string.contains(message, "expected name:type") |> should.be_true
}

pub fn parse_field_checks_the_name_test() {
  gen.parse_field("Title:string") |> should.be_error
  gen.parse_field("1st:string") |> should.be_error
  gen.parse_field(":string") |> should.be_error
  gen.parse_field("id:int") |> should.be_error
  gen.parse_field("first_name:string") |> should.be_ok
}

pub fn parse_fields_rejects_duplicates_test() {
  let assert Error(message) = gen.parse_fields(["title:string", "title:text"])
  string.contains(message, "`title`") |> should.be_true
}

pub fn optional_type_helpers_test() {
  gen.is_optional("optional(int)") |> should.be_true
  gen.is_optional("int") |> should.be_false
  gen.base_type("optional(int)") |> should.equal("int")
  gen.base_type("text") |> should.equal("text")
  gen.to_gleam_type("optional(float)") |> should.equal("Option(Float)")
  gen.to_gleam_type("optional(date)") |> should.equal("Option(String)")
}

pub fn first_string_field_test() {
  gen.first_string_field(
    "pub type Post {\n  Post(id: Int, title: String, published: Bool)\n}\n",
  )
  |> should.equal(Some("title"))
  gen.first_string_field(
    "pub type Post {\n  Post(\n    id: Int,\n    views: Int,\n    body: String,\n  )\n}\n",
  )
  |> should.equal(Some("body"))
  gen.first_string_field(
    "pub type Tag {\n  Tag(id: Int, name: Option(String), name2: String)\n}\n",
  )
  |> should.equal(Some("name2"))
  gen.first_string_field("pub type Vote {\n  Vote(id: Int, up: Bool)\n}\n")
  |> should.equal(None)
}

// =============================================================================
// gen resource with optional(T) fields
// =============================================================================

pub fn gen_resource_with_optional_fields_sqlite_test() {
  in_project("opt_sqlite", "sqlite", fn(app) {
    gen.resource("products", [
      "name:string", "price:optional(float)", "stock:optional(int)",
      "note:optional(text)", "featured:optional(bool)",
      "released:optional(date)",
    ])

    let domain = "src/" <> app <> "/domain/product.gleam"
    file_contains(domain, "import gleam/option.{type Option}")
    |> should.be_true
    file_contains(domain, "price: Option(Float)") |> should.be_true
    file_contains(domain, "featured: Option(Bool)") |> should.be_true
    file_contains(domain, "name: String") |> should.be_true

    // Nullable columns: no NOT NULL
    let migration = "src/" <> app <> "/data/migrations/001_create_products.sql"
    file_contains(migration, "name TEXT NOT NULL,") |> should.be_true
    file_contains(migration, "price REAL,") |> should.be_true
    file_contains(migration, "stock INTEGER,") |> should.be_true
    file_contains(migration, "featured INTEGER,") |> should.be_true

    let repo = "src/" <> app <> "/data/product_repo.gleam"
    file_contains(repo, "sqlight.nullable(sqlight.float, params.price)")
    |> should.be_true
    file_contains(repo, "decode.optional(decode.float)") |> should.be_true
    file_contains(repo, "decode.optional(sqlight.decode_bool())")
    |> should.be_true

    // Blank is None; a number that does not parse is a validation error
    let form = "src/" <> app <> "/web/forms/product_form.gleam"
    file_contains(form, "price: optional(price, parse_float)")
    |> should.be_true
    file_contains(
      form,
      "|> must_parse(stock, int.parse, \"stock\", \"Stock must be a whole number\")",
    )
    |> should.be_true
    file_contains(form, "validate.required(price") |> should.be_false

    // The optional bool is a blank/yes/no select; None shows as a dash
    let views = "src/" <> app <> "/web/product_views.gleam"
    file_contains(views, "html.select([name(\"featured\")]") |> should.be_true
    file_contains(views, "option.unwrap(values.note, \"\")") |> should.be_true
    file_contains(views, "option.unwrap(\"—\")") |> should.be_true
    file_contains(views, "step(\"any\")") |> should.be_true
  })
}

pub fn gen_resource_with_optional_fields_postgres_test() {
  in_project("opt_pg", "postgres", fn(app) {
    gen.resource("events", [
      "title:string", "starts_on:optional(date)", "capacity:optional(int)",
    ])

    let repo = "src/" <> app <> "/data/event_repo.gleam"
    file_contains(repo, "pog.nullable(pog.int, params.capacity)")
    |> should.be_true
    file_contains(repo, "decode.optional(decode.int)") |> should.be_true
    // Dates are read and written as text
    file_contains(repo, "starts_on::text AS starts_on") |> should.be_true
    file_contains(repo, "$2::text::date") |> should.be_true

    let migration = "src/" <> app <> "/data/migrations/001_create_events.sql"
    file_contains(migration, "starts_on DATE,") |> should.be_true
    file_contains(migration, "title TEXT NOT NULL,") |> should.be_true
  })
}

pub fn gen_api_resource_with_optional_fields_test() {
  in_project("opt_api", "sqlite", fn(app) {
    gen.resource("gadgets", [
      "label:string", "weight:optional(float)", "count:optional(int)", "--api",
    ])

    let form = "src/" <> app <> "/web/forms/gadget_form.gleam"
    file_contains(form, "import gleam/option.{type Option, None}")
    |> should.be_true
    file_contains(form, "decode.optional(decode.int)") |> should.be_true
    file_contains(form, "decode.optional(float_or_int())") |> should.be_true

    let handler = "src/" <> app <> "/web/gadget_handler.gleam"
    file_contains(handler, "json.nullable(item.count, json.int)")
    |> should.be_true
  })
}

pub fn gen_resource_with_unknown_type_writes_nothing_test() {
  in_project("opt_bad", "sqlite", fn(app) {
    gen.resource("products", ["name:string", "price:money"])

    file_exists("src/" <> app <> "/web/product_handler.gleam")
    |> should.be_false
    file_exists("src/" <> app <> "/domain/product.gleam") |> should.be_false
    file_contains("src/" <> app <> "/router.gleam", "product_handler")
    |> should.be_false
  })
}

pub fn gen_resource_with_unknown_option_writes_nothing_test() {
  in_project("opt_flag", "sqlite", fn(app) {
    gen.resource("products", ["name:string", "--json"])

    file_exists("src/" <> app <> "/web/product_handler.gleam")
    |> should.be_false
  })
}

// =============================================================================
// gen resource --belongs-to
// =============================================================================

pub fn gen_belongs_to_missing_parent_writes_nothing_test() {
  in_project("rel_missing", "sqlite", fn(app) {
    gen.resource("comments", ["body:text", "--belongs-to", "posts"])

    file_exists("src/" <> app <> "/web/comment_handler.gleam")
    |> should.be_false
    file_exists("src/" <> app <> "/domain/comment.gleam") |> should.be_false
    file_contains("src/" <> app <> "/router.gleam", "comment_handler")
    |> should.be_false
  })
}

pub fn gen_belongs_to_needs_a_parent_name_test() {
  in_project("rel_flag", "sqlite", fn(app) {
    gen.resource("posts", ["title:string"])
    gen.resource("comments", ["body:text", "--belongs-to"])

    file_exists("src/" <> app <> "/web/comment_handler.gleam")
    |> should.be_false
  })
}

pub fn gen_belongs_to_sqlite_test() {
  in_project("rel_sqlite", "sqlite", fn(app) {
    gen.resource("posts", ["title:string", "body:text"])
    gen.resource("comments", ["body:text", "--belongs-to", "posts"])

    // The flag's value is not mistaken for a field
    let domain = "src/" <> app <> "/domain/comment.gleam"
    file_contains(domain, "post_id: Int") |> should.be_true
    file_contains(domain, "posts") |> should.be_false

    let migration = "src/" <> app <> "/data/migrations/002_create_comments.sql"
    file_contains(
      migration,
      "post_id INTEGER NOT NULL REFERENCES posts(id) ON DELETE CASCADE",
    )
    |> should.be_true
    file_contains(
      migration,
      "CREATE INDEX comments_post_id_index ON comments (post_id);",
    )
    |> should.be_true

    let repo = "src/" <> app <> "/data/comment_repo.gleam"
    file_contains(
      repo,
      "pub fn list_for_post(db_path: String, post_id: Int) -> List(Comment)",
    )
    |> should.be_true
    file_contains(repo, "pub fn post_options(db_path: String)")
    |> should.be_true
    file_contains(repo, "SELECT id, title FROM posts ORDER BY title, id")
    |> should.be_true

    // The parent's repo turns on SQLite foreign keys for ON DELETE CASCADE
    file_contains(
      "src/" <> app <> "/data/post_repo.gleam",
      "PRAGMA foreign_keys = ON",
    )
    |> should.be_true

    // The form offers the posts; the handler checks the post exists
    let views = "src/" <> app <> "/web/comment_views.gleam"
    file_contains(views, "post_options: List(#(Int, String))")
    |> should.be_true
    file_contains(views, "html.select([name(\"post_id\")]") |> should.be_true
    file_contains(views, "href(\"/posts/\" <> int.to_string(item.post_id))")
    |> should.be_true
    let handler = "src/" <> app <> "/web/comment_handler.gleam"
    file_contains(handler, "fn check_post(") |> should.be_true
    file_contains(handler, "\"Post does not exist\"") |> should.be_true
    file_contains(handler, "result.try(check_post(ctx, _))") |> should.be_true
    file_contains(handler, "list.key_find(wisp.get_query(req), \"post_id\")")
    |> should.be_true

    // The post's show page lists its comments
    file_exists("src/" <> app <> "/web/components/comment_list.gleam")
    |> should.be_true
    let post_handler = "src/" <> app <> "/web/post_handler.gleam"
    file_contains(post_handler, "element.fragment([") |> should.be_true
    file_contains(
      post_handler,
      "comment_repo.list_for_post(ctx.db_path, item.id)",
    )
    |> should.be_true
    file_contains(post_handler, "import lustre/element\n") |> should.be_true
    file_contains(
      post_handler,
      "import " <> app <> "/web/components/comment_list",
    )
    |> should.be_true

    // Flat routes
    file_contains("src/" <> app <> "/router.gleam", "[\"comments\", id]")
    |> should.be_true
  })
}

pub fn gen_two_children_patch_one_fragment_test() {
  in_project("rel_two", "sqlite", fn(app) {
    gen.resource("posts", ["title:string"])
    gen.resource("comments", ["body:text", "--belongs-to", "posts"])
    gen.resource("likes", ["note:string", "--belongs-to=posts"])

    let assert Ok(content) =
      simplifile.read("src/" <> app <> "/web/post_handler.gleam")
    count(content, "element.fragment([") |> should.equal(1)
    string.contains(content, "comment_list.render(") |> should.be_true
    string.contains(content, "like_list.render(") |> should.be_true
  })
}

pub fn gen_belongs_to_api_parent_prints_instructions_test() {
  in_project("rel_api_parent", "sqlite", fn(app) {
    gen.resource("posts", ["title:string", "--api"])
    gen.resource("comments", ["body:text", "--belongs-to", "posts"])

    // The component is generated, the JSON handler is left alone
    file_exists("src/" <> app <> "/web/components/comment_list.gleam")
    |> should.be_true
    file_contains("src/" <> app <> "/web/post_handler.gleam", "comment_list")
    |> should.be_false
  })
}

pub fn gen_belongs_to_api_child_test() {
  in_project("rel_api", "postgres", fn(app) {
    gen.resource("posts", ["title:string"])
    gen.resource("votes", ["up:bool", "--belongs-to", "posts", "--api"])

    let handler = "src/" <> app <> "/web/vote_handler.gleam"
    file_contains(handler, "vote_form.InvalidParams([") |> should.be_true
    file_contains(handler, "post_repo.get(ctx.db, params.post_id)")
    |> should.be_true

    let repo = "src/" <> app <> "/data/vote_repo.gleam"
    file_contains(
      repo,
      "pub fn list_for_post(db: pog.Connection, post_id: Int)",
    )
    |> should.be_true
    // No form, so no select options
    file_contains(repo, "post_options") |> should.be_false
    file_exists("src/" <> app <> "/web/components/vote_list.gleam")
    |> should.be_false

    file_contains(
      "src/" <> app <> "/data/migrations/002_create_votes.sql",
      "post_id INTEGER NOT NULL REFERENCES posts(id) ON DELETE CASCADE",
    )
    |> should.be_true
  })
}

// =============================================================================
// Helpers
// =============================================================================

/// Run `f` inside a new project `<name>_app` with the given database.
fn in_project(name: String, db: String, f: fn(String) -> Nil) -> Nil {
  let dir = "/tmp/refrakt_test_" <> name
  let app = name <> "_app"
  let _ = simplifile.delete_all([dir])
  let assert Ok(_) = simplifile.create_directory_all(dir)
  new.run(dir <> "/" <> app, ["--db", db])

  let assert Ok(cwd) = current_directory()
  let assert Ok(_) = set_cwd(dir <> "/" <> app)
  f(app)
  let assert Ok(_) = set_cwd(cwd)

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

fn count(haystack: String, needle: String) -> Int {
  list.length(string.split(haystack, needle)) - 1
}

@external(erlang, "refrakt_cli_test_ffi", "set_cwd")
fn set_cwd(path: String) -> Result(Nil, Nil)

@external(erlang, "refrakt_cli_test_ffi", "current_directory")
fn current_directory() -> Result(String, Nil)
