/// File templates for code generation.
///
/// Each function returns the complete file content as a String.
/// Templates use string concatenation — no macros, no interpolation engine.
///
import gleam/string
import refrakt/cli/types.{type DbChoice, NoDb, Postgres, Sqlite}

// =============================================================================
// Project files
// =============================================================================

pub fn gleam_toml(name: String, db: DbChoice) -> String {
  let db_dep = case db {
    Postgres -> "\npog = \">= 4.1.0 and < 5.0.0\""
    Sqlite -> "\nsqlight = \">= 1.0.0 and < 2.0.0\""
    NoDb -> ""
  }

  "name = \"" <> name <> "\"
version = \"0.1.0\"
target = \"erlang\"
gleam = \">= 1.14.0\"

[dependencies]
gleam_stdlib = \">= 0.44.0 and < 2.0.0\"
gleam_erlang = \">= 0.34.0 and < 2.0.0\"
gleam_http = \">= 4.3.0 and < 5.0.0\"
envoy = \">= 1.1.0 and < 2.0.0\"
mist = \">= 5.0.0 and < 6.0.0\"
wisp = \">= 2.2.0 and < 3.0.0\"
lustre = \">= 5.6.0 and < 6.0.0\"
refrakt = \">= 0.1.0 and < 1.0.0\"" <> db_dep <> "

[dev-dependencies]
gleeunit = \">= 1.0.0 and < 2.0.0\"
"
}

pub fn gitignore() -> String {
  "/build/
.DS_Store
"
}

