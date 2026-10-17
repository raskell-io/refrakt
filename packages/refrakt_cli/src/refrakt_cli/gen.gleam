//// Code generators: page, resource, migration, auth.
////

import gleam/int
import gleam/io
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import refrakt_cli/format
import refrakt_cli/project
import refrakt_cli/templates
import refrakt_cli/types.{
  type DbChoice, type Relation, NoDb, Postgres, Relation, Sqlite,
}
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

pub fn resource(name: String, raw_args: List(String)) {
  case project.detect_db() {
    NoDb -> {
      io.println("No database configured.")
      io.println(
        "gen resource generates a repo and a migration. Create a project with --db postgres or --db sqlite.",
      )
    }
    db -> resource_with_db(name, raw_args, db)
  }
}

fn resource_with_db(name: String, raw_args: List(String), db: DbChoice) {
  let app = project.app_name()
  let parsed = {
    use #(raw_fields, api_mode, belongs_to) <- result.try(resource_args(
      raw_args,
      [],
      False,
      None,
    ))
    use fields <- result.try(parse_fields(raw_fields))
    use relation <- result.try(load_relation(app, belongs_to))
    use fields <- result.try(add_relation_field(fields, relation))
    Ok(#(fields, api_mode, relation))
  }
  case parsed {
    Error(message) -> {
      io.println("Error: " <> message)
      io.println("Nothing was generated.")
    }
    Ok(#(fields, api_mode, relation)) ->
      generate_resource(app, name, fields, api_mode, relation, db)
  }
}

