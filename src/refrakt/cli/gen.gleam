/// Code generators: page, resource, migration, auth.
///
import gleam/int
import gleam/io
import gleam/list
import gleam/string
import refrakt/cli/format
import refrakt/cli/project
import refrakt/cli/templates
import refrakt/cli/types.{type DbChoice, NoDb, Postgres, Sqlite}
import simplifile

// =============================================================================
// gen page
// =============================================================================

pub fn page(name: String) {
  let app = project.app_name()

  let handler_path = "src/" <> app <> "/web/" <> name <> "_handler.gleam"
  let test_path = "test/" <> app <> "/web/" <> name <> "_handler_test.gleam"

  // Create handler
  let handler_content = "import " <> app <> "/context.{type Context}
import " <> app <> "/web/layouts/root_layout
import lustre/attribute.{class}
import lustre/element.{text}
import lustre/element/html.{h1, section}
import wisp.{type Request, type Response}

pub fn index(_req: Request, _ctx: Context) -> Response {
  section([class(\"" <> name <> "\")], [
    h1([], [text(\"" <> capitalize(name) <> "\")]),
  ])
  |> root_layout.wrap(\"" <> capitalize(name) <> "\")
  |> wisp.html_response(200)
}
"

  let test_content =
    "import gleeunit/should

pub fn placeholder_test() {
  1 + 1
  |> should.equal(2)
}
"

  let assert Ok(_) = simplifile.write(handler_path, handler_content)
  ensure_dir_for(test_path)
  let assert Ok(_) = simplifile.write(test_path, test_content)

  // Patch router and format
  let _ = patch_router_page(app, name)
  let router_path = "src/" <> app <> "/router.gleam"
  format.format_files([handler_path, test_path, router_path])

  io.println("")
  io.println("Created:")
  io.println("  " <> handler_path)
  io.println("  " <> test_path)
  io.println("")
  io.println("Updated:")
  io.println("  " <> router_path)
}

// =============================================================================
// gen resource
// =============================================================================

pub fn resource(name: String, raw_fields: List(String)) {
  let app = project.app_name()
  let db = project.detect_db()
  let singular = singularize(name)
  let type_name = capitalize(singular)
  let fields = parse_fields(raw_fields)

  // Paths
  let handler_path = "src/" <> app <> "/web/" <> singular <> "_handler.gleam"
  let views_path = "src/" <> app <> "/web/" <> singular <> "_views.gleam"
  let form_path = "src/" <> app <> "/web/forms/" <> singular <> "_form.gleam"
  let domain_path = "src/" <> app <> "/domain/" <> singular <> ".gleam"
  let repo_path = "src/" <> app <> "/data/" <> singular <> "_repo.gleam"
  let migration_path =
    "src/"
    <> app
    <> "/data/migrations/"
    <> next_migration_number(app)
    <> "_create_"
    <> name
    <> ".sql"
  let test_path = "test/" <> app <> "/web/" <> singular <> "_handler_test.gleam"

  // Ensure directories
  list.each(
    [
      "src/" <> app <> "/web/forms",
      "src/" <> app <> "/domain",
      "src/" <> app <> "/data",
      "src/" <> app <> "/data/migrations",
      "test/" <> app <> "/web",
    ],
    fn(dir) {
      let _ = simplifile.create_directory_all(dir)
    },
  )

  // Generate files
  let first_field = case fields {
    [#(name, _), ..] -> name
    [] -> "id"
  }

  let gleam_fields =
    list.map(fields, fn(f) {
      let #(field_name, field_type) = f
      #(field_name, to_gleam_type(field_type))
    })

  let assert Ok(_) =
    simplifile.write(
      handler_path,
      templates.resource_handler(
        app,
        name,
        singular,
        type_name,
        first_field,
        db,
      ),
    )

  let assert Ok(_) =
    simplifile.write(
      views_path,
      resource_views(app, name, singular, type_name, fields),
    )

  let assert Ok(_) =
    simplifile.write(form_path, resource_form(app, singular, type_name, fields))

  let assert Ok(_) =
    simplifile.write(
      domain_path,
      templates.resource_domain_type(type_name, gleam_fields),
    )

  let assert Ok(_) =
    simplifile.write(
      repo_path,
      resource_repo(app, singular, type_name, fields, db),
    )

  let assert Ok(_) =
    simplifile.write(migration_path, resource_migration(name, fields, db))

  let assert Ok(_) =
    simplifile.write(test_path, resource_test(app, singular, type_name, fields))

  // Patch router and format
  let _ = patch_router_resource(app, name, singular)
  let router_path = "src/" <> app <> "/router.gleam"
  format.format_files([
    handler_path, views_path, form_path, domain_path, repo_path, test_path,
    router_path,
  ])

  io.println("")
  io.println("Created:")
  io.println("  " <> handler_path)
  io.println("  " <> views_path)
  io.println("  " <> form_path)
  io.println("  " <> domain_path)
  io.println("  " <> repo_path)
  io.println("  " <> migration_path)
  io.println("  " <> test_path)
  io.println("")
  io.println("Updated:")
  io.println("  src/" <> app <> "/router.gleam")
}

// =============================================================================
// gen migration
// =============================================================================

pub fn migration(name: String) {
  let app = project.app_name()
  let dir = "src/" <> app <> "/data/migrations"
  let _ = simplifile.create_directory_all(dir)

  let number = next_migration_number(app)
  let filename = number <> "_" <> name <> ".sql"
  let path = dir <> "/" <> filename

  let content = "-- Migration: " <> name <> "\n-- Created: " <> number <> "\n\n"

  let assert Ok(_) = simplifile.write(path, content)

  io.println("")
  io.println("Created:")
  io.println("  " <> path)
}

// =============================================================================
// gen auth
// =============================================================================

pub fn auth() {
  let app = project.app_name()

  // Ensure directories
  list.each(
    [
      "src/" <> app <> "/web/forms",
      "src/" <> app <> "/web/middleware",
      "src/" <> app <> "/domain",
      "src/" <> app <> "/data",
      "src/" <> app <> "/data/migrations",
      "test/" <> app <> "/web",
    ],
    fn(dir) {
      let _ = simplifile.create_directory_all(dir)
    },
  )

  let files = [
    #("src/" <> app <> "/domain/user.gleam", auth_user_type()),
    #("src/" <> app <> "/domain/auth.gleam", auth_domain(app)),
    #("src/" <> app <> "/data/user_repo.gleam", auth_user_repo(app)),
    #(
      "src/"
        <> app
        <> "/data/migrations/"
        <> next_migration_number(app)
        <> "_create_users.sql",
      auth_migration(),
    ),
    #("src/" <> app <> "/web/forms/auth_form.gleam", auth_form(app)),
    #("src/" <> app <> "/web/auth_handler.gleam", auth_handler(app)),
    #("src/" <> app <> "/web/auth_views.gleam", auth_views(app)),
    #("src/" <> app <> "/web/middleware/auth.gleam", auth_middleware(app)),
    #("test/" <> app <> "/web/auth_handler_test.gleam", auth_test(app)),
  ]

  list.each(files, fn(file) {
    let #(path, content) = file
    let assert Ok(_) = simplifile.write(path, content)
  })

  // Patch router and format
  let _ = patch_router_auth(app)
  let router_path = "src/" <> app <> "/router.gleam"
  let gleam_paths =
    list.filter_map(files, fn(file) {
      case string.ends_with(file.0, ".gleam") {
        True -> Ok(file.0)
        False -> Error(Nil)
      }
    })
  format.format_files([router_path, ..gleam_paths])

  io.println("")
  io.println("Created:")
  list.each(files, fn(file) { io.println("  " <> file.0) })
  io.println("")
  io.println("Updated:")
  io.println("  src/" <> app <> "/router.gleam")
  io.println("")
  io.println("Note: You need a password hashing library. Add one with:")
  io.println("  gleam add beecrypt")
}

// =============================================================================
// gen island
// =============================================================================

pub fn island(name: String) {
  let app = project.app_name()

  let island_dir = "src/" <> app <> "/web/islands"
  let _ = simplifile.create_directory_all(island_dir)

  let island_path = island_dir <> "/" <> name <> ".gleam"
  let embed_path = island_dir <> "/" <> name <> "_embed.gleam"

  let assert Ok(_) = simplifile.write(island_path, island_module(name))
  let assert Ok(_) = simplifile.write(embed_path, island_embed(app, name))
  format.format_files([island_path, embed_path])

  io.println("")
  io.println("Created:")
  io.println("  " <> island_path)
  io.println("  " <> embed_path)
  io.println("")
  io.println("Usage in a view:")
  io.println("  import " <> app <> "/web/islands/" <> name <> "_embed")
  io.println("  " <> name <> "_embed.render()")
  io.println("  " <> name <> "_embed.script_tag()")
  io.println("")
  io.println("Build the island JS:")
  io.println("  gleam build --target javascript")
}

fn island_module(name: String) -> String {
  "/// Interactive island: " <> name <> "
///
/// This is a Lustre client-side app. Compile to JavaScript with:
///   gleam build --target javascript
///
import gleam/int
import lustre
import lustre/element.{text}
import lustre/element/html.{button, div, p}
import lustre/event

pub type Model {
  Model(count: Int)
}

pub type Msg {
  Increment
  Decrement
}

pub fn init(_flags: Nil) -> Model {
  Model(count: 0)
}

pub fn update(model: Model, msg: Msg) -> Model {
  case msg {
    Increment -> Model(count: model.count + 1)
    Decrement -> Model(count: model.count - 1)
  }
}

pub fn view(model: Model) -> element.Element(Msg) {
  div([], [
    button([event.on_click(Decrement)], [text(\"-\")]),
    p([], [text(int.to_string(model.count))]),
    button([event.on_click(Increment)], [text(\"+\")]),
  ])
}

pub fn main() {
  let app = lustre.simple(init, update, view)
  let assert Ok(_) = lustre.start(app, \"#" <> name <> "\", Nil)
}
"
}

fn island_embed(_app: String, name: String) -> String {
  "/// Server-side helper to embed the " <> name <> " island in a view.
///
import lustre/attribute.{id, src}
import lustre/element.{type Element, text}
import lustre/element/html.{div, script}

/// Render the mount point for the island.
pub fn render() -> Element(Nil) {
  div([id(\"" <> name <> "\")], [text(\"Loading...\")])
}

/// Render the script tag that loads the island JS.
pub fn script_tag() -> Element(Nil) {
  script([src(\"/static/js/islands/" <> name <> ".js\")], \"\")
}
"
}

// =============================================================================
// Resource template helpers
// =============================================================================

fn resource_views(
  app_name: String,
  resource_plural: String,
  resource_singular: String,
  type_name: String,
  fields: List(#(String, String)),
) -> String {
  let first_field = case fields {
    [#(name, _), ..] -> name
    [] -> "id"
  }

  let form_field_elements =
    fields
    |> list.map(fn(f) {
      let #(fname, ftype) = f
      let label_text = capitalize(fname)
      case ftype {
        "bool" -> "      div([class(\"field\")], [
        label([], [
          input([type_(\"checkbox\"), name(\"" <> fname <> "\"), attribute.checked(values." <> fname <> ")]),
          text(\" " <> label_text <> "\"),
        ]),
      ]),"
        "text" -> "      div([class(\"field\")], [
        label([], [text(\"" <> label_text <> "\")]),
        textarea([name(\"" <> fname <> "\")], values." <> fname <> "),
        field_error(errors, \"" <> fname <> "\"),
      ]),"
        "int" -> "      div([class(\"field\")], [
        label([], [text(\"" <> label_text <> "\")]),
        input([type_(\"number\"), name(\"" <> fname <> "\"), value(int.to_string(values." <> fname <> "))]),
        field_error(errors, \"" <> fname <> "\"),
      ]),"
        "float" -> "      div([class(\"field\")], [
        label([], [text(\"" <> label_text <> "\")]),
        input([type_(\"number\"), name(\"" <> fname <> "\"), value(float.to_string(values." <> fname <> "))]),
        field_error(errors, \"" <> fname <> "\"),
      ]),"
        _ -> "      div([class(\"field\")], [
        label([], [text(\"" <> label_text <> "\")]),
        input([type_(\"text\"), name(\"" <> fname <> "\"), value(values." <> fname <> ")]),
        field_error(errors, \"" <> fname <> "\"),
      ]),"
      }
    })
    |> string.join("\n")

  let float_import = case list.any(fields, fn(f) { f.1 == "float" }) {
    True -> "\nimport gleam/float"
    False -> ""
  }

  "import gleam/int" <> float_import <> "
import gleam/list
import gleam/option
import lustre/attribute.{class, href, name, type_, value}
import lustre/element.{type Element, text}
import lustre/element/html.{
  a, button, div, form, h1, input, label, li, p, section, textarea, ul,
}
import " <> app_name <> "/domain/" <> resource_singular <> ".{type " <> type_name <> "}
import " <> app_name <> "/web/forms/" <> resource_singular <> "_form

pub fn index_view(items: List(" <> type_name <> ")) -> Element(Nil) {
  section([class(\"" <> resource_plural <> "\")], [
    div([class(\"header\")], [
      h1([], [text(\"" <> type_name <> "s\")]),
      a([href(\"/" <> resource_plural <> "/new\"), class(\"btn\")], [text(\"New " <> type_name <> "\")]),
    ]),
    ul(
      [class(\"post-list\")],
      list.map(items, fn(item) {
        li([], [
          a([href(\"/" <> resource_plural <> "/\" <> int.to_string(item.id))], [
            text(item." <> first_field <> "),
          ]),
        ])
      }),
    ),
  ])
}

pub fn show_view(item: " <> type_name <> ") -> Element(Nil) {
  section([class(\"" <> resource_singular <> "\")], [
    h1([], [text(item." <> first_field <> ")]),
    div([class(\"actions\")], [
      a(
        [
          href(\"/" <> resource_plural <> "/\" <> int.to_string(item.id) <> \"/edit\"),
          class(\"btn\"),
        ],
        [text(\"Edit\")],
      ),
    ]),
  ])
}

pub fn form_view(
  values: " <> resource_singular <> "_form." <> type_name <> "Form,
  errors: List(#(String, String)),
) -> Element(Nil) {
  let post_action = case values.id {
    option.Some(id) -> \"/" <> resource_plural <> "/\" <> int.to_string(id)
    option.None -> \"/" <> resource_plural <> "\"
  }

  section([class(\"" <> resource_singular <> "-form\")], [
    h1([], [text(case values.id {
      option.Some(_) -> \"Edit " <> type_name <> "\"
      option.None -> \"New " <> type_name <> "\"
    })]),
    form([attribute.action(post_action), attribute.method(\"post\")], [
      case values.id {
        option.Some(_) -> input([type_(\"hidden\"), name(\"_method\"), value(\"put\")])
        option.None -> text(\"\")
      },
" <> form_field_elements <> "
      button([type_(\"submit\"), class(\"btn\")], [text(\"Save\")]),
    ]),
  ])
}

fn field_error(
  errors: List(#(String, String)),
  field: String,
) -> Element(Nil) {
  case list.find(errors, fn(e) { e.0 == field }) {
    Ok(#(_, message)) -> p([class(\"error\")], [text(message)])
    Error(_) -> text(\"\")
  }
}
"
}

fn resource_form(
  app_name: String,
  resource_singular: String,
  type_name: String,
  fields: List(#(String, String)),
) -> String {
  let form_fields =
    fields
    |> list.map(fn(f) {
      let #(field_name, field_type) = f
      "    " <> field_name <> ": " <> form_default_value(field_type) <> ","
    })
    |> string.join("\n")

  let form_field_defs =
    fields
    |> list.map(fn(f) {
      let #(name, ft) = f
      "    " <> name <> ": " <> to_gleam_type(ft) <> ","
    })
    |> string.join("\n")

  let params_field_defs =
    fields
    |> list.map(fn(f) {
      let #(name, ft) = f
      "    " <> name <> ": " <> to_gleam_type(ft) <> ","
    })
    |> string.join("\n")

  let from_form_fields =
    fields
    |> list.map(fn(f) {
      let #(field_name, field_type) = f
      case field_type {
        "bool" ->
          "    "
          <> field_name
          <> ": list.any(data.values, fn(v) { v.0 == \""
          <> field_name
          <> "\" }),"
        "int" ->
          "    "
          <> field_name
          <> ": result.unwrap(int.parse(get_value(data, \""
          <> field_name
          <> "\")), 0),"
        "float" ->
          "    "
          <> field_name
          <> ": result.unwrap(float.parse(get_value(data, \""
          <> field_name
          <> "\")), 0.0),"
        _ ->
          "    " <> field_name <> ": get_value(data, \"" <> field_name <> "\"),"
      }
    })
    |> string.join("\n")

  let from_record_fields =
    fields
    |> list.map(fn(f) {
      let #(name, _) = f
      "    " <> name <> ": item." <> name <> ","
    })
    |> string.join("\n")

  let decode_lets =
    fields
    |> list.filter(fn(f) { f.1 != "bool" })
    |> list.map(fn(f) {
      let #(name, _) = f
      "  let " <> name <> " = get_value(data, \"" <> name <> "\")"
    })
    |> string.join("\n")

  let validation_lines =
    fields
    |> list.filter(fn(f) {
      let #(_, t) = f
      t == "string" || t == "text"
    })
    |> list.map(fn(f) {
      let #(name, _) = f
      "    |> validate.required("
      <> name
      <> ", \""
      <> name
      <> "\", \""
      <> capitalize(name)
      <> " is required\")"
    })
    |> string.join("\n")

  let params_construction =
    fields
    |> list.map(fn(f) {
      let #(name, t) = f
      case t {
        "bool" ->
          "        "
          <> name
          <> ": list.any(data.values, fn(v) { v.0 == \""
          <> name
          <> "\" }),"
        "int" ->
          "        " <> name <> ": result.unwrap(int.parse(" <> name <> "), 0),"
        "float" ->
          "        "
          <> name
          <> ": result.unwrap(float.parse("
          <> name
          <> "), 0.0),"
        _ -> "        " <> name <> ": " <> name <> ","
      }
    })
    |> string.join("\n")

  let extra_imports = case
    list.any(fields, fn(f) { f.1 == "int" }),
    list.any(fields, fn(f) { f.1 == "float" })
  {
    True, True -> "\nimport gleam/int\nimport gleam/float"
    True, False -> "\nimport gleam/int"
    False, True -> "\nimport gleam/float"
    False, False -> ""
  }

  "import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result" <> extra_imports <> "
import " <> app_name <> "/domain/" <> resource_singular <> ".{type " <> type_name <> "}
import refrakt/validate
import wisp

pub type " <> type_name <> "Form {
  " <> type_name <> "Form(
    id: Option(Int),
" <> form_field_defs <> "
  )
}

pub type " <> type_name <> "Params {
  " <> type_name <> "Params(
" <> params_field_defs <> "
  )
}

pub fn empty() -> " <> type_name <> "Form {
  " <> type_name <> "Form(
    id: None,
" <> form_fields <> "
  )
}

pub fn from_" <> resource_singular <> "(item: " <> type_name <> ") -> " <> type_name <> "Form {
  " <> type_name <> "Form(
    id: Some(item.id),
" <> from_record_fields <> "
  )
}

pub fn from_form_data(data: wisp.FormData) -> " <> type_name <> "Form {
  " <> type_name <> "Form(
    id: None,
" <> from_form_fields <> "
  )
}

pub fn decode(
  data: wisp.FormData,
) -> Result(" <> type_name <> "Params, List(#(String, String))) {
" <> decode_lets <> "

  let errors =
    []
" <> validation_lines <> "

  case errors {
    [] ->
      Ok(" <> type_name <> "Params(
" <> params_construction <> "
      ))
    _ -> Error(errors)
  }
}

fn get_value(data: wisp.FormData, key: String) -> String {
  list.find(data.values, fn(v) { v.0 == key })
  |> result.map(fn(v) { v.1 })
  |> result.unwrap(\"\")
}
"
}

fn resource_repo(
  app_name: String,
  resource_singular: String,
  type_name: String,
  fields: List(#(String, String)),
  db: DbChoice,
) -> String {
  case db {
    Sqlite | NoDb ->
      resource_repo_sqlite(app_name, resource_singular, type_name, fields)
    Postgres ->
      resource_repo_pog(app_name, resource_singular, type_name, fields)
  }
}

fn resource_repo_sqlite(
  app_name: String,
  resource_singular: String,
  type_name: String,
  fields: List(#(String, String)),
) -> String {
  let table = resource_singular <> "s"
  let field_names = list.map(fields, fn(f) { f.0 }) |> string.join(", ")
  let select_fields = "id, " <> field_names
  let q = "\""

  let decoder_fields =
    fields
    |> list.index_map(fn(f, i) {
      let #(name, field_type) = f
      let decode_fn = case field_type {
        "bool" -> "sqlight.decode_bool()"
        "int" -> "decode.int"
        "float" -> "decode.float"
        _ -> "decode.string"
      }
      "  use "
      <> name
      <> " <- decode.field("
      <> int.to_string(i + 1)
      <> ", "
      <> decode_fn
      <> ")"
    })
    |> string.join("\n")

  let constructor_args =
    fields
    |> list.map(fn(f) { f.0 <> ": " <> f.0 })
    |> string.join(", ")

  let insert_placeholders =
    fields
    |> list.index_map(fn(_, _i) { "?" })
    |> string.join(", ")

  let insert_params =
    fields
    |> list.map(fn(f) {
      let #(name, field_type) = f
      let sq_fn = case field_type {
        "bool" -> "sqlight.bool"
        "int" -> "sqlight.int"
        "float" -> "sqlight.float"
        _ -> "sqlight.text"
      }
      "    " <> sq_fn <> "(params." <> name <> "),"
    })
    |> string.join("\n")

  let update_sets =
    fields
    |> list.index_map(fn(f, _i) { f.0 <> " = ?" })
    |> string.join(", ")

  string.join(
    [
      "import gleam/dynamic/decode",
      "import gleam/result",
      "import "
        <> app_name
        <> "/domain/"
        <> resource_singular
        <> ".{type "
        <> type_name
        <> ", "
        <> type_name
        <> "}",
      "import "
        <> app_name
        <> "/web/forms/"
        <> resource_singular
        <> "_form.{type "
        <> type_name
        <> "Params}",
      "import sqlight",
      "",
      "fn "
        <> resource_singular
        <> "_decoder() -> decode.Decoder("
        <> type_name
        <> ") {",
      "  use id <- decode.field(0, decode.int)",
      decoder_fields,
      "  decode.success("
        <> type_name
        <> "(id: id, "
        <> constructor_args
        <> "))",
      "}",
      "",
      "pub fn list(db_path: String) -> List(" <> type_name <> ") {",
      "  use conn <- sqlight.with_connection(db_path)",
      "  case sqlight.query("
        <> q
        <> "SELECT "
        <> select_fields
        <> " FROM "
        <> table
        <> " ORDER BY id DESC"
        <> q
        <> ", on: conn, with: [], expecting: "
        <> resource_singular
        <> "_decoder()) {",
      "    Ok(rows) -> rows",
      "    Error(_) -> []",
      "  }",
      "}",
      "",
      "pub fn get(db_path: String, id: Int) -> Result("
        <> type_name
        <> ", Nil) {",
      "  use conn <- sqlight.with_connection(db_path)",
      "  sqlight.query("
        <> q
        <> "SELECT "
        <> select_fields
        <> " FROM "
        <> table
        <> " WHERE id = ?"
        <> q
        <> ", on: conn, with: [sqlight.int(id)], expecting: "
        <> resource_singular
        <> "_decoder())",
      "  |> result.replace_error(Nil)",
      "  |> result.try(fn(rows) {",
      "    case rows {",
      "      [item] -> Ok(item)",
      "      _ -> Error(Nil)",
      "    }",
      "  })",
      "}",
      "",
      "pub fn create(db_path: String, params: "
        <> type_name
        <> "Params) -> Result("
        <> type_name
        <> ", Nil) {",
      "  use conn <- sqlight.with_connection(db_path)",
      "  sqlight.query(",
      "    "
        <> q
        <> "INSERT INTO "
        <> table
        <> " ("
        <> field_names
        <> ") VALUES ("
        <> insert_placeholders
        <> ") RETURNING "
        <> select_fields
        <> q
        <> ",",
      "    on: conn,",
      "    with: [",
      insert_params,
      "    ],",
      "    expecting: " <> resource_singular <> "_decoder(),",
      "  )",
      "  |> result.replace_error(Nil)",
      "  |> result.try(fn(rows) {",
      "    case rows {",
      "      [item] -> Ok(item)",
      "      _ -> Error(Nil)",
      "    }",
      "  })",
      "}",
      "",
      "pub fn update(",
      "  db_path: String,",
      "  id: Int,",
      "  params: " <> type_name <> "Params,",
      ") -> Result(" <> type_name <> ", Nil) {",
      "  use conn <- sqlight.with_connection(db_path)",
      "  sqlight.query(",
      "    "
        <> q
        <> "UPDATE "
        <> table
        <> " SET "
        <> update_sets
        <> " WHERE id = ? RETURNING "
        <> select_fields
        <> q
        <> ",",
      "    on: conn,",
      "    with: [",
      insert_params,
      "      sqlight.int(id),",
      "    ],",
      "    expecting: " <> resource_singular <> "_decoder(),",
      "  )",
      "  |> result.replace_error(Nil)",
      "  |> result.try(fn(rows) {",
      "    case rows {",
      "      [item] -> Ok(item)",
      "      _ -> Error(Nil)",
      "    }",
      "  })",
      "}",
      "",
      "pub fn delete(db_path: String, id: Int) -> Result(Nil, Nil) {",
      "  use conn <- sqlight.with_connection(db_path)",
      "  sqlight.query("
        <> q
        <> "DELETE FROM "
        <> table
        <> " WHERE id = ?"
        <> q
        <> ", on: conn, with: [sqlight.int(id)], expecting: decode.success(Nil))",
      "  |> result.replace(Nil)",
      "  |> result.replace_error(Nil)",
      "}",
      "",
    ],
    "\n",
  )
}

fn resource_repo_pog(
  app_name: String,
  resource_singular: String,
  type_name: String,
  fields: List(#(String, String)),
) -> String {
  let field_names =
    fields
    |> list.map(fn(f) { f.0 })
    |> string.join(", ")

  let select_fields = "id, " <> field_names

  let decoder_fields =
    fields
    |> list.index_map(fn(f, i) {
      let #(name, field_type) = f
      let decode_fn = case field_type {
        "bool" -> "decode.bool"
        "int" -> "decode.int"
        "float" -> "decode.float"
        _ -> "decode.string"
      }
      "  use "
      <> name
      <> " <- decode.field("
      <> int.to_string(i + 1)
      <> ", "
      <> decode_fn
      <> ")"
    })
    |> string.join("\n")

  let constructor_args =
    fields
    |> list.map(fn(f) { f.0 <> ": " <> f.0 })
    |> string.join(", ")

  let insert_placeholders =
    fields
    |> list.index_map(fn(_, i) { "$" <> int.to_string(i + 1) })
    |> string.join(", ")

  let insert_params =
    fields
    |> list.map(fn(f) {
      let #(name, field_type) = f
      let pog_fn = case field_type {
        "bool" -> "pog.bool"
        "int" -> "pog.int"
        "float" -> "pog.float"
        _ -> "pog.text"
      }
      "  |> pog.parameter(" <> pog_fn <> "(params." <> name <> "))"
    })
    |> string.join("\n")

  let update_sets =
    fields
    |> list.index_map(fn(f, i) { f.0 <> " = $" <> int.to_string(i + 1) })
    |> string.join(", ")

  let update_id_param = "$" <> int.to_string(list.length(fields) + 1)

  let q = "\""
  let table = resource_singular <> "s"

  let list_query =
    "  pog.query("
    <> q
    <> "SELECT "
    <> select_fields
    <> " FROM "
    <> table
    <> " ORDER BY id DESC"
    <> q
    <> ")"

  let get_query =
    "  pog.query("
    <> q
    <> "SELECT "
    <> select_fields
    <> " FROM "
    <> table
    <> " WHERE id = $1"
    <> q
    <> ")"

  let create_query =
    "  pog.query("
    <> q
    <> "INSERT INTO "
    <> table
    <> " ("
    <> field_names
    <> ") VALUES ("
    <> insert_placeholders
    <> ") RETURNING "
    <> select_fields
    <> q
    <> ")"

  let update_query =
    "  pog.query("
    <> q
    <> "UPDATE "
    <> table
    <> " SET "
    <> update_sets
    <> " WHERE id = "
    <> update_id_param
    <> " RETURNING "
    <> select_fields
    <> q
    <> ")"

  let delete_query =
    "  pog.query("
    <> q
    <> "DELETE FROM "
    <> table
    <> " WHERE id = $1"
    <> q
    <> ")"

  let single_row_extract =
    "  |> pog.execute(db)
  |> result.replace_error(Nil)
  |> result.try(fn(r) {
    case r.rows {
      [item] -> Ok(item)
      _ -> Error(Nil)
    }
  })"

  string.join(
    [
      "import gleam/dynamic/decode",
      "import gleam/result",
      "import "
        <> app_name
        <> "/domain/"
        <> resource_singular
        <> ".{type "
        <> type_name
        <> ", "
        <> type_name
        <> "}",
      "import "
        <> app_name
        <> "/web/forms/"
        <> resource_singular
        <> "_form.{type "
        <> type_name
        <> "Params}",
      "import pog",
      "",
      "fn "
        <> resource_singular
        <> "_decoder() -> decode.Decoder("
        <> type_name
        <> ") {",
      "  use id <- decode.field(0, decode.int)",
      decoder_fields,
      "  decode.success("
        <> type_name
        <> "(id: id, "
        <> constructor_args
        <> "))",
      "}",
      "",
      "pub fn list(db: pog.Connection) -> List(" <> type_name <> ") {",
      list_query,
      "  |> pog.returning(" <> resource_singular <> "_decoder())",
      "  |> pog.execute(db)",
      "  |> result.map(fn(r) { r.rows })",
      "  |> result.unwrap([])",
      "}",
      "",
      "pub fn get(db: pog.Connection, id: Int) -> Result("
        <> type_name
        <> ", Nil) {",
      get_query,
      "  |> pog.parameter(pog.int(id))",
      "  |> pog.returning(" <> resource_singular <> "_decoder())",
      single_row_extract,
      "}",
      "",
      "pub fn create(db: pog.Connection, params: "
        <> type_name
        <> "Params) -> Result("
        <> type_name
        <> ", Nil) {",
      create_query,
      insert_params,
      "  |> pog.returning(" <> resource_singular <> "_decoder())",
      single_row_extract,
      "}",
      "",
      "pub fn update(",
      "  db: pog.Connection,",
      "  id: Int,",
      "  params: " <> type_name <> "Params,",
      ") -> Result(" <> type_name <> ", Nil) {",
      update_query,
      insert_params,
      "  |> pog.parameter(pog.int(id))",
      "  |> pog.returning(" <> resource_singular <> "_decoder())",
      single_row_extract,
      "}",
      "",
      "pub fn delete(db: pog.Connection, id: Int) -> Result(Nil, Nil) {",
      delete_query,
      "  |> pog.parameter(pog.int(id))",
      "  |> pog.execute(db)",
      "  |> result.replace(Nil)",
      "  |> result.replace_error(Nil)",
      "}",
      "",
    ],
    "\n",
  )
}

fn resource_migration(
  name: String,
  fields: List(#(String, String)),
  db: DbChoice,
) -> String {
  let column_defs =
    fields
    |> list.map(fn(f) {
      let #(field_name, field_type) = f
      let sql_type = case db {
        Sqlite -> to_sql_type_sqlite(field_type)
        _ -> to_sql_type(field_type)
      }
      "  " <> field_name <> " " <> sql_type <> " NOT NULL"
    })
    |> string.join(",\n")

  let table = singularize(name) <> "s"

  case db {
    Sqlite -> "CREATE TABLE " <> table <> " (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
" <> column_defs <> ",
  inserted_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);
"
    _ -> "CREATE TABLE " <> table <> " (
  id SERIAL PRIMARY KEY,
" <> column_defs <> ",
  inserted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
"
  }
}

fn resource_test(
  app_name: String,
  resource_singular: String,
  _type_name: String,
  fields: List(#(String, String)),
) -> String {
  // Build valid form data for decode test
  let valid_values =
    fields
    |> list.map(fn(f) {
      let #(name, ftype) = f
      let val = case ftype {
        "bool" -> "on"
        "int" -> "42"
        "float" -> "3.14"
        _ -> "test value"
      }
      "    #(\"" <> name <> "\", \"" <> val <> "\"),"
    })
    |> string.join("\n")

  // Find required string fields for missing-field test
  let required_fields =
    fields
    |> list.filter(fn(f) { f.1 == "string" || f.1 == "text" })

  let missing_field_test = case required_fields {
    [#(name, _), ..] -> "

pub fn decode_missing_" <> name <> "_returns_error_test() {
  let data =
    wisp.FormData(values: [], files: [])

  " <> resource_singular <> "_form.decode(data)
  |> should.be_error
}
"
    [] -> ""
  }

  "import gleeunit/should
import " <> app_name <> "/web/forms/" <> resource_singular <> "_form
import wisp

pub fn empty_form_has_no_id_test() {
  let form = " <> resource_singular <> "_form.empty()
  form.id
  |> should.be_none
}

pub fn decode_valid_form_test() {
  let data =
    wisp.FormData(
      values: [
" <> valid_values <> "
      ],
      files: [],
    )

  " <> resource_singular <> "_form.decode(data)
  |> should.be_ok
}
" <> missing_field_test
}

// =============================================================================
// Router patching
// =============================================================================

fn patch_router_page(app: String, name: String) {
  let router_path = "src/" <> app <> "/router.gleam"
  let assert Ok(content) = simplifile.read(router_path)

  // Add import
  let import_line = "import " <> app <> "/web/" <> name <> "_handler"
  let content = add_import(content, import_line)

  // Add route before catch-all
  let route_line =
    "    [\""
    <> name
    <> "\"], http.Get -> "
    <> name
    <> "_handler.index(req, ctx)"

  let content = add_route(content, route_line)

  let assert Ok(_) = simplifile.write(router_path, content)
}

fn patch_router_resource(app: String, plural: String, singular: String) {
  let router_path = "src/" <> app <> "/router.gleam"
  let assert Ok(content) = simplifile.read(router_path)

  // Add import
  let import_line = "import " <> app <> "/web/" <> singular <> "_handler"
  let content = add_import(content, import_line)

  // Add routes before catch-all
  let routes =
    "\n    [\""
    <> plural
    <> "\"], http.Get -> "
    <> singular
    <> "_handler.index(req, ctx)
    [\""
    <> plural
    <> "\", \"new\"], http.Get -> "
    <> singular
    <> "_handler.new(req, ctx)
    [\""
    <> plural
    <> "\"], http.Post -> "
    <> singular
    <> "_handler.create(req, ctx)
    [\""
    <> plural
    <> "\", id], http.Get -> "
    <> singular
    <> "_handler.show(req, ctx, id)
    [\""
    <> plural
    <> "\", id, \"edit\"], http.Get -> "
    <> singular
    <> "_handler.edit(req, ctx, id)
    [\""
    <> plural
    <> "\", id], http.Put -> "
    <> singular
    <> "_handler.update(req, ctx, id)
    [\""
    <> plural
    <> "\", id], http.Delete -> "
    <> singular
    <> "_handler.delete(req, ctx, id)"

  let content = add_route(content, routes)

  let assert Ok(_) = simplifile.write(router_path, content)
}

fn add_import(content: String, import_line: String) -> String {
  // Check if import already exists
  case string.contains(content, import_line) {
    True -> content
    False -> {
      // Find last import line and add after it
      let lines = string.split(content, "\n")
      let #(before, after) = split_after_imports(lines, [])
      string.join(list.append(before, [import_line, ..after]), "\n")
    }
  }
}

fn split_after_imports(
  lines: List(String),
  acc: List(String),
) -> #(List(String), List(String)) {
  case lines {
    [] -> #(list.reverse(acc), [])
    [line, ..rest] ->
      case string.starts_with(line, "import ") {
        True -> split_after_imports(rest, [line, ..acc])
        False ->
          case acc {
            [] -> split_after_imports(rest, [line, ..acc])
            _ -> #(list.reverse(acc), [line, ..rest])
          }
      }
  }
}

fn add_route(content: String, route_line: String) -> String {
  // Insert before the catch-all `_, _ ->` pattern
  case string.split_once(content, "    _, _ ->") {
    Ok(#(before, after)) -> before <> route_line <> "\n    _, _ ->" <> after
    Error(_) ->
      // Fallback: try `_ ->` pattern
      case string.split_once(content, "    _ ->") {
        Ok(#(before, after)) -> before <> route_line <> "\n    _ ->" <> after
        Error(_) -> content
      }
  }
}

// =============================================================================
// Field parsing and type conversion
// =============================================================================

pub fn parse_fields(raw: List(String)) -> List(#(String, String)) {
  raw
  |> list.filter_map(fn(field) {
    case string.split(field, ":") {
      [name, field_type] -> Ok(#(name, field_type))
      _ -> Error(Nil)
    }
  })
}

pub fn to_gleam_type(field_type: String) -> String {
  case field_type {
    "string" -> "String"
    "text" -> "String"
    "int" -> "Int"
    "float" -> "Float"
    "bool" -> "Bool"
    "date" -> "String"
    "datetime" -> "String"
    _ -> "String"
  }
}

pub fn to_sql_type(field_type: String) -> String {
  case field_type {
    "string" -> "TEXT"
    "text" -> "TEXT"
    "int" -> "INTEGER"
    "float" -> "DOUBLE PRECISION"
    "bool" -> "BOOLEAN"
    "date" -> "DATE"
    "datetime" -> "TIMESTAMPTZ"
    _ -> "TEXT"
  }
}

fn to_sql_type_sqlite(field_type: String) -> String {
  case field_type {
    "string" -> "TEXT"
    "text" -> "TEXT"
    "int" -> "INTEGER"
    "float" -> "REAL"
    "bool" -> "INTEGER"
    "date" -> "TEXT"
    "datetime" -> "TEXT"
    _ -> "TEXT"
  }
}

fn form_default_value(field_type: String) -> String {
  case field_type {
    "bool" -> "False"
    "int" -> "0"
    "float" -> "0.0"
    _ -> "\"\""
  }
}

// =============================================================================
// Auth generator templates
// =============================================================================

fn auth_user_type() -> String {
  "pub type User {
  User(id: Int, email: String, hashed_password: String)
}
"
}

fn auth_domain(_app: String) -> String {
  "import gleam/crypto
import gleam/bit_array
import gleam/string

/// Hash a password using a simple HMAC-based approach.
/// Replace with a proper bcrypt/argon2 library for production.
pub fn hash_password(password: String) -> String {
  crypto.hash(crypto.Sha256, bit_array.from_string(password))
  |> bit_array.base16_encode
  |> string.lowercase
}

/// Verify a password against a hash.
pub fn verify_password(password: String, hash: String) -> Bool {
  hash_password(password) == hash
}
"
}

fn auth_user_repo(app: String) -> String {
  let q = "\""
  "import gleam/dynamic/decode
import gleam/result
import " <> app <> "/domain/user.{type User, User}
import pog

fn user_decoder() -> decode.Decoder(User) {
  use id <- decode.field(0, decode.int)
  use email <- decode.field(1, decode.string)
  use hashed_password <- decode.field(2, decode.string)
  decode.success(User(id: id, email: email, hashed_password: hashed_password))
}

pub fn get_by_email(db: pog.Connection, email: String) -> Result(User, Nil) {
  pog.query(" <> q <> "SELECT id, email, hashed_password FROM users WHERE email = $1" <> q <> ")
  |> pog.parameter(pog.text(email))
  |> pog.returning(user_decoder())
  |> pog.execute(db)
  |> result.replace_error(Nil)
  |> result.try(fn(r) {
    case r.rows {
      [user] -> Ok(user)
      _ -> Error(Nil)
    }
  })
}

pub fn get_by_id(db: pog.Connection, id: Int) -> Result(User, Nil) {
  pog.query(" <> q <> "SELECT id, email, hashed_password FROM users WHERE id = $1" <> q <> ")
  |> pog.parameter(pog.int(id))
  |> pog.returning(user_decoder())
  |> pog.execute(db)
  |> result.replace_error(Nil)
  |> result.try(fn(r) {
    case r.rows {
      [user] -> Ok(user)
      _ -> Error(Nil)
    }
  })
}

pub fn create(
  db: pog.Connection,
  email: String,
  hashed_password: String,
) -> Result(User, Nil) {
  pog.query(
    " <> q <> "INSERT INTO users (email, hashed_password) VALUES ($1, $2) RETURNING id, email, hashed_password" <> q <> ",
  )
  |> pog.parameter(pog.text(email))
  |> pog.parameter(pog.text(hashed_password))
  |> pog.returning(user_decoder())
  |> pog.execute(db)
  |> result.replace_error(Nil)
  |> result.try(fn(r) {
    case r.rows {
      [user] -> Ok(user)
      _ -> Error(Nil)
    }
  })
}
"
}

fn auth_migration() -> String {
  "CREATE TABLE users (
  id SERIAL PRIMARY KEY,
  email TEXT NOT NULL UNIQUE,
  hashed_password TEXT NOT NULL,
  inserted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX users_email_index ON users (email);
"
}

fn auth_form(_app: String) -> String {
  "import gleam/list
import gleam/result
import refrakt/validate
import wisp

pub type LoginParams {
  LoginParams(email: String, password: String)
}

pub type RegisterParams {
  RegisterParams(email: String, password: String, password_confirmation: String)
}

pub fn decode_login(
  data: wisp.FormData,
) -> Result(LoginParams, List(#(String, String))) {
  let email = get_value(data, \"email\")
  let password = get_value(data, \"password\")

  let errors =
    []
    |> validate.required(email, \"email\", \"Email is required\")
    |> validate.required(password, \"password\", \"Password is required\")

  case errors {
    [] -> Ok(LoginParams(email: email, password: password))
    _ -> Error(errors)
  }
}

pub fn decode_register(
  data: wisp.FormData,
) -> Result(RegisterParams, List(#(String, String))) {
  let email = get_value(data, \"email\")
  let password = get_value(data, \"password\")
  let password_confirmation = get_value(data, \"password_confirmation\")

  let errors =
    []
    |> validate.required(email, \"email\", \"Email is required\")
    |> validate.required(password, \"password\", \"Password is required\")
    |> validate.min_length(password, \"password\", 8, \"Password must be at least 8 characters\")
    |> check_confirmation(password, password_confirmation)

  case errors {
    [] ->
      Ok(RegisterParams(
        email: email,
        password: password,
        password_confirmation: password_confirmation,
      ))
    _ -> Error(errors)
  }
}

fn check_confirmation(
  errors: List(#(String, String)),
  password: String,
  confirmation: String,
) -> List(#(String, String)) {
  case password == confirmation {
    True -> errors
    False -> [#(\"password_confirmation\", \"Passwords do not match\"), ..errors]
  }
}

fn get_value(data: wisp.FormData, key: String) -> String {
  list.find(data.values, fn(v) { v.0 == key })
  |> result.map(fn(v) { v.1 })
  |> result.unwrap(\"\")
}
"
}

fn auth_handler(app: String) -> String {
  "import gleam/int
import " <> app <> "/context.{type Context}
import " <> app <> "/data/user_repo
import " <> app <> "/domain/auth
import " <> app <> "/web/auth_views
import " <> app <> "/web/error_handler
import " <> app <> "/web/forms/auth_form
import " <> app <> "/web/layouts/root_layout
import refrakt/flash
import wisp.{type Request, type Response}

pub fn login_page(_req: Request, _ctx: Context) -> Response {
  auth_views.login_view(\"\", [])
  |> root_layout.wrap(\"Log In\")
  |> wisp.html_response(200)
}

pub fn login(req: Request, ctx: Context) -> Response {
  use form_data <- wisp.require_form(req)

  case auth_form.decode_login(form_data) {
    Error(errors) ->
      auth_views.login_view(\"\", errors)
      |> root_layout.wrap(\"Log In\")
      |> wisp.html_response(422)

    Ok(params) ->
      case user_repo.get_by_email(ctx.db, params.email) {
        Error(_) ->
          auth_views.login_view(params.email, [#(\"email\", \"Invalid email or password\")])
          |> root_layout.wrap(\"Log In\")
          |> wisp.html_response(422)

        Ok(user) ->
          case auth.verify_password(params.password, user.hashed_password) {
            False ->
              auth_views.login_view(params.email, [#(\"email\", \"Invalid email or password\")])
              |> root_layout.wrap(\"Log In\")
              |> wisp.html_response(422)

            True ->
              wisp.redirect(\"/\")
              |> wisp.set_cookie(
                req,
                \"_user_id\",
                int.to_string(user.id),
                wisp.Signed,
                60 * 60 * 24 * 7,
              )
              |> flash.set_flash(req, \"info\", \"Logged in\")
          }
      }
  }
}

pub fn register_page(_req: Request, _ctx: Context) -> Response {
  auth_views.register_view(\"\", [])
  |> root_layout.wrap(\"Register\")
  |> wisp.html_response(200)
}

pub fn register(req: Request, ctx: Context) -> Response {
  use form_data <- wisp.require_form(req)

  case auth_form.decode_register(form_data) {
    Error(errors) ->
      auth_views.register_view(\"\", errors)
      |> root_layout.wrap(\"Register\")
      |> wisp.html_response(422)

    Ok(params) -> {
      let hashed = auth.hash_password(params.password)
      case user_repo.create(ctx.db, params.email, hashed) {
        Ok(user) ->
          wisp.redirect(\"/\")
          |> wisp.set_cookie(
            req,
            \"_user_id\",
            int.to_string(user.id),
            wisp.Signed,
            60 * 60 * 24 * 7,
          )
          |> flash.set_flash(req, \"info\", \"Account created\")

        Error(_) ->
          auth_views.register_view(params.email, [#(\"email\", \"Could not create account\")])
          |> root_layout.wrap(\"Register\")
          |> wisp.html_response(422)
      }
    }
  }
}

pub fn logout(req: Request, _ctx: Context) -> Response {
  wisp.redirect(\"/\")
  |> wisp.set_cookie(req, \"_user_id\", \"\", wisp.Signed, 0)
  |> flash.set_flash(req, \"info\", \"Logged out\")
}
"
}

fn auth_views(_app: String) -> String {
  "import gleam/list
import lustre/attribute.{class, href, name, type_, value}
import lustre/element.{type Element, text}
import lustre/element/html.{
  a, button, div, form, h1, input, label, p, section,
}

pub fn login_view(email: String, errors: List(#(String, String))) -> Element(Nil) {
  section([class(\"auth-form\")], [
    h1([], [text(\"Log In\")]),
    form([attribute.action(\"/login\"), attribute.method(\"post\")], [
      div([class(\"field\")], [
        label([], [text(\"Email\")]),
        input([type_(\"email\"), name(\"email\"), value(email)]),
        field_error(errors, \"email\"),
      ]),
      div([class(\"field\")], [
        label([], [text(\"Password\")]),
        input([type_(\"password\"), name(\"password\")]),
        field_error(errors, \"password\"),
      ]),
      button([type_(\"submit\"), class(\"btn\")], [text(\"Log In\")]),
    ]),
    p([], [
      text(\"Don't have an account? \"),
      a([href(\"/register\")], [text(\"Register\")]),
    ]),
  ])
}

pub fn register_view(
  email: String,
  errors: List(#(String, String)),
) -> Element(Nil) {
  section([class(\"auth-form\")], [
    h1([], [text(\"Register\")]),
    form([attribute.action(\"/register\"), attribute.method(\"post\")], [
      div([class(\"field\")], [
        label([], [text(\"Email\")]),
        input([type_(\"email\"), name(\"email\"), value(email)]),
        field_error(errors, \"email\"),
      ]),
      div([class(\"field\")], [
        label([], [text(\"Password\")]),
        input([type_(\"password\"), name(\"password\")]),
        field_error(errors, \"password\"),
      ]),
      div([class(\"field\")], [
        label([], [text(\"Confirm Password\")]),
        input([type_(\"password\"), name(\"password_confirmation\")]),
        field_error(errors, \"password_confirmation\"),
      ]),
      button([type_(\"submit\"), class(\"btn\")], [text(\"Register\")]),
    ]),
    p([], [
      text(\"Already have an account? \"),
      a([href(\"/login\")], [text(\"Log In\")]),
    ]),
  ])
}

fn field_error(errors: List(#(String, String)), field: String) -> Element(Nil) {
  case list.find(errors, fn(e) { e.0 == field }) {
    Ok(#(_, message)) -> p([class(\"error\")], [text(message)])
    Error(_) -> text(\"\")
  }
}
"
}

fn auth_middleware(app: String) -> String {
  "import gleam/int
import gleam/result
import " <> app <> "/context.{type Context}
import " <> app <> "/data/user_repo
import " <> app <> "/domain/user.{type User}
import wisp.{type Request, type Response}

/// Extract the current user from the session cookie.
pub fn get_current_user(req: Request, ctx: Context) -> Result(User, Nil) {
  use user_id_str <- result.try(wisp.get_cookie(req, \"_user_id\", wisp.Signed))
  use user_id <- result.try(
    int.parse(user_id_str)
    |> result.replace_error(Nil),
  )
  user_repo.get_by_id(ctx.db, user_id)
}

/// Middleware that requires authentication.
/// Redirects to /login if no valid session.
pub fn require_auth(
  req: Request,
  ctx: Context,
  next: fn(User) -> Response,
) -> Response {
  case get_current_user(req, ctx) {
    Ok(user) -> next(user)
    Error(_) -> wisp.redirect(\"/login\")
  }
}
"
}

fn auth_test(app: String) -> String {
  "import gleeunit/should
import " <> app <> "/domain/auth

pub fn hash_password_test() {
  let hash = auth.hash_password(\"secret123\")
  auth.verify_password(\"secret123\", hash)
  |> should.be_true
}

pub fn wrong_password_test() {
  let hash = auth.hash_password(\"secret123\")
  auth.verify_password(\"wrong\", hash)
  |> should.be_false
}
"
}

fn patch_router_auth(app: String) {
  let router_path = "src/" <> app <> "/router.gleam"
  let assert Ok(content) = simplifile.read(router_path)

  let import_line = "import " <> app <> "/web/auth_handler"
  let content = add_import(content, import_line)

  let routes =
    "\n    [\"login\"], http.Get -> auth_handler.login_page(req, ctx)
    [\"login\"], http.Post -> auth_handler.login(req, ctx)
    [\"register\"], http.Get -> auth_handler.register_page(req, ctx)
    [\"register\"], http.Post -> auth_handler.register(req, ctx)
    [\"logout\"], http.Post -> auth_handler.logout(req, ctx)"

  let content = add_route(content, routes)

  let assert Ok(_) = simplifile.write(router_path, content)
}

// =============================================================================
// String helpers
// =============================================================================

fn capitalize(s: String) -> String {
  case string.pop_grapheme(s) {
    Ok(#(first, rest)) -> string.uppercase(first) <> rest
    Error(_) -> s
  }
}

fn singularize(s: String) -> String {
  // Simple singularization: drop trailing 's'
  // Handles: posts -> post, users -> user, categories -> categorie (good enough for MVP)
  case string.ends_with(s, "ies") {
    True -> string.drop_end(s, 3) <> "y"
    False ->
      case string.ends_with(s, "ses") {
        True -> string.drop_end(s, 2)
        False ->
          case string.ends_with(s, "s") {
            True -> string.drop_end(s, 1)
            False -> s
          }
      }
  }
}

fn next_migration_number(app: String) -> String {
  let dir = "src/" <> app <> "/data/migrations"
  case simplifile.read_directory(dir) {
    Ok(files) -> {
      let count = list.length(files) + 1
      pad_number(count, 3)
    }
    Error(_) -> "001"
  }
}

fn pad_number(n: Int, width: Int) -> String {
  let s = int.to_string(n)
  let padding = width - string.length(s)
  case padding > 0 {
    True -> string.repeat("0", padding) <> s
    False -> s
  }
}

fn ensure_dir_for(path: String) {
  case string.split(path, "/") {
    [] -> Nil
    parts -> {
      let dir =
        parts
        |> list.take(list.length(parts) - 1)
        |> string.join("/")
      let _ = simplifile.create_directory_all(dir)
      Nil
    }
  }
}