pub fn readme(name: String) -> String {
  "# " <> name <> "

A web application built with [Refrakt](https://github.com/raskell-io/refrakt).

## Development

```bash
gleam run    # Start the server at http://localhost:4000
gleam test   # Run tests
```
"
}

// =============================================================================
// Application modules
// =============================================================================

pub fn main_module(name: String, db: DbChoice) -> String {
  let db_import = case db {
    Postgres -> "\nimport " <> name <> "/data/repo"
    Sqlite -> "\nimport " <> name <> "/data/repo"
    NoDb -> ""
  }

  let db_ctx = case db {
    Postgres ->
      "\n  let assert Ok(db) = repo.connect(cfg)\n  let ctx = context.Context(config: cfg, db: db)"
    Sqlite ->
      "\n  let db_path = repo.database_path(cfg)\n  let ctx = context.Context(config: cfg, db_path: db_path)"
    NoDb -> "\n  let ctx = context.Context(config: cfg)"
  }

  "import gleam/erlang/process
import gleam/io
import mist
import " <> name <> "/config
import " <> name <> "/context
import " <> name <> "/router
import wisp
import wisp/wisp_mist" <> db_import <> "

pub fn main() {
  wisp.configure_logger()

  let cfg = config.load()" <> db_ctx <> "

  let assert Ok(_) =
    wisp_mist.handler(router.handle_request(_, ctx), cfg.secret_key_base)
    |> mist.new
    |> mist.port(cfg.port)
    |> mist.start

  io.println(\"Listening on http://localhost:\" <> cfg.port_string)
  process.sleep_forever()
}
"
}

pub fn config_module(_name: String) -> String {
  "import envoy
import gleam/int
import gleam/result

pub type Config {
  Config(
    port: Int,
    port_string: String,
    secret_key_base: String,
    env: Env,
  )
}

pub type Env {
  Dev
  Test
  Prod
}

pub fn load() -> Config {
  let port =
    envoy.get(\"PORT\")
    |> result.try(int.parse)
    |> result.unwrap(4000)

  let secret_key_base =
    envoy.get(\"SECRET_KEY_BASE\")
    |> result.unwrap(
      \"dev-secret-key-base-that-is-at-least-64-bytes-long-for-security!!\",
    )

  let env = case envoy.get(\"APP_ENV\") {
    Ok(\"prod\") -> Prod
    Ok(\"test\") -> Test
    _ -> Dev
  }

  Config(
    port: port,
    port_string: int.to_string(port),
    secret_key_base: secret_key_base,
    env: env,
  )
}
"
}

pub fn context_module(name: String, db: DbChoice) -> String {
  let db_field = case db {
    Postgres -> ", db: pog.Connection"
    Sqlite -> ", db_path: String"
    NoDb -> ""
  }

  let db_import = case db {
    Postgres -> "\nimport pog"
    _ -> ""
  }

  "import " <> name <> "/config" <> db_import <> "

pub type Context {
  Context(config: config.Config" <> db_field <> ")
}
"
}

pub fn router_module(name: String, _db: DbChoice) -> String {
  "import gleam/http
import " <> name <> "/context.{type Context}
import " <> name <> "/web/error_handler
import " <> name <> "/web/home_handler
import wisp.{type Request, type Response}

pub fn handle_request(req: Request, ctx: Context) -> Response {
  use req <- middleware(req)

  case wisp.path_segments(req), req.method {
    [], http.Get -> home_handler.index(req, ctx)
    _, _ -> error_handler.not_found(req)
  }
}

fn middleware(
  req: Request,
  next: fn(Request) -> Response,
) -> Response {
  let req = wisp.method_override(req)
  use <- wisp.log_request(req)
  use <- wisp.rescue_crashes
  use <- wisp.serve_static(req, under: \"/static\", from: priv_static())
  next(req)
}

fn priv_static() -> String {
  let assert Ok(priv) = wisp.priv_directory(\"" <> name <> "\")
  priv <> \"/static\"
}
"
}

pub fn home_handler(name: String) -> String {
  "import lustre/attribute.{class}
import lustre/element.{text}
import lustre/element/html.{h1, p, section}
import " <> name <> "/context.{type Context}
import " <> name <> "/web/layouts/root_layout
import wisp.{type Request, type Response}

pub fn index(_req: Request, _ctx: Context) -> Response {
  section([class(\"hero\")], [
    h1([], [text(\"Welcome to " <> name <> "\")]),
    p([], [text(\"Built with Refrakt — a convention-first web framework for Gleam.\")]),
  ])
  |> root_layout.wrap(\"Home\")
  |> wisp.html_response(200)
}
"
}

pub fn error_handler(_name: String) -> String {
  "import lustre/attribute.{class}
import lustre/element.{text}
import lustre/element/html.{h1, p, section}
import wisp.{type Request, type Response}

pub fn not_found(_req: Request) -> Response {
  section([class(\"error-page\")], [
    h1([], [text(\"404\")]),
    p([], [text(\"Page not found.\")]),
  ])
  |> element.to_string
  |> wisp.html_response(404)
}

pub fn internal_error(_req: Request) -> Response {
  section([class(\"error-page\")], [
    h1([], [text(\"500\")]),
    p([], [text(\"Something went wrong.\")]),
  ])
  |> element.to_string
  |> wisp.html_response(500)
}
"
}

pub fn root_layout() -> String {
  "import lustre/attribute.{charset, class, content, href, name, rel}
import lustre/element.{type Element}
import lustre/element/html.{body, head, html, link, main, meta, title}

pub fn wrap(inner: Element(Nil), page_title: String) -> String {
  html([], [
    head([], [
      meta([charset(\"utf-8\")]),
      meta([name(\"viewport\"), content(\"width=device-width, initial-scale=1\")]),
      title([], page_title),
      link([rel(\"stylesheet\"), href(\"/static/css/app.css\")]),
    ]),
    body([], [main([class(\"container\")], [inner])]),
  ])
  |> element.to_document_string
}
"
}

pub fn flash_component() -> String {
  "import lustre/attribute.{class}
import lustre/element.{type Element, text}
import lustre/element/html.{div, p}
import gleam/option.{type Option, None, Some}

pub fn render(message: Option(String)) -> Element(Nil) {
  case message {
    Some(msg) ->
      div([class(\"flash\")], [
        p([], [text(msg)]),
      ])
    None -> text(\"\")
  }
}
"
}

pub fn repo_module(name: String, db: DbChoice) -> String {
  case db {
    Postgres -> "import " <> name <> "/config.{type Config}
import gleam/erlang/process
import gleam/result
import pog

pub fn connect(cfg: Config) -> Result(pog.Connection, Nil) {
  let db_url = case cfg.env {
    config.Test -> \"postgres://localhost:5432/" <> name <> "_test\"
    _ -> \"postgres://localhost:5432/" <> name <> "_dev\"
  }

  let pool_name = process.new_name(prefix: \"" <> name <> "_db\")
  use db_config <- result.try(pog.url_config(pool_name, db_url))
  case pog.start(db_config) {
    Ok(_started) -> Ok(pog.named_connection(pool_name))
    Error(_) -> Error(Nil)
  }
}
"
    Sqlite -> "import " <> name <> "/config.{type Config}

/// Get the SQLite database path for the current environment.
pub fn database_path(cfg: Config) -> String {
  case cfg.env {
    config.Test -> \":memory:\"
    _ -> \"" <> name <> ".db\"
  }
}
"
    NoDb -> ""
  }
}

// =============================================================================
// Static assets
// =============================================================================

pub fn app_css() -> String {
  "/* Refrakt default styles */

*,
*::before,
*::after {
  box-sizing: border-box;
  margin: 0;
  padding: 0;
}

:root {
  --font-sans: system-ui, -apple-system, sans-serif;
  --font-mono: ui-monospace, \"Cascadia Code\", \"Fira Code\", monospace;
  --color-bg: #fafafa;
  --color-text: #1a1a1a;
  --color-muted: #666;
  --color-border: #e5e5e5;
  --color-accent: #5b21b6;
  --color-accent-light: #7c3aed;
  --color-error: #dc2626;
  --max-width: 48rem;
}

body {
  font-family: var(--font-sans);
  color: var(--color-text);
  background: var(--color-bg);
  line-height: 1.6;
}

.container {
  max-width: var(--max-width);
  margin: 0 auto;
  padding: 2rem 1rem;
}

/* Hero */
.hero {
  text-align: center;
  padding: 4rem 0;
}

.hero h1 {
  font-size: 2.5rem;
  margin-bottom: 0.5rem;
}

.hero p {
  color: var(--color-muted);
  font-size: 1.125rem;
}

/* Links */
a {
  color: var(--color-accent);
  text-decoration: none;
}

a:hover {
  text-decoration: underline;
}

/* Buttons */
.btn {
  display: inline-block;
  padding: 0.5rem 1rem;
  background: var(--color-accent);
  color: white;
  border: none;
  border-radius: 0.25rem;
  font-size: 0.875rem;
  cursor: pointer;
  text-decoration: none;
}

.btn:hover {
  background: var(--color-accent-light);
  text-decoration: none;
}

/* Forms */
.field {
  margin-bottom: 1rem;
}

.field label {
  display: block;
  font-weight: 500;
  margin-bottom: 0.25rem;
}

.field input[type=\"text\"],
.field input[type=\"email\"],
.field input[type=\"password\"],
.field textarea,
.field select {
  width: 100%;
  padding: 0.5rem;
  border: 1px solid var(--color-border);
  border-radius: 0.25rem;
  font-size: 1rem;
  font-family: inherit;
}

.field textarea {
  min-height: 8rem;
  resize: vertical;
}

.field .error {
  color: var(--color-error);
  font-size: 0.875rem;
  margin-top: 0.25rem;
}

/* Flash */
.flash {
  padding: 0.75rem 1rem;
  border-radius: 0.25rem;
  background: #dbeafe;
  border: 1px solid #93c5fd;
  margin-bottom: 1rem;
}

/* Error pages */
.error-page {
  text-align: center;
  padding: 4rem 0;
}

.error-page h1 {
  font-size: 4rem;
  color: var(--color-muted);
}

/* Lists */
.post-list {
  list-style: none;
}

.post-list li {
  padding: 0.75rem 0;
  border-bottom: 1px solid var(--color-border);
}

.header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 1.5rem;
}

.actions {
  margin-top: 1.5rem;
  display: flex;
  gap: 0.5rem;
}
"
}

pub fn app_js() -> String {
  "// Refrakt client-side JavaScript
// Add your client-side code here.
"
}

// =============================================================================
// Tests
// =============================================================================

pub fn main_test(_name: String) -> String {
  "import gleeunit

pub fn main() {
  gleeunit.main()
}
"
}

pub fn home_handler_test(_name: String) -> String {
  "import gleeunit/should

pub fn placeholder_test() {
  1 + 1
  |> should.equal(2)
}
"
}

// =============================================================================
// Resource generator templates
// =============================================================================

pub fn resource_handler(
  app_name: String,
  resource_plural: String,
  resource_singular: String,
  type_name: String,
) -> String {
  "import gleam/int
import " <> app_name <> "/context.{type Context}
import " <> app_name <> "/data/" <> resource_singular <> "_repo
import " <> app_name <> "/web/error_handler
import " <> app_name <> "/web/forms/" <> resource_singular <> "_form
import " <> app_name <> "/web/layouts/root_layout
import " <> app_name <> "/web/" <> resource_singular <> "_views
import refrakt/flash
import wisp.{type Request, type Response}

pub fn index(_req: Request, ctx: Context) -> Response {
  let items = " <> resource_singular <> "_repo.list(ctx.db)
  " <> resource_singular <> "_views.index_view(items)
  |> root_layout.wrap(\"" <> type_name <> "s\")
  |> wisp.html_response(200)
}

pub fn show(req: Request, ctx: Context, id: String) -> Response {
  case int.parse(id) {
    Error(_) -> error_handler.not_found(req)
    Ok(id) ->
      case " <> resource_singular <> "_repo.get(ctx.db, id) {
        Error(_) -> error_handler.not_found(req)
        Ok(item) ->
          " <> resource_singular <> "_views.show_view(item)
          |> root_layout.wrap(item.title)
          |> wisp.html_response(200)
      }
  }
}

pub fn new(_req: Request, _ctx: Context) -> Response {
  " <> resource_singular <> "_views.form_view(" <> resource_singular <> "_form.empty(), [])
  |> root_layout.wrap(\"New " <> type_name <> "\")
  |> wisp.html_response(200)
}

pub fn create(req: Request, ctx: Context) -> Response {
  use form_data <- wisp.require_form(req)

  case " <> resource_singular <> "_form.decode(form_data) {
    Error(errors) ->
      " <> resource_singular <> "_views.form_view(
        " <> resource_singular <> "_form.from_form_data(form_data),
        errors,
      )
      |> root_layout.wrap(\"New " <> type_name <> "\")
      |> wisp.html_response(422)

    Ok(params) ->
      case " <> resource_singular <> "_repo.create(ctx.db, params) {
        Ok(item) ->
          wisp.redirect(\"/" <> resource_plural <> "/\" <> int.to_string(item.id))
          |> flash.set_flash(req, \"info\", \"" <> type_name <> " created\")

        Error(_) -> error_handler.internal_error(req)
      }
  }
}

pub fn edit(req: Request, ctx: Context, id: String) -> Response {
  case int.parse(id) {
    Error(_) -> error_handler.not_found(req)
    Ok(id) ->
      case " <> resource_singular <> "_repo.get(ctx.db, id) {
        Error(_) -> error_handler.not_found(req)
        Ok(item) ->
          " <> resource_singular <> "_views.form_view(" <> resource_singular <> "_form.from_" <> resource_singular <> "(item), [])
          |> root_layout.wrap(\"Edit " <> type_name <> "\")
          |> wisp.html_response(200)
      }
  }
}

pub fn update(req: Request, ctx: Context, id: String) -> Response {
  use form_data <- wisp.require_form(req)

  case int.parse(id) {
    Error(_) -> error_handler.not_found(req)
    Ok(id) ->
      case " <> resource_singular <> "_form.decode(form_data) {
        Error(errors) ->
          " <> resource_singular <> "_views.form_view(
            " <> resource_singular <> "_form.from_form_data(form_data),
            errors,
          )
          |> root_layout.wrap(\"Edit " <> type_name <> "\")
          |> wisp.html_response(422)

        Ok(params) ->
          case " <> resource_singular <> "_repo.update(ctx.db, id, params) {
            Ok(_) ->
              wisp.redirect(\"/" <> resource_plural <> "/\" <> int.to_string(id))
              |> flash.set_flash(req, \"info\", \"" <> type_name <> " updated\")

            Error(_) -> error_handler.internal_error(req)
          }
      }
  }
}

pub fn delete(req: Request, ctx: Context, id: String) -> Response {
  case int.parse(id) {
    Error(_) -> error_handler.not_found(req)
    Ok(id) -> {
      let _ = " <> resource_singular <> "_repo.delete(ctx.db, id)
      wisp.redirect(\"/" <> resource_plural <> "\")
      |> flash.set_flash(req, \"info\", \"" <> type_name <> " deleted\")
    }
  }
}
"
}

pub fn resource_domain_type(
  type_name: String,
  fields: List(#(String, String)),
) -> String {
  let field_defs =
    fields
    |> list_map_join(
      fn(field) {
        let #(name, gleam_type) = field
        "    " <> name <> ": " <> gleam_type <> ","
      },
      "\n",
    )

  "pub type " <> type_name <> " {
  " <> type_name <> "(
    id: Int,
" <> field_defs <> "
  )
}
"
}

// =============================================================================
// Helpers
// =============================================================================

fn list_map_join(
  items: List(a),
  f: fn(a) -> String,
  separator: String,
) -> String {
  items
  |> do_list_map_join(f, [])
  |> string.join(separator)
}

fn do_list_map_join(
  items: List(a),
  f: fn(a) -> String,
  acc: List(String),
) -> List(String) {
  case items {
    [] -> list_reverse(acc)
    [first, ..rest] -> do_list_map_join(rest, f, [f(first), ..acc])
  }
}

fn list_reverse(items: List(a)) -> List(a) {
  do_list_reverse(items, [])
}

fn do_list_reverse(items: List(a), acc: List(a)) -> List(a) {
  case items {
    [] -> acc
    [first, ..rest] -> do_list_reverse(rest, [first, ..acc])
  }
}