/// Split `gen resource` arguments into field specs, `--api` and the
/// `--belongs-to` parent.
fn resource_args(
  args: List(String),
  fields: List(String),
  api_mode: Bool,
  belongs_to: Option(String),
) -> Result(#(List(String), Bool, Option(String)), String) {
  case args {
    [] -> Ok(#(list.reverse(fields), api_mode, belongs_to))
    ["--api", ..rest] -> resource_args(rest, fields, True, belongs_to)
    ["--belongs-to=" <> parent, ..rest] | ["--belongs-to", parent, ..rest] ->
      case parent == "" || string.starts_with(parent, "-") {
        True -> Error(belongs_to_usage)
        False -> resource_args(rest, fields, api_mode, Some(parent))
      }
    ["--belongs-to"] -> Error(belongs_to_usage)
    [arg, ..rest] ->
      case string.starts_with(arg, "-") {
        True ->
          Error("Unknown option " <> arg <> " (use --api or --belongs-to).")
        False -> resource_args(rest, [arg, ..fields], api_mode, belongs_to)
      }
  }
}

const belongs_to_usage =
  "--belongs-to needs the parent resource, such as --belongs-to posts."

/// Look up the parent resource of `--belongs-to`. It must have been
/// generated (a domain type and a repo with `get`), since the child's
/// handlers check that the parent exists.
fn load_relation(
  app: String,
  belongs_to: Option(String),
) -> Result(Option(Relation), String) {
  case belongs_to {
    None -> Ok(None)
    Some(plural) -> {
      let singular = singularize(plural)
      let domain_path = "src/" <> app <> "/domain/" <> singular <> ".gleam"
      let repo_path = "src/" <> app <> "/data/" <> singular <> "_repo.gleam"
      case simplifile.read(domain_path), simplifile.read(repo_path) {
        Ok(domain), Ok(repo) ->
          case string.contains(repo, "pub fn get(") {
            False ->
              Error(
                "--belongs-to "
                <> plural
                <> ": "
                <> repo_path
                <> " has no `get(db, id)` function, which the generated handlers use to check that the "
                <> singular
                <> " exists.",
              )
            True ->
              Ok(
                Some(Relation(
                  plural: plural,
                  singular: singular,
                  type_name: capitalize(singular),
                  table: singular <> "s",
                  field: singular <> "_id",
                  label: first_string_field(domain),
                )),
              )
          }
        _, _ ->
          Error(
            "--belongs-to "
            <> plural
            <> ": there is no "
            <> plural
            <> " resource ("
            <> domain_path
            <> " or "
            <> repo_path
            <> " is missing). Generate it first, for example: refrakt gen resource "
            <> plural
            <> " title:string",
          )
      }
    }
  }
}

/// The first `name: String` field of a generated domain type, such as
/// `pub type Post { Post(id: Int, title: String) }` on one line or several.
pub fn first_string_field(domain: String) -> Option(String) {
  let fields = case string.split_once(domain, "(") {
    Ok(#(_, after)) -> after
    Error(_) -> ""
  }
  fields
  |> string.split(",")
  |> list.find_map(fn(field) {
    case string.split_once(field, ":") {
      Ok(#(name, gleam_type)) ->
        // the last field is followed by the constructor's `)`
        case string.trim(name), string.trim(gleam_type) {
          "id", _ -> Error(Nil)
          name, "String" -> Ok(name)
          name, "String)" <> _ -> Ok(name)
          _, _ -> Error(Nil)
        }
      Error(_) -> Error(Nil)
    }
  })
  |> option.from_result
}

/// Append the foreign key field of `--belongs-to`.
fn add_relation_field(
  fields: List(#(String, String)),
  relation: Option(Relation),
) -> Result(List(#(String, String)), String) {
  case relation {
    None -> Ok(fields)
    Some(relation) ->
      case list.any(fields, fn(f) { f.0 == relation.field }) {
        True ->
          Error(
            "--belongs-to "
            <> relation.plural
            <> " adds the field "
            <> relation.field
            <> " itself; leave it out of the field list.",
          )
        False -> Ok(list.append(fields, [#(relation.field, "int")]))
      }
  }
}

fn generate_resource(
  app: String,
  name: String,
  fields: List(#(String, String)),
  api_mode: Bool,
  relation: Option(Relation),
  db: DbChoice,
) {
  let singular = singularize(name)
  let type_name = capitalize(singular)

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

  // Generate handler (HTML or JSON)
  let assert Ok(_) = case api_mode {
    True ->
      simplifile.write(
        handler_path,
        api_resource_handler(
          app,
          name,
          singular,
          type_name,
          db,
          fields,
          relation,
        ),
      )
    False ->
      simplifile.write(
        handler_path,
        templates.resource_handler(
          app,
          name,
          singular,
          type_name,
          first_field,
          db,
          relation,
        ),
      )
  }

  // Views and forms: full for HTML, params-only for API
  let created_paths = case api_mode {
    False -> {
      let assert Ok(_) =
        simplifile.write(
          views_path,
          resource_views(app, name, singular, type_name, fields, relation),
        )
      let assert Ok(_) =
        simplifile.write(
          form_path,
          resource_form(app, singular, type_name, fields),
        )
      [handler_path, views_path, form_path, domain_path, repo_path, test_path]
    }
    True -> {
      // API mode still needs the Params type for repos
      let assert Ok(_) =
        simplifile.write(form_path, api_params_module(type_name, fields))
      [handler_path, form_path, domain_path, repo_path, test_path]
    }
  }

  let assert Ok(_) =
    simplifile.write(
      domain_path,
      templates.resource_domain_type(type_name, gleam_fields),
    )

  let assert Ok(_) =
    simplifile.write(
      repo_path,
      resource_repo(app, singular, type_name, fields, db, relation, !api_mode),
    )

  let assert Ok(_) =
    simplifile.write(
      migration_path,
      resource_migration(name, fields, db, relation),
    )

  let assert Ok(_) =
    simplifile.write(test_path, case api_mode {
      True -> api_resource_test(app, name, singular, db, fields)
      // A --belongs-to form re-renders with the parents from the database,
      // which these tests do not start on Postgres
      False ->
        resource_test(app, name, singular, fields, db, case relation, db {
          Some(_), Postgres -> False
          _, _ -> True
        })
    })

  // An HTML child gets a component listing it on the parent's show page
  let children = case relation, api_mode {
    Some(relation), False ->
      Some(generate_children(
        app,
        name,
        singular,
        type_name,
        fields,
        relation,
        db,
      ))
    _, _ -> None
  }
  let created_paths = case children {
    Some(children) -> list.append(created_paths, [children.component_path])
    None -> created_paths
  }
  let patched_paths = case children {
    Some(Children(patched: Some(path), ..)) -> [path]
    _ -> []
  }

  // Patch router and format
  let _ = case api_mode {
    True -> patch_router_api_resource(app, name, singular)
    False -> patch_router_resource(app, name, singular)
  }
  let router_path = "src/" <> app <> "/router.gleam"
  format.format_files(
    list.flatten([[router_path], created_paths, patched_paths]),
  )

  io.println("")
  io.println("Created:")
  io.println("  " <> handler_path)
  case api_mode {
    False -> {
      io.println("  " <> views_path)
      io.println("  " <> form_path)
    }
    True -> Nil
  }
  io.println("  " <> domain_path)
  io.println("  " <> repo_path)
  io.println("  " <> migration_path)
  io.println("  " <> test_path)
  case children {
    Some(children) -> io.println("  " <> children.component_path)
    None -> Nil
  }
  io.println("")
  io.println("Updated:")
  io.println("  " <> router_path)
  list.each(patched_paths, fn(path) {
    io.println("  " <> path <> " (lists the " <> name <> " on the show page)")
  })
  case children {
    Some(Children(instructions: [_, ..] as lines, ..)) -> {
      io.println("")
      list.each(lines, io.println)
    }
    _ -> Nil
  }
  case relation {
    Some(relation) -> print_relation_notes(app, name, relation, db)
    None -> Nil
  }
}

/// A field whose Gleam type is `String`: string, text, date or datetime.
fn is_plain_string(field_type: String) -> Bool {
  case field_type {
    "string" | "text" | "date" | "datetime" -> True
    _ -> False
  }
}

/// Notes for a `--belongs-to` resource that depend on the database.
fn print_relation_notes(
  app: String,
  name: String,
  relation: Relation,
  db: DbChoice,
) {
  io.println("")
  io.println(
    "Each of the "
    <> name
    <> " belongs to a "
    <> relation.singular
    <> " ("
    <> relation.field
    <> " REFERENCES "
    <> relation.table
    <> "(id) ON DELETE CASCADE): deleting a "
    <> relation.singular
    <> " deletes its "
    <> name
    <> ".",
  )
  case db {
    Sqlite -> {
      // SQLite enforces foreign keys only on connections that ask for it.
      // Repos generated since 0.6 turn them on in `delete`.
      let parent_repo =
        "src/" <> app <> "/data/" <> relation.singular <> "_repo.gleam"
      case simplifile.read(parent_repo) {
        Ok(content) ->
          case string.contains(content, "PRAGMA foreign_keys = ON") {
            True -> Nil
            False -> {
              io.println(
                "SQLite only enforces foreign keys (and ON DELETE CASCADE) when a connection",
              )
              io.println(
                "turns them on. Add this line to `delete` in "
                <> parent_repo
                <> ", after `use conn <- sqlight.with_connection(db_path)`:",
              )
              io.println(
                "  use _ <- result.try(sqlight.exec(\"PRAGMA foreign_keys = ON\", conn) |> result.replace_error(Nil))",
              )
            }
          }
        Error(_) -> Nil
      }
    }
    _ -> Nil
  }
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
  case project.detect_db() {
    NoDb -> {
      io.println("No database configured.")
      io.println(
        "gen auth stores users in a database. Create a project with --db postgres or --db sqlite.",
      )
    }
    db -> auth_with_db(db)
  }
}

/// The argus (Argon2) version range `gen auth` adds to gleam.toml.
const argus_requirement = ">= 2.0.0 and < 3.0.0"

fn auth_with_db(db: DbChoice) {
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
    #("src/" <> app <> "/data/user_repo.gleam", auth_user_repo(app, db)),
    #(
      "src/"
        <> app
        <> "/data/migrations/"
        <> next_migration_number(app)
        <> "_create_users.sql",
      auth_migration(db),
    ),
    #("src/" <> app <> "/web/forms/auth_form.gleam", auth_form(app)),
    #("src/" <> app <> "/web/auth_handler.gleam", auth_handler(app, db)),
    #("src/" <> app <> "/web/auth_views.gleam", auth_views(app)),
    #("src/" <> app <> "/web/session.gleam", auth_session(app)),
    #("src/" <> app <> "/web/middleware/auth.gleam", auth_middleware(app, db)),
    #("test/" <> app <> "/web/auth_handler_test.gleam", auth_test(app)),
    #("test/" <> app <> "/web/session_test.gleam", auth_session_test(app, db)),
  ]

  list.each(files, fn(file) {
    let #(path, content) = file
    let assert Ok(_) = simplifile.write(path, content)
  })

  // Passwords are hashed with Argon2 from the argus package
  let added_argus = project.add_dependency("argus", argus_requirement)

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
  case added_argus {
    True -> io.println("  gleam.toml (added argus for Argon2 password hashing)")
    False -> Nil
  }
}

// =============================================================================
// gen live
// =============================================================================

pub fn live(name: String) {
  let app = project.app_name()

  let live_dir = "src/" <> app <> "/web/live"
  let _ = simplifile.create_directory_all(live_dir)

  let component_path = live_dir <> "/" <> name <> ".gleam"
  let socket_path = live_dir <> "/" <> name <> "_socket.gleam"
  let handler_path = "src/" <> app <> "/web/" <> name <> "_live_handler.gleam"

  let assert Ok(_) = simplifile.write(component_path, live_component(app, name))
  let assert Ok(_) = simplifile.write(socket_path, live_socket(app, name))
  let assert Ok(_) = simplifile.write(handler_path, live_handler(app, name))

  // Patch router
  let _ = patch_router_live(app, name)
  let router_path = "src/" <> app <> "/router.gleam"
  format.format_files([component_path, socket_path, handler_path, router_path])

  io.println("")
  io.println("Created:")
  io.println("  " <> component_path)
  io.println("  " <> socket_path)
  io.println("  " <> handler_path)
  io.println("")
  io.println("Updated:")
  io.println("  " <> router_path)
  io.println("")
  io.println("The live component runs on the server and patches the DOM")
  io.println("over WebSocket. Visit /" <> name <> " to see it in action.")
}

fn live_component(_app: String, name: String) -> String {
  let type_name = capitalize(name)

  "/// " <> type_name <> " — a Lustre server component.
///
/// This component runs on the server. UI updates are sent to the
/// browser over WebSocket. The client runtime (~10kb) patches the DOM.
///
import gleam/int
import lustre
import lustre/effect
import lustre/element.{text}
import lustre/element/html.{button, div, h1, p}
import lustre/event

pub type Model {
  Model(count: Int)
}

pub type Msg {
  Increment
  Decrement
}

pub fn init(_flags: Nil) -> #(Model, effect.Effect(Msg)) {
  #(Model(count: 0), effect.none())
}

pub fn update(model: Model, msg: Msg) -> #(Model, effect.Effect(Msg)) {
  case msg {
    Increment -> #(Model(count: model.count + 1), effect.none())
    Decrement -> #(Model(count: model.count - 1), effect.none())
  }
}

pub fn view(model: Model) -> element.Element(Msg) {
  div([], [
    h1([], [text(\"" <> type_name <> "\")]),
    div([], [
      button([event.on_click(Decrement)], [text(\"-\")]),
      p([], [text(int.to_string(model.count))]),
      button([event.on_click(Increment)], [text(\"+\")]),
    ]),
  ])
}

/// Create a Lustre application for server-side rendering.
pub fn app() {
  lustre.application(init, update, view)
}
"
}

fn live_socket(app: String, name: String) -> String {
  "/// WebSocket transport for the " <> name <> " server component.
///
/// This module handles the WebSocket connection between the Lustre
/// server component and the browser client runtime.
///
/// ## Setup
///
/// 1. Add the WebSocket route to router.gleam. Because WebSocket
///    upgrades bypass Wisp, handle it before the Wisp handler in
///    your main module:
///
///    ```gleam
///    // In src/<app>.gleam, before the wisp_mist.handler:
///    import " <> app <> "/web/live/" <> name <> "_socket
///
///    // In the mist handler, check for WS upgrade:
///    fn handle(req) {
///      case request.path_segments(req) {
///        [\"" <> name <> "\", \"ws\"] -> " <> name <> "_socket.upgrade(req)
///        _ -> wisp_handler(req)
///      }
///    }
///    ```
///
/// 2. Start a Lustre factory supervisor in your main module to
///    manage server component instances.
///
/// See: https://hexdocs.pm/lustre/lustre/server_component.html
///
import gleam/erlang/process
import gleam/http/request.{type Request}
import gleam/http/response
import gleam/json
import gleam/option.{None}
import lustre/server_component
import mist.{type Connection, type ResponseData}

/// WebSocket connection state.
pub type State {
  State
}

/// Upgrade an HTTP request to a WebSocket for the server component.
pub fn upgrade(
  req: Request(Connection),
) -> response.Response(ResponseData) {
  mist.websocket(
    request: req,
    handler: fn(state, msg, conn) {
      case msg {
        mist.Text(text) -> {
          // Decode event from client and dispatch to server runtime
          // TODO: wire to your Lustre runtime Subject
          // case json.parse(text, server_component.runtime_message_decoder()) {
          //   Ok(runtime_msg) -> process.send(runtime, runtime_msg)
          //   Error(_) -> Nil
          // }
          mist.continue(state)
        }
        mist.Binary(_) -> mist.continue(state)
        mist.Custom(_) -> mist.continue(state)
        mist.Closed | mist.Shutdown -> mist.stop()
      }
    },
    on_init: fn(_conn) {
      // TODO: Start a Lustre server component instance here.
      // Use lustre.supervised() or lustre.factory() to create
      // a managed runtime, then register a callback to send
      // patches over the WebSocket:
      //
      // server_component.register_callback(fn(msg) {
      //   let patch = server_component.client_message_to_json(msg)
      //   mist.send_text_frame(conn, json.to_string(patch))
      // })
      #(State, None)
    },
    on_close: fn(_state) { Nil },
  )
}
"
}

fn live_handler(app: String, name: String) -> String {
  let type_name = capitalize(name)

  "/// Handler for the " <> name <> " live page.
///
/// Serves the HTML shell that mounts the Lustre server component
/// via the <lustre-server-component> custom element over WebSocket.
///
import " <> app <> "/context.{type Context}
import " <> app <> "/web/layouts/root_layout
import lustre/attribute
import lustre/element.{text}
import lustre/element/html.{div, section}
import lustre/server_component
import wisp.{type Request, type Response}

pub fn index(_req: Request, _ctx: Context) -> Response {
  section([], [
    // Inline the Lustre server component client runtime
    server_component.script(),
    // Mount the server component, connecting via WebSocket
    server_component.element(
      [
        server_component.route(\"/" <> name <> "/ws\"),
        server_component.method(server_component.WebSocket),
      ],
      [text(\"Loading " <> type_name <> "...\")],
    ),
  ])
  |> root_layout.wrap(\"" <> type_name <> "\")
  |> wisp.html_response(200)
}
"
}

fn patch_router_live(app: String, name: String) {
  let router_path = "src/" <> app <> "/router.gleam"
  let assert Ok(content) = simplifile.read(router_path)

  let handler_import = "import " <> app <> "/web/" <> name <> "_live_handler"
  let content = add_import(content, handler_import)

  let socket_import = "import " <> app <> "/web/live/" <> name <> "_socket"
  let content = add_import(content, socket_import)

  let routes =
    "\n    [\""
    <> name
    <> "\"], http.Get -> "
    <> name
    <> "_live_handler.index(req, ctx)"

  let content = add_route(content, routes)
  let assert Ok(_) = simplifile.write(router_path, content)
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

// --api resources -------------------------------------------------------------
//
// An --api resource answers JSON under /api/<plural>. Its params module
// (web/forms/<singular>_form.gleam) decodes and validates the request body
// with the same checks the HTML form's `decode` runs; the handler maps the
// outcome to a status code.

/// The `gleam/dynamic/decode` decoder for one field of a JSON body.
fn api_field_decoder(field_type: String) -> String {
  case is_optional(field_type) {
    True ->
      "decode.optional("
      <> plain_api_field_decoder(base_type(field_type))
      <> ")"
    False -> plain_api_field_decoder(field_type)
  }
}

fn plain_api_field_decoder(field_type: String) -> String {
  case field_type {
    "int" -> "decode.int"
    "float" -> "float_or_int()"
    "bool" -> "decode.bool"
    _ -> "decode.string"
  }
}

/// The `gleam/json` function that encodes one field of a record.
fn api_field_encoder(field_type: String) -> String {
  case field_type {
    "int" -> "json.int"
    "float" -> "json.float"
    "bool" -> "json.bool"
    _ -> "json.string"
  }
}

/// A valid JSON value for a field, for generated tests.
fn api_sample_json(field_type: String) -> String {
  case base_type(field_type) {
    "int" -> "json.int(42)"
    "float" -> "json.float(3.14)"
    "bool" -> "json.bool(True)"
    _ -> "json.string(\"test value\")"
  }
}

/// A JSON value of the wrong type for a field, for generated tests.
fn api_wrong_json(field_type: String) -> String {
  case base_type(field_type) {
    "int" | "float" -> "json.string(\"not a number\")"
    "bool" -> "json.string(\"not a bool\")"
    _ -> "json.int(42)"
  }
}

/// The fields the HTML form's `decode` requires: string and text.
fn api_required_fields(
  fields: List(#(String, String)),
) -> List(#(String, String)) {
  list.filter(fields, fn(f) { f.1 == "string" || f.1 == "text" })
}

fn api_params_module(
  type_name: String,
  fields: List(#(String, String)),
) -> String {
  let params = type_name <> "Params"
  let required = api_required_fields(fields)
  let has_float = list.any(fields, fn(f) { base_type(f.1) == "float" })
  let has_optional = list.any(fields, fn(f) { is_optional(f.1) })

  let imports =
    ["import gleam/dynamic.{type Dynamic}", "import gleam/dynamic/decode"]
    |> append_if(has_float, "import gleam/int")
    |> append_if(has_optional, "import gleam/option.{type Option, None}")
    |> append_if(required != [], "import refrakt/validate")
    |> string.join("\n")

  let params_field_defs =
    fields
    |> list.map(fn(f) {
      let #(name, ft) = f
      "    " <> name <> ": " <> to_gleam_type(ft) <> ","
    })
    |> string.join("\n")

  let decoder_lines =
    fields
    |> list.map(fn(f) {
      let #(name, field_type) = f
      "  use "
      <> name
      <> " <- decode.optional_field(\""
      <> name
      <> "\", "
      <> form_default_value(field_type)
      <> ", "
      <> api_field_decoder(field_type)
      <> ")"
    })
    |> string.join("\n")

  let constructor_args =
    fields
    |> list.map(fn(f) { f.0 <> ":" })
    |> string.join(", ")

  let validate_fn = case required {
    [] -> "/// The HTML form's `decode` has no checks for these field types; add
/// your own with `refrakt/validate`. Errors are `#(field, message)` pairs.
pub fn validate_params(_params: " <> params <> ") -> List(#(String, String)) {
  []
}"
    _ ->
      "/// The checks the HTML form's `decode` runs: string and text fields are
/// required. Errors are `#(field, message)` pairs.
pub fn validate_params(params: " <> params <> ") -> List(#(String, String)) {
  []
" <> {
        required
        |> list.map(fn(f) {
          "  |> validate.required(params."
          <> f.0
          <> ", \""
          <> f.0
          <> "\", \""
          <> capitalize(f.0)
          <> " is required\")"
        })
        |> string.join("\n")
      } <> "
}"
  }

  let float_or_int = case has_float {
    True ->
      "

/// JSON has a single number type: accept `4` as well as `4.0`.
fn float_or_int() -> decode.Decoder(Float) {
  decode.one_of(decode.float, [decode.int |> decode.map(int.to_float)])
}"
    False -> ""
  }

  "//// JSON params for " <> type_name <> " (API mode).
////
//// `decode_json` turns the body `wisp.require_json` hands a handler into
//// validated " <> params <> ", with the same checks the HTML form's `decode`
//// runs.

" <> imports <> "

pub type " <> params <> " {
  " <> params <> "(
" <> params_field_defs <> "
  )
}

/// Why a JSON body could not become " <> params <> ".
pub type JsonError {
  /// The body is not an object whose fields have the expected types.
  /// Handlers answer 400 Bad Request.
  MalformedBody(errors: List(decode.DecodeError))
  /// The body has the expected shape but fails validation.
  /// Handlers answer 422 Unprocessable Content.
  InvalidParams(errors: List(#(String, String)))
}

/// Decode a JSON body and validate it.
pub fn decode_json(data: Dynamic) -> Result(" <> params <> ", JsonError) {
  case decode.run(data, decoder()) {
    Error(errors) -> Error(MalformedBody(errors))
    Ok(params) ->
      case validate_params(params) {
        [] -> Ok(params)
        errors -> Error(InvalidParams(errors))
      }
  }
}

/// The JSON shape of " <> params <> ". A missing field gets the value an
/// empty HTML form field would (`\"\"`, `0`, `0.0`, `false`); `null` or a
/// value of the wrong type fails decoding. An optional field may be
/// missing or `null`, and is then `None`.
pub fn decoder() -> decode.Decoder(" <> params <> ") {
" <> decoder_lines <> "
  decode.success(" <> params <> "(" <> constructor_args <> "))
}

" <> validate_fn <> float_or_int <> "
"
}

fn api_resource_handler(
  app_name: String,
  resource_plural: String,
  resource_singular: String,
  type_name: String,
  db: DbChoice,
  fields: List(#(String, String)),
  relation: Option(Relation),
) -> String {
  let db_arg = case db {
    Sqlite -> "ctx.db_path"
    _ -> "ctx.db"
  }
  let repo = resource_singular <> "_repo"
  let form = resource_singular <> "_form"

  let json_fields =
    fields
    |> list.map(fn(f) {
      let #(name, field_type) = f
      let value = case is_optional(field_type) {
        // None is encoded as null
        True ->
          "json.nullable(item."
          <> name
          <> ", "
          <> api_field_encoder(base_type(field_type))
          <> ")"
        False -> api_field_encoder(field_type) <> "(item." <> name <> ")"
      }
      "    #(\"" <> name <> "\", " <> value <> "),"
    })
    |> string.join("\n")

  let update_call =
    "case " <> repo <> ".update(" <> db_arg <> ", item.id, params) {
            Ok(item) -> json_response(to_json(item), 200)
            Error(_) -> internal_error()
          }"

  // --belongs-to: a body whose parent id has no row is a 422
  let #(check_create, update_record, parent_import, check_fn) = case relation {
    None -> #("", "\n          " <> update_call, "", "")
    Some(relation) -> {
      let check = "check_" <> relation.singular
      #("\n    |> result.try(" <> check <> "(ctx, _))", "
          case " <> check <> "(ctx, params) {
            Error(error) -> invalid_body(error)
            Ok(params) ->
              " <> update_call <> "
          }", "\nimport "
        <> app_name
        <> "/data/"
        <> relation.singular
        <> "_repo", "

/// The " <> relation.singular <> " a " <> resource_singular <> " belongs to must exist.
fn " <> check <> "(
  ctx: Context,
  params: " <> form <> "." <> type_name <> "Params,
) -> Result(" <> form <> "." <> type_name <> "Params, " <> form <> ".JsonError) {
  case " <> relation.singular <> "_repo.get(" <> db_arg <> ", params." <> relation.field <> ") {
    Ok(_) -> Ok(params)
    Error(_) ->
      Error(
        " <> form <> ".InvalidParams([
          #(\"" <> relation.field <> "\", \"" <> relation.type_name <> " does not exist\"),
        ]),
      )
  }
}")
    }
  }

  "//// JSON API for "
  <> resource_plural
  <> ", routed under /api/"
  <> resource_plural
  <> ".
////
//// Errors are JSON too: 404 `{\"error\": \"not found\"}`, 400 for a body
//// whose fields have the wrong types, and 422
//// `{\"errors\": {\"field\": \"message\"}}` when validation fails. A body
//// that is not JSON at all is rejected by `wisp.require_json` (400), as is
//// a content type other than application/json (415).

import gleam/dynamic/decode
import gleam/http/response
import gleam/int
import gleam/json
import gleam/list
import gleam/result
import gleam/string
import "
  <> app_name
  <> "/context.{type Context}
import "
  <> app_name
  <> "/data/"
  <> repo
  <> parent_import
  <> "
import "
  <> app_name
  <> "/domain/"
  <> resource_singular
  <> ".{type "
  <> type_name
  <> "}
import "
  <> app_name
  <> "/web/forms/"
  <> form
  <> "
import wisp.{type Request, type Response}

pub fn index(_req: Request, ctx: Context) -> Response {
  "
  <> repo
  <> ".list("
  <> db_arg
  <> ")
  |> json.array(to_json)
  |> json_response(200)
}

pub fn show(_req: Request, ctx: Context, id: String) -> Response {
  case find(ctx, id) {
    Error(_) -> not_found()
    Ok(item) -> json_response(to_json(item), 200)
  }
}

pub fn create(req: Request, ctx: Context) -> Response {
  use body <- wisp.require_json(req)

  case "
  <> form
  <> ".decode_json(body)"
  <> check_create
  <> " {
    Error(error) -> invalid_body(error)
    Ok(params) ->
      case "
  <> repo
  <> ".create("
  <> db_arg
  <> ", params) {
        Ok(item) ->
          json_response(to_json(item), 201)
          |> response.set_header(
            \"location\",
            \"/api/"
  <> resource_plural
  <> "/\" <> int.to_string(item.id),
          )
        Error(_) -> internal_error()
      }
  }
}

/// The body is checked before the record is looked up, so a bad body
/// gets 400 or 422 even when the id is unknown.
pub fn update(req: Request, ctx: Context, id: String) -> Response {
  use body <- wisp.require_json(req)

  case "
  <> form
  <> ".decode_json(body) {
    Error(error) -> invalid_body(error)
    Ok(params) ->
      case find(ctx, id) {
        Error(_) -> not_found()
        Ok(item) ->"
  <> update_record
  <> "
      }
  }
}

pub fn delete(_req: Request, ctx: Context, id: String) -> Response {
  case find(ctx, id) {
    Error(_) -> not_found()
    Ok(item) ->
      case "
  <> repo
  <> ".delete("
  <> db_arg
  <> ", item.id) {
        Ok(_) -> wisp.no_content()
        Error(_) -> internal_error()
      }
  }
}

/// Look up a record by the id from the path. An id that is not a number
/// is as unknown as one without a row.
fn find(ctx: Context, id: String) -> Result("
  <> type_name
  <> ", Nil) {
  use id <- result.try(int.parse(id))
  "
  <> repo
  <> ".get("
  <> db_arg
  <> ", id)
}

fn to_json(item: "
  <> type_name
  <> ") -> json.Json {
  json.object([
    #(\"id\", json.int(item.id)),
"
  <> json_fields
  <> "
  ])
}

fn json_response(data: json.Json, status: Int) -> Response {
  data
  |> json.to_string
  |> wisp.json_response(status)
}

/// 400 with what did not decode, or 422 with a message per invalid field.
fn invalid_body(error: "
  <> form
  <> ".JsonError) -> Response {
  case error {
    "
  <> form
  <> ".MalformedBody(errors) ->
      json.object([
        #(\"error\", json.string(\"invalid request body\")),
        #(\"details\", json.array(errors, decode_error_to_json)),
      ])
      |> json_response(400)
    "
  <> form
  <> ".InvalidParams(errors) ->
      json.object([
        #(
          \"errors\",
          json.object(
            list.map(errors, fn(error) { #(error.0, json.string(error.1)) }),
          ),
        ),
      ])
      |> json_response(422)
  }
}

fn decode_error_to_json(error: decode.DecodeError) -> json.Json {
  json.object([
    #(\"path\", json.string(string.join(error.path, \".\"))),
    #(\"expected\", json.string(error.expected)),
    #(\"found\", json.string(error.found)),
  ])
}

fn not_found() -> Response {
  json.object([#(\"error\", json.string(\"not found\"))])
  |> json_response(404)
}

fn internal_error() -> Response {
  json.object([#(\"error\", json.string(\"internal server error\"))])
  |> json_response(500)
}"
  <> check_fn
  <> "
"
}

// --belongs-to: children on the parent's show page ---------------------------

/// What `generate_children` wrote: the component, and the parent handler
/// it patched or the instructions to wire the component in by hand.
type Children {
  Children(
    component_path: String,
    patched: Option(String),
    instructions: List(String),
  )
}

/// Write `web/components/<child>_list.gleam` and render it on the parent's
/// show page. The parent's handler is patched only when its `show` still
/// renders `<parent>_views.show_view(item)` exactly once, as generated;
/// otherwise the CLI prints what to add.
fn generate_children(
  app: String,
  plural: String,
  singular: String,
  type_name: String,
  fields: List(#(String, String)),
  relation: Relation,
  db: DbChoice,
) -> Children {
  let component_path =
    "src/" <> app <> "/web/components/" <> singular <> "_list.gleam"
  ensure_dir_for(component_path)
  let assert Ok(_) =
    simplifile.write(
      component_path,
      children_component(app, plural, singular, type_name, fields, relation),
    )

  let db_arg = case db {
    Sqlite -> "ctx.db_path"
    _ -> "ctx.db"
  }
  let render_call =
    singular
    <> "_list.render(item.id, "
    <> singular
    <> "_repo.list_for_"
    <> relation.singular
    <> "("
    <> db_arg
    <> ", item.id))"
  let parent_handler =
    "src/" <> app <> "/web/" <> relation.singular <> "_handler.gleam"
  let show_call = relation.singular <> "_views.show_view(item)"
  let repo_import = "import " <> app <> "/data/" <> singular <> "_repo"
  let component_import =
    "import " <> app <> "/web/components/" <> singular <> "_list"

  let patched = {
    use content <- result.try(
      simplifile.read(parent_handler) |> result.replace_error(Nil),
    )
    use content <- result.try(patch_parent_show(content, show_call, render_call))
    let content = case imports_lustre_element(content) {
      True -> content
      False -> add_import(content, "import lustre/element")
    }
    let content =
      content
      |> add_import(repo_import)
      |> add_import(component_import)
    simplifile.write(parent_handler, content) |> result.replace_error(Nil)
  }

  case patched {
    Ok(_) -> Children(component_path, Some(parent_handler), [])
    Error(_) ->
      Children(component_path, None, [
        "To list the "
          <> plural
          <> " on a "
          <> relation.singular
          <> "'s page, render the component in `show` of "
          <> parent_handler
          <> ":",
        "",
        "  import lustre/element",
        "  " <> repo_import,
        "  " <> component_import,
        "",
        "  element.fragment([",
        "    " <> show_call <> ",",
        "    " <> render_call <> ",",
        "  ])",
      ])
  }
}

/// Render `render_call` after the parent's show view: wrap the generated
/// `show_view(item)` in an `element.fragment`, or add to the fragment an
/// earlier `--belongs-to` child made.
fn patch_parent_show(
  content: String,
  show_call: String,
  render_call: String,
) -> Result(String, Nil) {
  case string.contains(content, render_call) {
    True -> Ok(content)
    False ->
      case string.split(content, show_call <> ",\n") {
        [before, after] ->
          Ok(before <> show_call <> ",\n" <> render_call <> ",\n" <> after)
        _ ->
          case string.split(content, show_call <> "\n") {
            [before, after] ->
              Ok(
                before
                <> "element.fragment([\n"
                <> show_call
                <> ",\n"
                <> render_call
                <> ",\n])\n"
                <> after,
              )
            _ -> Error(Nil)
          }
      }
  }
}

/// Whether a module imports `lustre/element` itself (not only a submodule
/// such as `lustre/element/html`).
fn imports_lustre_element(content: String) -> Bool {
  content
  |> string.split("\n")
  |> list.any(fn(line) {
    line == "import lustre/element"
    || string.starts_with(line, "import lustre/element.{")
    || string.starts_with(line, "import lustre/element as ")
  })
}

fn children_component(
  app: String,
  plural: String,
  singular: String,
  type_name: String,
  fields: List(#(String, String)),
  relation: Relation,
) -> String {
  let label = case list.find(fields, fn(f) { is_plain_string(f.1) }) {
    Ok(#(name, _)) -> "item." <> name
    Error(_) -> "\"" <> type_name <> " #\" <> int.to_string(item.id)"
  }
  let parent_id = relation.field

  "//// The "
  <> plural
  <> " of a "
  <> relation.singular
  <> ", for the "
  <> relation.singular
  <> "'s show page.
////
//// `gen resource "
  <> plural
  <> " --belongs-to "
  <> relation.plural
  <> "` renders it in `show` of
//// web/"
  <> relation.singular
  <> "_handler.gleam, after the "
  <> relation.singular
  <> ":
////
////     "
  <> singular
  <> "_list.render(item.id, "
  <> singular
  <> "_repo.list_for_"
  <> relation.singular
  <> "(db, item.id))

import gleam/int
import gleam/list
import "
  <> app
  <> "/domain/"
  <> singular
  <> ".{type "
  <> type_name
  <> "}
import lustre/attribute.{class, href}
import lustre/element.{type Element, text}
import lustre/element/html.{a, h2, li, p, section, ul}

pub fn render("
  <> parent_id
  <> ": Int, items: List("
  <> type_name
  <> ")) -> Element(Nil) {
  section([class(\""
  <> plural
  <> "\")], [
    h2([], [text(\""
  <> capitalize(plural)
  <> "\")]),
    case items {
      [] -> p([], [text(\"No "
  <> plural
  <> " yet.\")])
      _ ->
        ul(
          [],
          list.map(items, fn(item) {
            li([], [
              a([href(\"/"
  <> plural
  <> "/\" <> int.to_string(item.id))], [
                text("
  <> label
  <> "),
              ]),
            ])
          }),
        )
    },
    // /"
  <> plural
  <> "/new?"
  <> parent_id
  <> "=<id> preselects the "
  <> relation.singular
  <> " in the form
    a(
      [
        href(\"/"
  <> plural
  <> "/new?"
  <> parent_id
  <> "=\" <> int.to_string("
  <> parent_id
  <> ")),
        class(\"btn\"),
      ],
      [text(\"New "
  <> type_name
  <> "\")],
    ),
  ])
}
"
}

fn resource_views(
  app_name: String,
  resource_plural: String,
  resource_singular: String,
  type_name: String,
  fields: List(#(String, String)),
  relation: Option(Relation),
) -> String {
  let is_relation = fn(field_name: String) {
    case relation {
      Some(relation) -> relation.field == field_name
      None -> False
    }
  }

  let form_field_elements =
    fields
    |> list.map(fn(f) {
      case relation {
        Some(relation) if relation.field == f.0 -> relation_select(relation)
        _ -> form_field_element(f)
      }
    })
    |> string.join("\n")

  let show_field_elements =
    fields
    |> list.map(fn(f) {
      let #(fname, _) = f
      let #(label_text, value) = case relation {
        Some(relation) if relation.field == fname -> #(
          relation.type_name,
          "a([href(\"/"
            <> relation.plural
            <> "/\" <> int.to_string(item."
            <> fname
            <> "))], [text(\""
            <> relation.type_name
            <> " #\" <> int.to_string(item."
            <> fname
            <> "))])",
        )
        _ -> #(capitalize(fname), "text(" <> show_value(f) <> ")")
      }
      "      dt([], [text(\"" <> label_text <> "\")]),
      dd([], [" <> value <> "]),"
    })
    |> string.join("\n")

  let float_import = case
    list.any(fields, fn(f) { base_type(f.1) == "float" })
  {
    True -> "\nimport gleam/float"
    False -> ""
  }

  // Import only what the field elements use: an unused import would be
  // a warning in the generated module. `text` fields render a textarea,
  // optional bools and the --belongs-to field a select, every other type
  // an input; all but text fields and checkboxes set a value.
  let uses = fn(predicate: fn(#(String, String)) -> Bool) {
    list.any(fields, predicate)
  }
  let renders_input = fn(f: #(String, String)) {
    let #(fname, ftype) = f
    base_type(ftype) != "text"
    && ftype != "optional(bool)"
    && !is_relation(fname)
  }
  let attribute_imports =
    ["class", "href", "name"]
    |> append_if(uses(fn(f) { base_type(f.1) == "float" }), "step")
    |> list.append(["type_"])
    |> append_if(
      uses(fn(f) { base_type(f.1) != "text" && f.1 != "bool" }),
      "value",
    )
  let html_imports =
    ["a", "button", "dd", "div", "dl", "dt", "form", "h1"]
    |> append_if(uses(renders_input), "input")
    |> list.append(["label", "li", "p", "section"])
    |> append_if(uses(fn(f) { base_type(f.1) == "text" }), "textarea")
    |> list.append(["ul"])

  let options_param = case relation {
    Some(relation) ->
      "\n  " <> relation.singular <> "_options: List(#(Int, String)),"
    None -> ""
  }

  // index_view and show_view label a record with its first required
  // string field, or with its id
  let show_title = case list.find(fields, fn(f) { is_plain_string(f.1) }) {
    Ok(#(name, _)) -> "item." <> name
    Error(_) -> "\"" <> type_name <> " #\" <> int.to_string(item.id)"
  }

  "import gleam/int" <> float_import <> "
import gleam/list
import gleam/option
import lustre/attribute.{" <> string.join(attribute_imports, ", ") <> "}
import lustre/element.{type Element, text}
import lustre/element/html.{" <> string.join(html_imports, ", ") <> "}
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
            text(" <> show_title <> "),
          ]),
        ])
      }),
    ),
  ])
}

pub fn show_view(item: " <> type_name <> ") -> Element(Nil) {
  section([class(\"" <> resource_singular <> "\")], [
    h1([], [text(" <> show_title <> ")]),
    // Fields without a value (None) show as an em dash
    dl([], [
" <> show_field_elements <> "
    ]),
    div([class(\"actions\")], [
      a(
        [
          href(\"/" <> resource_plural <> "/\" <> int.to_string(item.id) <> \"/edit\"),
          class(\"btn\"),
        ],
        [text(\"Edit\")],
      ),
      // wisp.method_override reads the method from the _method query
      // parameter of a POST, so this form sends a DELETE.
      form(
        [
          attribute.action(
            \"/" <> resource_plural <> "/\" <> int.to_string(item.id) <> \"?_method=DELETE\",
          ),
          attribute.method(\"post\"),
        ],
        [button([type_(\"submit\"), class(\"btn\")], [text(\"Delete\")])],
      ),
    ]),
  ])
}

pub fn form_view(
  values: " <> resource_singular <> "_form." <> type_name <> "Form,
  errors: List(#(String, String))," <> options_param <> "
) -> Element(Nil) {
  // Updates are sent as POST /<id>?_method=PUT: wisp.method_override
  // reads the method from the _method query parameter.
  let post_action = case values.id {
    option.Some(id) -> \"/" <> resource_plural <> "/\" <> int.to_string(id) <> \"?_method=PUT\"
    option.None -> \"/" <> resource_plural <> "\"
  }

  section([class(\"" <> resource_singular <> "-form\")], [
    h1([], [text(case values.id {
      option.Some(_) -> \"Edit " <> type_name <> "\"
      option.None -> \"New " <> type_name <> "\"
    })]),
    form([attribute.action(post_action), attribute.method(\"post\")], [
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

/// The form element for one field. An optional field renders `None` as
/// an empty value; an optional bool is a select (blank, Yes, No), since a
/// checkbox cannot say "not set".
fn form_field_element(field: #(String, String)) -> String {
  let #(fname, ftype) = field
  let label_text = capitalize(fname)
  let labelled = fn(control: String) { "      div([class(\"field\")], [
        label([], [text(\"" <> label_text <> "\")]),
        " <> control <> ",
        field_error(errors, \"" <> fname <> "\"),
      ])," }
  let input = fn(input_type: String, extra: String, shown: String) {
    "input([type_(\""
    <> input_type
    <> "\"), name(\""
    <> fname
    <> "\"), "
    <> extra
    <> "value("
    <> shown
    <> ")])"
  }
  let optional_value = fn(to_string: String) {
    "values."
    <> fname
    <> " |> option.map("
    <> to_string
    <> ") |> option.unwrap(\"\")"
  }
  case ftype {
    "bool" -> "      div([class(\"field\")], [
        label([], [
          input([type_(\"checkbox\"), name(\"" <> fname <> "\"), attribute.checked(values." <> fname <> ")]),
          text(\" " <> label_text <> "\"),
        ]),
      ]),"
    "text" ->
      labelled("textarea([name(\"" <> fname <> "\")], values." <> fname <> ")")
    "int" ->
      labelled(input("number", "", "int.to_string(values." <> fname <> ")"))
    "float" ->
      labelled(input(
        "number",
        "step(\"any\"), ",
        "float.to_string(values." <> fname <> ")",
      ))
    "optional(bool)" -> labelled("html.select([name(\"" <> fname <> "\")], [
          html.option([value(\"\"), attribute.selected(values." <> fname <> " == option.None)], \"—\"),
          html.option([value(\"true\"), attribute.selected(values." <> fname <> " == option.Some(True))], \"Yes\"),
          html.option([value(\"false\"), attribute.selected(values." <> fname <> " == option.Some(False))], \"No\"),
        ])")
    "optional(text)" ->
      labelled(
        "textarea([name(\""
        <> fname
        <> "\")], option.unwrap(values."
        <> fname
        <> ", \"\"))",
      )
    "optional(int)" ->
      labelled(input("number", "", optional_value("int.to_string")))
    "optional(float)" ->
      labelled(input(
        "number",
        "step(\"any\"), ",
        optional_value("float.to_string"),
      ))
    "optional(" <> _ ->
      labelled(input("text", "", "option.unwrap(values." <> fname <> ", \"\")"))
    _ -> labelled(input("text", "", "values." <> fname))
  }
}

/// The `--belongs-to` field: a select of the parents, labelled by the
/// parent's first string field (or its id).
fn relation_select(relation: Relation) -> String {
  let fname = relation.field
  "      div([class(\"field\")], [
        label([], [text(\"" <> relation.type_name <> "\")]),
        html.select([name(\"" <> fname <> "\")], [
          html.option([value(\"\")], \"Choose a " <> relation.singular <> "\"),
          ..list.map(" <> relation.singular <> "_options, fn(choice) {
            html.option(
              [
                value(int.to_string(choice.0)),
                attribute.selected(choice.0 == values." <> fname <> "),
              ],
              choice.1,
            )
          })
        ]),
        field_error(errors, \"" <> fname <> "\"),
      ]),"
}

/// The text the show view renders for a field; `None` is an em dash.
fn show_value(field: #(String, String)) -> String {
  let #(fname, ftype) = field
  let value = "item." <> fname
  case ftype {
    "int" -> "int.to_string(" <> value <> ")"
    "float" -> "float.to_string(" <> value <> ")"
    "bool" -> "case " <> value <> " {
          True -> \"Yes\"
          False -> \"No\"
        }"
    "optional(int)" ->
      value <> " |> option.map(int.to_string) |> option.unwrap(\"—\")"
    "optional(float)" ->
      value <> " |> option.map(float.to_string) |> option.unwrap(\"—\")"
    "optional(bool)" -> "case " <> value <> " {
          option.Some(True) -> \"Yes\"
          option.Some(False) -> \"No\"
          option.None -> \"—\"
        }"
    "optional(" <> _ -> "option.unwrap(" <> value <> ", \"—\")"
    _ -> value
  }
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
      let value = "get_value(data, \"" <> field_name <> "\")"
      "    "
      <> field_name
      <> ": "
      <> case field_type {
        "bool" ->
          "list.any(data.values, fn(v) { v.0 == \"" <> field_name <> "\" })"
        "int" -> "result.unwrap(int.parse(" <> value <> "), 0)"
        "float" -> "result.unwrap(parse_float(" <> value <> "), 0.0)"
        _ ->
          case is_optional(field_type) {
            True ->
              "optional(" <> value <> ", " <> optional_parser(field_type) <> ")"
            False -> value
          }
      }
      <> ","
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

  // string and text fields are required; an optional field may be blank,
  // but a number or bool it holds must parse
  let validation_lines =
    fields
    |> list.filter_map(fn(f) {
      let #(name, t) = f
      let label = capitalize(name)
      case t {
        "string" | "text" ->
          Ok(
            "    |> validate.required("
            <> name
            <> ", \""
            <> name
            <> "\", \""
            <> label
            <> " is required\")",
          )
        "optional(int)" | "optional(float)" | "optional(bool)" ->
          Ok(
            "    |> must_parse("
            <> name
            <> ", "
            <> optional_parser(t)
            <> ", \""
            <> name
            <> "\", \""
            <> label
            <> case t {
              "optional(int)" -> " must be a whole number"
              "optional(float)" -> " must be a number"
              _ -> " must be yes or no"
            }
            <> "\")",
          )
        _ -> Error(Nil)
      }
    })
    |> string.join("\n")

  let params_construction =
    fields
    |> list.map(fn(f) {
      let #(name, t) = f
      "        "
      <> name
      <> ": "
      <> case t {
        "bool" -> "list.any(data.values, fn(v) { v.0 == \"" <> name <> "\" })"
        "int" -> "result.unwrap(int.parse(" <> name <> "), 0)"
        "float" -> "result.unwrap(parse_float(" <> name <> "), 0.0)"
        _ ->
          case is_optional(t) {
            True -> "optional(" <> name <> ", " <> optional_parser(t) <> ")"
            False -> name
          }
      }
      <> ","
    })
    |> string.join("\n")

  let has = fn(predicate: fn(String) -> Bool) {
    list.any(fields, fn(f) { predicate(f.1) })
  }
  let validate_import = case has(fn(t) { t == "string" || t == "text" }) {
    True -> "\nimport refrakt/validate"
    False -> ""
  }
  let has_float = has(fn(t) { base_type(t) == "float" })
  let has_optional = has(is_optional)
  let has_must_parse =
    has(fn(t) {
      t == "optional(int)" || t == "optional(float)" || t == "optional(bool)"
    })

  let extra_imports =
    []
    |> append_if(
      has(fn(t) { base_type(t) == "int" }) || has_float,
      "import gleam/int",
    )
    |> append_if(has_float, "import gleam/float")
    |> append_if(has_optional, "import gleam/string")
    |> list.map(fn(line) { "\n" <> line })
    |> string.concat

  // Helpers, only those the fields use (an unused function is a warning)
  let helpers =
    []
    |> append_if(
      has_optional,
      "
/// An optional field: blank is `None`, anything else is parsed (a value
/// that does not parse is `None` too; `decode` reports it with
/// `must_parse`).
fn optional(value: String, parse: fn(String) -> Result(a, Nil)) -> Option(a) {
  case string.trim(value) {
    \"\" -> None
    trimmed -> option.from_result(parse(trimmed))
  }
}",
    )
    |> append_if(
      has_must_parse,
      "
/// Add an error when an optional field is not blank and does not parse.
fn must_parse(
  errors: List(#(String, String)),
  value: String,
  parse: fn(String) -> Result(a, Nil),
  field: String,
  message: String,
) -> List(#(String, String)) {
  case string.trim(value) {
    \"\" -> errors
    trimmed ->
      case parse(trimmed) {
        Ok(_) -> errors
        Error(_) -> [#(field, message), ..errors]
      }
  }
}",
    )
    |> append_if(
      has_float,
      "
/// Parse a float, accepting whole numbers (`4`) as well as `4.0`.
fn parse_float(value: String) -> Result(Float, Nil) {
  case float.parse(value) {
    Ok(number) -> Ok(number)
    Error(_) -> int.parse(value) |> result.map(int.to_float)
  }
}",
    )
    |> append_if(
      has(fn(t) { t == "optional(bool)" }),
      "
/// The values of an optional bool's select: blank, `true` or `false`.
fn parse_bool(value: String) -> Result(Bool, Nil) {
  case value {
    \"true\" -> Ok(True)
    \"false\" -> Ok(False)
    _ -> Error(Nil)
  }
}",
    )
    |> string.concat

  "import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result" <> extra_imports <> "
import " <> app_name <> "/domain/" <> resource_singular <> ".{type " <> type_name <> "}" <> validate_import <> "
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
" <> helpers
}

/// The parser `optional` and `must_parse` use for an optional field.
fn optional_parser(field_type: String) -> String {
  case base_type(field_type) {
    "int" -> "int.parse"
    "float" -> "parse_float"
    "bool" -> "parse_bool"
    _ -> "Ok"
  }
}

fn resource_repo(
  app_name: String,
  resource_singular: String,
  type_name: String,
  fields: List(#(String, String)),
  db: DbChoice,
  relation: Option(Relation),
  with_options: Bool,
) -> String {
  let #(repo, relation_functions) = case db {
    Sqlite | NoDb -> #(
      resource_repo_sqlite(app_name, resource_singular, type_name, fields),
      relation_functions_sqlite,
    )
    Postgres -> #(
      resource_repo_pog(app_name, resource_singular, type_name, fields),
      relation_functions_pog,
    )
  }
  case relation {
    None -> repo
    Some(relation) ->
      repo
      <> relation_functions(
        resource_singular,
        type_name,
        fields,
        relation,
        with_options,
      )
  }
}

/// The Sqlight decoder for one column.
fn sqlite_decoder(field_type: String) -> String {
  let decoder = case base_type(field_type) {
    "bool" -> "sqlight.decode_bool()"
    "int" -> "decode.int"
    "float" -> "decode.float"
    _ -> "decode.string"
  }
  case is_optional(field_type) {
    True -> "decode.optional(" <> decoder <> ")"
    False -> decoder
  }
}

/// The Sqlight parameter for one field of the params.
fn sqlite_parameter(name: String, field_type: String) -> String {
  let encoder = case base_type(field_type) {
    "bool" -> "sqlight.bool"
    "int" -> "sqlight.int"
    "float" -> "sqlight.float"
    _ -> "sqlight.text"
  }
  case is_optional(field_type) {
    // None is NULL
    True -> "sqlight.nullable(" <> encoder <> ", params." <> name <> ")"
    False -> encoder <> "(params." <> name <> ")"
  }
}

/// The Pog decoder for one column.
fn pog_decoder(field_type: String) -> String {
  let decoder = case base_type(field_type) {
    "bool" -> "decode.bool"
    "int" -> "decode.int"
    "float" -> "decode.float"
    _ -> "decode.string"
  }
  case is_optional(field_type) {
    True -> "decode.optional(" <> decoder <> ")"
    False -> decoder
  }
}

/// The Pog parameter for one field of the params.
fn pog_parameter(name: String, field_type: String) -> String {
  let encoder = case base_type(field_type) {
    "bool" -> "pog.bool"
    "int" -> "pog.int"
    "float" -> "pog.float"
    _ -> "pog.text"
  }
  case is_optional(field_type) {
    // None is NULL
    True -> "pog.nullable(" <> encoder <> ", params." <> name <> ")"
    False -> encoder <> "(params." <> name <> ")"
  }
}

/// A column in a Postgres SELECT or RETURNING list. Dates and timestamps
/// are read as text, since the domain type holds them as strings.
fn pog_select_column(field: #(String, String)) -> String {
  case base_type(field.1) {
    "date" | "datetime" -> field.0 <> "::text AS " <> field.0
    _ -> field.0
  }
}

/// The Postgres placeholder for a parameter. Dates and timestamps are sent
/// as text and cast by Postgres.
fn pog_placeholder(field: #(String, String), index: Int) -> String {
  let placeholder = "$" <> int.to_string(index)
  case base_type(field.1) {
    "date" -> placeholder <> "::text::date"
    "datetime" -> placeholder <> "::text::timestamptz"
    _ -> placeholder
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
      let decode_fn = sqlite_decoder(field_type)
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
    |> list.map(fn(f) { "    " <> sqlite_parameter(f.0, f.1) <> "," })
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
      "  // SQLite enforces foreign keys, and so the ON DELETE CASCADE of",
      "  // --belongs-to children, only on connections that turn them on.",
      "  use _ <- result.try(",
      "    sqlight.exec(\"PRAGMA foreign_keys = ON\", conn)",
      "    |> result.replace_error(Nil),",
      "  )",
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

  let select_fields =
    ["id", ..list.map(fields, pog_select_column)]
    |> string.join(", ")

  let decoder_fields =
    fields
    |> list.index_map(fn(f, i) {
      let #(name, field_type) = f
      let decode_fn = pog_decoder(field_type)
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
    |> list.index_map(fn(f, i) { pog_placeholder(f, i + 1) })
    |> string.join(", ")

  let insert_params =
    fields
    |> list.map(fn(f) {
      "  |> pog.parameter(" <> pog_parameter(f.0, f.1) <> ")"
    })
    |> string.join("\n")

  let update_sets =
    fields
    |> list.index_map(fn(f, i) { f.0 <> " = " <> pog_placeholder(f, i + 1) })
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

// --belongs-to repo functions -------------------------------------------------

/// The SQL for the parents a child form offers: `id` and a label, the
/// parent's first string field or `<Parent> #<id>`.
fn options_sql(relation: Relation, label_cast: String) -> String {
  case relation.label {
    Some(label) ->
      "SELECT id, "
      <> label
      <> label_cast
      <> " FROM "
      <> relation.table
      <> " ORDER BY "
      <> label
      <> ", id"
    None ->
      "SELECT id, '"
      <> relation.type_name
      <> " #' || id FROM "
      <> relation.table
      <> " ORDER BY id"
  }
}

fn options_doc(resource_singular: String, relation: Relation) -> String {
  "/// The "
  <> relation.plural
  <> " a "
  <> resource_singular
  <> " can belong to, as `#(id, label)` pairs for the\n/// form's select."
}

fn list_for_doc(type_name: String, relation: Relation) -> String {
  "/// The "
  <> type_name
  <> " records of one "
  <> relation.singular
  <> ", oldest first."
}

fn relation_functions_sqlite(
  resource_singular: String,
  type_name: String,
  fields: List(#(String, String)),
  relation: Relation,
  with_options: Bool,
) -> String {
  let q = "\""
  let select_fields =
    ["id", ..list.map(fields, fn(f) { f.0 })] |> string.join(", ")
  let table = resource_singular <> "s"
  let list_for = "
" <> list_for_doc(type_name, relation) <> "
pub fn list_for_" <> relation.singular <> "(db_path: String, " <> relation.field <> ": Int) -> List(" <> type_name <> ") {
  use conn <- sqlight.with_connection(db_path)
  case
    sqlight.query(
      " <> q <> "SELECT " <> select_fields <> " FROM " <> table <> " WHERE " <> relation.field <> " = ? ORDER BY id" <> q <> ",
      on: conn,
      with: [sqlight.int(" <> relation.field <> ")],
      expecting: " <> resource_singular <> "_decoder(),
    )
  {
    Ok(rows) -> rows
    Error(_) -> []
  }
}
"
  let options = case with_options {
    False -> ""
    True -> "
" <> options_doc(resource_singular, relation) <> "
pub fn " <> relation.singular <> "_options(db_path: String) -> List(#(Int, String)) {
  use conn <- sqlight.with_connection(db_path)
  let decoder = {
    use id <- decode.field(0, decode.int)
    use label <- decode.field(1, decode.string)
    decode.success(#(id, label))
  }
  case
    sqlight.query(
      " <> q <> options_sql(relation, "") <> q <> ",
      on: conn,
      with: [],
      expecting: decoder,
    )
  {
    Ok(rows) -> rows
    Error(_) -> []
  }
}
"
  }
  list_for <> options
}

fn relation_functions_pog(
  resource_singular: String,
  type_name: String,
  fields: List(#(String, String)),
  relation: Relation,
  with_options: Bool,
) -> String {
  let q = "\""
  let select_fields =
    ["id", ..list.map(fields, pog_select_column)] |> string.join(", ")
  let table = resource_singular <> "s"
  let list_for = "
" <> list_for_doc(type_name, relation) <> "
pub fn list_for_" <> relation.singular <> "(db: pog.Connection, " <> relation.field <> ": Int) -> List(" <> type_name <> ") {
  pog.query(
    " <> q <> "SELECT " <> select_fields <> " FROM " <> table <> " WHERE " <> relation.field <> " = $1 ORDER BY id" <> q <> ",
  )
  |> pog.parameter(pog.int(" <> relation.field <> "))
  |> pog.returning(" <> resource_singular <> "_decoder())
  |> pog.execute(db)
  |> result.map(fn(r) { r.rows })
  |> result.unwrap([])
}
"
  let options = case with_options {
    False -> ""
    True -> "
" <> options_doc(resource_singular, relation) <> "
pub fn " <> relation.singular <> "_options(db: pog.Connection) -> List(#(Int, String)) {
  let decoder = {
    use id <- decode.field(0, decode.int)
    use label <- decode.field(1, decode.string)
    decode.success(#(id, label))
  }
  pog.query(" <> q <> options_sql(relation, "::text") <> q <> ")
  |> pog.returning(decoder)
  |> pog.execute(db)
  |> result.map(fn(r) { r.rows })
  |> result.unwrap([])
}
"
  }
  list_for <> options
}

fn resource_migration(
  name: String,
  fields: List(#(String, String)),
  db: DbChoice,
  relation: Option(Relation),
) -> String {
  let column_defs =
    fields
    |> list.map(fn(f) {
      "  " <> f.0 <> " " <> column_definition(f, db, relation)
    })
    |> string.join(",\n")

  let table = singularize(name) <> "s"

  // The foreign key of --belongs-to is indexed: list_for_<parent> filters
  // on it.
  let index = case relation {
    Some(relation) ->
      "CREATE INDEX "
      <> table
      <> "_"
      <> relation.field
      <> "_index ON "
      <> table
      <> " ("
      <> relation.field
      <> ");\n"
    None -> ""
  }

  case db {
    Sqlite -> "CREATE TABLE " <> table <> " (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
" <> column_defs <> ",
  inserted_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);
" <> index
    _ -> "CREATE TABLE " <> table <> " (
  id SERIAL PRIMARY KEY,
" <> column_defs <> ",
  inserted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
" <> index
  }
}

fn api_resource_test(
  app_name: String,
  resource_plural: String,
  resource_singular: String,
  db: DbChoice,
  fields: List(#(String, String)),
) -> String {
  let handler = resource_singular <> "_handler"
  let form = resource_singular <> "_form"
  let path = "/api/" <> resource_plural

  let db_imports = case db {
    Postgres -> "\nimport gleam/erlang/process\nimport pog"
    _ -> ""
  }

  let test_db = case db {
    Postgres ->
      "db: pog.named_connection(process.new_name(prefix: \""
      <> app_name
      <> "_test_db\"))"
    _ -> "db_path: \":memory:\""
  }

  let valid_fields =
    fields
    |> list.map(fn(f) {
      "    #(\"" <> f.0 <> "\", " <> api_sample_json(f.1) <> "),"
    })
    |> string.join("\n")

  let validation_tests = case api_required_fields(fields) {
    [] -> ""
    [#(name, _), ..] -> "

pub fn decode_json_rejects_a_missing_" <> name <> "_test() {
  let assert Ok(data) = json.parse(\"{}\", decode.dynamic)

  " <> form <> ".decode_json(data)
  |> should.be_error
}

pub fn create_with_invalid_body_returns_422_test() {
  let response =
    testing.json_request(http.Post, \"" <> path <> "\", \"{}\")
    |> " <> handler <> ".create(test_context())

  response.status |> should.equal(422)
  simulate.read_body(response)
  |> json.parse(decode.at([\"errors\", \"" <> name <> "\"], decode.string))
  |> should.equal(Ok(\"" <> capitalize(name) <> " is required\"))
}

pub fn update_with_invalid_body_returns_422_test() {
  let response =
    testing.json_request(http.Put, \"" <> path <> "/1\", \"{}\")
    |> " <> handler <> ".update(test_context(), \"1\")

  response.status |> should.equal(422)
}"
  }

  let wrong_type_test = case fields {
    [] -> ""
    [#(name, field_type), ..] -> "

pub fn create_with_wrong_field_type_returns_400_test() {
  let body =
    json.object([#(\"" <> name <> "\", " <> api_wrong_json(field_type) <> ")])
    |> json.to_string
  let response =
    testing.json_request(http.Post, \"" <> path <> "\", body)
    |> " <> handler <> ".create(test_context())

  response.status |> should.equal(400)
}"
  }

  "//// Tests for the " <> resource_plural <> " JSON API.
////
//// These cover what a handler answers before it reaches the database:
//// malformed and invalid bodies, and ids that are not numbers. Creating,
//// updating and deleting rows needs a migrated database; try those
//// against the running app (`refrakt migrate`, then curl " <> path <> ").

import gleam/dynamic/decode
import gleam/http
import gleam/json" <> db_imports <> "
import gleeunit/should
import " <> app_name <> "/config
import " <> app_name <> "/context.{type Context, Context}
import " <> app_name <> "/web/forms/" <> form <> "
import " <> app_name <> "/web/" <> handler <> "
import refrakt/testing
import wisp/simulate

/// A context whose database these tests never reach.
fn test_context() -> Context {
  let assert Ok(cfg) = config.load()
  Context(config: cfg, " <> test_db <> ")
}

fn valid_body() -> String {
  json.object([
" <> valid_fields <> "
  ])
  |> json.to_string
}

pub fn decode_json_accepts_a_valid_body_test() {
  let assert Ok(data) = json.parse(valid_body(), decode.dynamic)

  " <> form <> ".decode_json(data)
  |> should.be_ok
}" <> validation_tests <> wrong_type_test <> "

pub fn create_with_malformed_json_returns_400_test() {
  let response =
    testing.json_request(http.Post, \"" <> path <> "\", \"{not json\")
    |> " <> handler <> ".create(test_context())

  response.status |> should.equal(400)
}

pub fn update_with_malformed_json_returns_400_test() {
  let response =
    testing.json_request(http.Put, \"" <> path <> "/1\", \"{not json\")
    |> " <> handler <> ".update(test_context(), \"1\")

  response.status |> should.equal(400)
}

pub fn update_unknown_id_returns_404_test() {
  let response =
    testing.json_request(http.Put, \"" <> path <> "/unknown\", valid_body())
    |> " <> handler <> ".update(test_context(), \"unknown\")

  response.status |> should.equal(404)
}

pub fn show_unknown_id_returns_404_test() {
  let response =
    simulate.request(http.Get, \"" <> path <> "/unknown\")
    |> " <> handler <> ".show(test_context(), \"unknown\")

  response.status |> should.equal(404)
}

pub fn delete_unknown_id_returns_404_test() {
  let response =
    simulate.request(http.Delete, \"" <> path <> "/unknown\")
    |> " <> handler <> ".delete(test_context(), \"unknown\")

  response.status |> should.equal(404)
}
"
}

fn resource_test(
  app_name: String,
  resource_plural: String,
  resource_singular: String,
  fields: List(#(String, String)),
  db: DbChoice,
  rerender_test: Bool,
) -> String {
  // Build valid form data for decode test
  let valid_values =
    fields
    |> list.map(fn(f) {
      let #(name, ftype) = f
      let val = case ftype {
        "bool" -> "on"
        "optional(bool)" -> "true"
        "int" | "optional(int)" -> "42"
        "float" | "optional(float)" -> "3.14"
        _ -> "test value"
      }
      "    #(\"" <> name <> "\", \"" <> val <> "\"),"
    })
    |> string.join("\n")

  // Find required string fields for missing-field test
  let required_fields =
    fields
    |> list.filter(fn(f) { f.1 == "string" || f.1 == "text" })

  let missing_field_tests = case required_fields {
    [#(name, _), ..] -> "

pub fn decode_missing_" <> name <> "_returns_error_test() {
  let data =
    wisp.FormData(values: [], files: [])

  " <> resource_singular <> "_form.decode(data)
  |> should.be_error
}
" <> case rerender_test {
        False -> ""
        True -> "
pub fn same_origin_invalid_create_rerenders_form_test() {
  // browser_request sends an Origin header matching the host, as a
  // browser does when it submits the form on /" <> resource_plural <> "/new.
  let response =
    simulate.browser_request(http.Post, \"/" <> resource_plural <> "\")
    |> simulate.form_body([])
    |> router.handle_request(test_context())

  response.status
  |> should.equal(422)
}
"
      }
    [] -> ""
  }

  let #(context_imports, context_value) = templates.test_context(db)

  "import gleam/http
import gleeunit/should
import " <> app_name <> "/config
import " <> app_name <> "/context.{type Context}
import " <> app_name <> "/router
import " <> app_name <> "/web/forms/" <> resource_singular <> "_form" <> context_imports <> "
import wisp
import wisp/simulate

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

pub fn cross_site_create_is_rejected_test() {
  let response =
    simulate.request(http.Post, \"/" <> resource_plural <> "\")
    |> simulate.header(\"origin\", \"https://evil.example\")
    |> simulate.form_body([])
    |> router.handle_request(test_context())

  response.status
  |> should.equal(403)
}
" <> missing_field_tests <> "
fn test_context() -> Context {
  let assert Ok(cfg) = config.load()
  " <> context_value <> "
}
"
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

fn patch_router_api_resource(app: String, plural: String, singular: String) {
  let router_path = "src/" <> app <> "/router.gleam"
  let assert Ok(content) = simplifile.read(router_path)

  let import_line = "import " <> app <> "/web/" <> singular <> "_handler"
  let content = add_import(content, import_line)

  // API routes: no /new or /edit (those are HTML-only)
  let routes =
    "\n    [\"api\", \""
    <> plural
    <> "\"], http.Get -> "
    <> singular
    <> "_handler.index(req, ctx)
    [\"api\", \""
    <> plural
    <> "\"], http.Post -> "
    <> singular
    <> "_handler.create(req, ctx)
    [\"api\", \""
    <> plural
    <> "\", id], http.Get -> "
    <> singular
    <> "_handler.show(req, ctx, id)
    [\"api\", \""
    <> plural
    <> "\", id], http.Put -> "
    <> singular
    <> "_handler.update(req, ctx, id)
    [\"api\", \""
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

/// The field types `gen resource` knows, besides `optional(<type>)`.
const field_types = [
  "string",
  "text",
  "int",
  "float",
  "bool",
  "date",
  "datetime",
]

/// Parse `name:type` field specs. A type is one of `field_types` or
/// `optional(<one of them>)`; the result holds the normalized type
/// (`optional(float)`), or a message saying which spec is wrong.
pub fn parse_fields(
  raw: List(String),
) -> Result(List(#(String, String)), String) {
  use fields <- result.try(list.try_map(raw, parse_field))
  case find_duplicate(list.map(fields, fn(f) { f.0 }), []) {
    Ok(name) -> Error("Field `" <> name <> "` is given more than once.")
    Error(_) -> Ok(fields)
  }
}

/// Parse one `name:type` field spec, such as `price:optional(float)`.
pub fn parse_field(spec: String) -> Result(#(String, String), String) {
  case string.split_once(spec, ":") {
    Error(_) ->
      Error(
        "Invalid field `"
        <> spec
        <> "`: expected name:type, such as title:string or price:optional(float).",
      )
    Ok(#(name, field_type)) -> {
      use name <- result.try(check_field_name(name, spec))
      use field_type <- result.try(parse_field_type(field_type, name))
      Ok(#(name, field_type))
    }
  }
}

fn check_field_name(name: String, spec: String) -> Result(String, String) {
  let valid_chars = string.to_graphemes("abcdefghijklmnopqrstuvwxyz0123456789_")
  let starts_with_letter = case string.pop_grapheme(name) {
    Ok(#(first, _)) -> string.contains("abcdefghijklmnopqrstuvwxyz", first)
    Error(_) -> False
  }
  let only_valid_chars =
    list.all(string.to_graphemes(name), list.contains(valid_chars, _))
  case name {
    "id" | "inserted_at" | "updated_at" ->
      Error(
        "Invalid field `"
        <> spec
        <> "`: `"
        <> name
        <> "` is a column every resource already has.",
      )
    _ if starts_with_letter && only_valid_chars -> Ok(name)
    _ ->
      Error(
        "Invalid field name in `"
        <> spec
        <> "`: use lowercase letters, digits and underscores, starting with a letter.",
      )
  }
}

fn parse_field_type(
  field_type: String,
  field_name: String,
) -> Result(String, String) {
  let field_type = string.lowercase(string.trim(field_type))
  let unknown = fn(found: String) {
    Error(
      "Unknown type `"
      <> found
      <> "` for field `"
      <> field_name
      <> "`. Use one of: "
      <> string.join(field_types, ", ")
      <> ", or optional(<type>) for a nullable field, such as optional(float).",
    )
  }
  case string.starts_with(field_type, "optional(") {
    True ->
      case string.ends_with(field_type, ")") {
        False -> unknown(field_type)
        True -> {
          let inner =
            field_type
            |> string.drop_start(string.length("optional("))
            |> string.drop_end(1)
            |> string.trim
          case list.contains(field_types, inner) {
            True -> Ok("optional(" <> inner <> ")")
            False -> unknown(field_type)
          }
        }
      }
    False ->
      case list.contains(field_types, field_type) {
        True -> Ok(field_type)
        False -> unknown(field_type)
      }
  }
}

fn find_duplicate(
  names: List(String),
  seen: List(String),
) -> Result(String, Nil) {
  case names {
    [] -> Error(Nil)
    [name, ..rest] ->
      case list.contains(seen, name) {
        True -> Ok(name)
        False -> find_duplicate(rest, [name, ..seen])
      }
  }
}

/// Whether a field type is `optional(<type>)`: a nullable column and an
/// `Option` in Gleam.
pub fn is_optional(field_type: String) -> Bool {
  string.starts_with(field_type, "optional(")
}

/// The type inside `optional(<type>)`, or the type itself.
pub fn base_type(field_type: String) -> String {
  case is_optional(field_type) {
    True ->
      field_type
      |> string.drop_start(string.length("optional("))
      |> string.drop_end(1)
    False -> field_type
  }
}

pub fn to_gleam_type(field_type: String) -> String {
  case is_optional(field_type) {
    True -> "Option(" <> to_gleam_type(base_type(field_type)) <> ")"
    False ->
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
}

/// The column definition after the column name: the SQL type, `NOT NULL`
/// unless the field is optional, and for the `--belongs-to` field a
/// foreign key to the parent.
fn column_definition(
  field: #(String, String),
  db: DbChoice,
  relation: Option(Relation),
) -> String {
  let #(field_name, field_type) = field
  let sql_type = case db {
    Sqlite -> to_sql_type_sqlite(base_type(field_type))
    _ -> to_sql_type(base_type(field_type))
  }
  let null = case is_optional(field_type) {
    True -> ""
    False -> " NOT NULL"
  }
  let reference = case relation {
    Some(relation) if relation.field == field_name ->
      " REFERENCES " <> relation.table <> "(id) ON DELETE CASCADE"
    _ -> ""
  }
  sql_type <> null <> reference
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
  case is_optional(field_type) {
    True -> "None"
    False -> plain_default_value(field_type)
  }
}

fn plain_default_value(field_type: String) -> String {
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

/// An Argon2id hash of a random password nobody knows, made with
/// `argus.hasher()`'s default cost settings (the ones `hash_password`
/// uses), so verifying a password against it takes as long as against a
/// real user's hash.
const dummy_password_hash =
  "$argon2id$v=13$m=19456,t=2,p=1$ifVUQ7umIYAd2kxrogck4g$p2a30+poAQh1eT0W6bef/xnaQUlPIMAtgLC/T3w7gn8"

fn auth_domain(app: String) -> String {
  "import argus
import gleam/result
import " <> app <> "/domain/user.{type User}

/// An Argon2id hash with the same cost settings as `hash_password`, of a
/// password nobody knows. `authenticate` checks against it when there is
/// no user with the given email. If you change the cost settings, replace
/// it with a hash made with the new ones.
pub const dummy_hash = \"" <> dummy_password_hash <> "\"

/// Hash a password with Argon2id, using a fresh random salt and the
/// OWASP-recommended cost settings. The result is a self-describing
/// string (`$argon2id$...`) holding the salt and parameters, so it
/// can be stored as-is and checked later with `verify_password`.
pub fn hash_password(password: String) -> Result(String, Nil) {
  argus.hasher()
  |> argus.hash(password)
  |> result.map(fn(output) { output.encoded_hash })
  |> result.replace_error(Nil)
}

/// Check a password against a hash from `hash_password`. The comparison
/// is constant-time; a malformed hash never matches.
pub fn verify_password(password: String, hash: String) -> Bool {
  argus.verify(hash, password)
  |> result.unwrap(False)
}

/// Check a login: the user looked up by email, and the password given.
/// When there is no such user the password is still checked, against
/// `dummy_hash`, so the answer takes as long as for a wrong password and
/// response times do not reveal which emails have accounts.
pub fn authenticate(
  user: Result(User, Nil),
  password: String,
) -> Result(User, Nil) {
  case user {
    Ok(user) ->
      case verify_password(password, user.hashed_password) {
        True -> Ok(user)
        False -> Error(Nil)
      }
    Error(_) -> {
      let _ = verify_password(password, dummy_hash)
      Error(Nil)
    }
  }
}
"
}

/// The expression a generated handler uses to reach the database.
fn auth_db_arg(db: DbChoice) -> String {
  case db {
    Sqlite -> "ctx.db_path"
    _ -> "ctx.db"
  }
}

fn auth_user_repo(app: String, db: DbChoice) -> String {
  case db {
    Sqlite -> auth_user_repo_sqlite(app)
    _ -> auth_user_repo_pog(app)
  }
}

fn auth_user_repo_sqlite(app: String) -> String {
  let q = "\""
  "import gleam/dynamic/decode
import gleam/result
import " <> app <> "/domain/user.{type User, User}
import sqlight

fn user_decoder() -> decode.Decoder(User) {
  use id <- decode.field(0, decode.int)
  use email <- decode.field(1, decode.string)
  use hashed_password <- decode.field(2, decode.string)
  decode.success(User(id: id, email: email, hashed_password: hashed_password))
}

pub fn get_by_email(db_path: String, email: String) -> Result(User, Nil) {
  use conn <- sqlight.with_connection(db_path)
  sqlight.query(
    " <> q <> "SELECT id, email, hashed_password FROM users WHERE email = ?" <> q <> ",
    on: conn,
    with: [sqlight.text(email)],
    expecting: user_decoder(),
  )
  |> result.replace_error(Nil)
  |> result.try(fn(rows) {
    case rows {
      [user] -> Ok(user)
      _ -> Error(Nil)
    }
  })
}

pub fn get_by_id(db_path: String, id: Int) -> Result(User, Nil) {
  use conn <- sqlight.with_connection(db_path)
  sqlight.query(
    " <> q <> "SELECT id, email, hashed_password FROM users WHERE id = ?" <> q <> ",
    on: conn,
    with: [sqlight.int(id)],
    expecting: user_decoder(),
  )
  |> result.replace_error(Nil)
  |> result.try(fn(rows) {
    case rows {
      [user] -> Ok(user)
      _ -> Error(Nil)
    }
  })
}

pub fn create(
  db_path: String,
  email: String,
  hashed_password: String,
) -> Result(User, Nil) {
  use conn <- sqlight.with_connection(db_path)
  sqlight.query(
    " <> q <> "INSERT INTO users (email, hashed_password) VALUES (?, ?) RETURNING id, email, hashed_password" <> q <> ",
    on: conn,
    with: [sqlight.text(email), sqlight.text(hashed_password)],
    expecting: user_decoder(),
  )
  |> result.replace_error(Nil)
  |> result.try(fn(rows) {
    case rows {
      [user] -> Ok(user)
      _ -> Error(Nil)
    }
  })
}
"
}

fn auth_user_repo_pog(app: String) -> String {
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

fn auth_migration(db: DbChoice) -> String {
  case db {
    Sqlite ->
      "CREATE TABLE users (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  email TEXT NOT NULL UNIQUE,
  hashed_password TEXT NOT NULL,
  inserted_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);
"
    _ ->
      "CREATE TABLE users (
  id SERIAL PRIMARY KEY,
  email TEXT NOT NULL UNIQUE,
  hashed_password TEXT NOT NULL,
  inserted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
"
  }
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

fn auth_handler(app: String, db: DbChoice) -> String {
  let db_arg = auth_db_arg(db)
  "import gleam/result
import " <> app <> "/context.{type Context}
import " <> app <> "/data/user_repo
import " <> app <> "/domain/auth
import " <> app <> "/web/auth_views
import " <> app <> "/web/forms/auth_form
import " <> app <> "/web/layouts/root_layout
import " <> app <> "/web/session
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
      case
        user_repo.get_by_email(" <> db_arg <> ", params.email)
        |> auth.authenticate(params.password)
      {
        Ok(user) ->
          wisp.redirect(\"/\")
          |> session.sign_in(req, ctx, user.id)
          |> flash.set_flash(req, \"info\", \"Logged in\")

        Error(_) ->
          auth_views.login_view(params.email, [#(\"email\", \"Invalid email or password\")])
          |> root_layout.wrap(\"Log In\")
          |> wisp.html_response(422)
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
      let created = {
        use hashed <- result.try(auth.hash_password(params.password))
        user_repo.create(" <> db_arg <> ", params.email, hashed)
      }
      case created {
        Ok(user) ->
          wisp.redirect(\"/\")
          |> session.sign_in(req, ctx, user.id)
          |> flash.set_flash(req, \"info\", \"Account created\")

        Error(_) ->
          auth_views.register_view(params.email, [#(\"email\", \"Could not create account\")])
          |> root_layout.wrap(\"Register\")
          |> wisp.html_response(422)
      }
    }
  }
}

pub fn logout(req: Request, ctx: Context) -> Response {
  wisp.redirect(\"/\")
  |> session.sign_out(req, ctx)
  |> flash.set_flash(req, \"info\", \"Logged out\")
}
"
}

fn auth_session(app: String) -> String {
  "//// The login session: a cookie holding the user's id in a signed token
//// that records when it was issued.
////
//// The cookie is HttpOnly (page scripts cannot read it), SameSite=Lax
//// (browsers only send it along from other sites on plain link
//// navigation, never with their form posts or scripts) and, in
//// production, Secure (HTTPS only). The token is refused once it is
//// older than `max_age`, even if a copy of the cookie is replayed after
//// the browser dropped it. Changing SECRET_KEY_BASE signs everyone out.

import gleam/http
import gleam/http/cookie
import gleam/http/request
import gleam/http/response
import gleam/int
import gleam/list
import gleam/option.{Some}
import gleam/result
import " <> app <> "/config
import " <> app <> "/context.{type Context}
import refrakt/token
import wisp.{type Request, type Response}

const cookie_name = \"_session\"

/// Tokens of different purposes are not interchangeable.
const purpose = \"session\"

/// How long a login lasts, in seconds: seven days.
const max_age = 604_800

/// Sign the user in: set the session cookie on the response.
pub fn sign_in(
  resp: Response,
  req: Request,
  ctx: Context,
  user_id: Int,
) -> Response {
  let value =
    token.sign(
      wisp.get_secret_key_base(req),
      purpose,
      int.to_string(user_id),
      max_age_seconds: max_age,
    )
  response.set_cookie(resp, cookie_name, value, attributes(req, ctx, max_age))
}

/// Sign the user out: tell the browser to delete the session cookie.
pub fn sign_out(resp: Response, req: Request, ctx: Context) -> Response {
  response.set_cookie(resp, cookie_name, \"\", attributes(req, ctx, 0))
}

/// The id of the signed-in user, if the request has a valid session.
pub fn user_id(req: Request) -> Result(Int, Nil) {
  use value <- result.try(
    request.get_cookies(req)
    |> list.key_find(cookie_name),
  )
  use id <- result.try(
    token.verify(
      wisp.get_secret_key_base(req),
      purpose,
      value,
      max_age_seconds: max_age,
    )
    |> result.replace_error(Nil),
  )
  int.parse(id)
}

fn attributes(req: Request, ctx: Context, max_age: Int) -> cookie.Attributes {
  // Production always marks the cookie Secure, even behind a proxy that
  // talks plain HTTP to the app. Development follows the request, as
  // Safari drops Secure cookies on http://localhost.
  let scheme = case ctx.config.env {
    config.Prod -> http.Https
    config.Dev | config.Test -> req.scheme
  }
  cookie.Attributes(..cookie.defaults(scheme), max_age: Some(max_age))
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

/// A \"Log out\" button for the layout. Logging out is a POST, so other
/// sites cannot log your users out with a link or an image.
pub fn logout_form() -> Element(Nil) {
  form([attribute.action(\"/logout\"), attribute.method(\"post\")], [
    button([type_(\"submit\"), class(\"btn\")], [text(\"Log Out\")]),
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

fn auth_middleware(app: String, db: DbChoice) -> String {
  let db_arg = auth_db_arg(db)
  "import gleam/result
import " <> app <> "/context.{type Context}
import " <> app <> "/data/user_repo
import " <> app <> "/domain/user.{type User}
import " <> app <> "/web/session
import wisp.{type Request, type Response}

/// The signed-in user, from the session cookie.
pub fn get_current_user(req: Request, ctx: Context) -> Result(User, Nil) {
  use user_id <- result.try(session.user_id(req))
  user_repo.get_by_id(" <> db_arg <> ", user_id)
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
  "import argus
import gleam/string
import gleeunit/should
import " <> app <> "/domain/auth
import " <> app <> "/domain/user.{User}

pub fn hash_password_round_trip_test() {
  let assert Ok(hash) = auth.hash_password(\"secret123\")
  auth.verify_password(\"secret123\", hash)
  |> should.be_true
}

pub fn wrong_password_test() {
  let assert Ok(hash) = auth.hash_password(\"secret123\")
  auth.verify_password(\"wrong\", hash)
  |> should.be_false
}

pub fn hash_uses_argon2id_test() {
  let assert Ok(hash) = auth.hash_password(\"secret123\")
  string.starts_with(hash, \"$argon2id$\")
  |> should.be_true
}

pub fn hashes_are_salted_test() {
  let assert Ok(first) = auth.hash_password(\"secret123\")
  let assert Ok(second) = auth.hash_password(\"secret123\")
  first
  |> should.not_equal(second)
}

pub fn malformed_hash_never_matches_test() {
  auth.verify_password(\"secret123\", \"not-a-hash\")
  |> should.be_false
}

pub fn dummy_hash_is_a_real_argon2id_hash_test() {
  // A malformed hash fails fast; a real one runs Argon2 like a user's.
  argus.verify(auth.dummy_hash, \"secret123\")
  |> should.equal(Ok(False))
}

pub fn authenticate_accepts_the_right_password_test() {
  let assert Ok(hash) = auth.hash_password(\"secret123\")
  let user = User(id: 1, email: \"a@example.com\", hashed_password: hash)

  auth.authenticate(Ok(user), \"secret123\")
  |> should.equal(Ok(user))
}

pub fn authenticate_rejects_a_wrong_password_test() {
  let assert Ok(hash) = auth.hash_password(\"secret123\")
  let user = User(id: 1, email: \"a@example.com\", hashed_password: hash)

  auth.authenticate(Ok(user), \"wrong\")
  |> should.be_error
}

pub fn authenticate_rejects_an_unknown_user_test() {
  auth.authenticate(Error(Nil), \"secret123\")
  |> should.be_error
}
"
}

fn auth_session_test(app: String, db: DbChoice) -> String {
  let #(context_imports, context_value) = templates.test_context(db)

  "import gleam/http
import gleam/http/request
import gleam/list
import gleam/string
import gleeunit/should
import " <> app <> "/config
import " <> app <> "/context.{type Context}
import " <> app <> "/web/session" <> context_imports <> "
import refrakt/token
import wisp
import wisp/simulate

pub fn signed_in_request_has_the_user_id_test() {
  let req = simulate.browser_request(http.Post, \"/login\")
  let resp = wisp.redirect(\"/\") |> session.sign_in(req, test_context(), 42)

  simulate.browser_request(http.Get, \"/\")
  |> simulate.session(req, resp)
  |> session.user_id
  |> should.equal(Ok(42))
}

pub fn signed_out_request_has_no_user_test() {
  let req = simulate.browser_request(http.Post, \"/login\")
  let signed_in = wisp.redirect(\"/\") |> session.sign_in(req, test_context(), 42)
  let req =
    simulate.browser_request(http.Post, \"/logout\")
    |> simulate.session(req, signed_in)
  let signed_out = wisp.redirect(\"/\") |> session.sign_out(req, test_context())

  simulate.browser_request(http.Get, \"/\")
  |> simulate.session(req, signed_out)
  |> session.user_id
  |> should.be_error
}

pub fn session_signed_with_another_key_is_rejected_test() {
  let forged =
    token.sign(\"not-the-secret-key-base\", \"session\", \"1\", max_age_seconds: 60)

  simulate.browser_request(http.Get, \"/\")
  |> request.set_cookie(\"_session\", forged)
  |> session.user_id
  |> should.be_error
}

pub fn session_cookie_is_http_only_and_same_site_test() {
  let cookie = session_cookie(test_context())

  string.contains(cookie, \"HttpOnly\")
  |> should.be_true
  string.contains(cookie, \"SameSite=Lax\")
  |> should.be_true
  string.contains(cookie, \"Max-Age=604800\")
  |> should.be_true
}

pub fn session_cookie_is_secure_in_production_test() {
  let ctx = test_context()
  let ctx = context.Context(..ctx, config: config.Config(..ctx.config, env: config.Prod))

  session_cookie(ctx)
  |> string.contains(\"Secure\")
  |> should.be_true
}

/// The Set-Cookie header of a sign-in over plain HTTP.
fn session_cookie(ctx: Context) -> String {
  let req =
    simulate.browser_request(http.Post, \"/login\")
    |> request.set_scheme(http.Http)
  let resp = wisp.redirect(\"/\") |> session.sign_in(req, ctx, 42)
  let assert Ok(cookie) = list.key_find(resp.headers, \"set-cookie\")
  cookie
}

fn test_context() -> Context {
  let assert Ok(cfg) = config.load()
  " <> context_value <> "
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

fn append_if(
  items: List(String),
  condition: Bool,
  item: String,
) -> List(String) {
  case condition {
    True -> list.append(items, [item])
    False -> items
  }
}
