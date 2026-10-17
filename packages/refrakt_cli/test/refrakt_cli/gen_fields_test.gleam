/// Tests for field specs and optional(T) fields (#35).
///
import gleam/list
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

@external(erlang, "refrakt_cli_test_ffi", "set_cwd")
fn set_cwd(path: String) -> Result(Nil, Nil)

@external(erlang, "refrakt_cli_test_ffi", "current_directory")
fn current_directory() -> Result(String, Nil)
