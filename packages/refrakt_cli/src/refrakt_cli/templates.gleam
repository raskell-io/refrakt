//// File templates for code generation.
////
//// Each function returns the complete file content as a String.
//// Templates use string concatenation — no macros, no interpolation engine.
////

import gleam/string
import refrakt_cli/types.{type DbChoice, NoDb, Postgres, Sqlite}

// =============================================================================
// Project files
// =============================================================================

pub fn gleam_toml(name: String, db: DbChoice) -> String {
  let db_dep = case db {
    Postgres -> "\npog = \">= 4.1.0 and < 5.0.0\""
    Sqlite -> "\nsqlight = \">= 1.2.0 and < 2.0.0\""
    NoDb -> ""
  }

  "name = \"" <> name <> "\"
version = \"0.1.0\"
target = \"erlang\"
gleam = \">= 1.14.0\"

[dependencies]
gleam_stdlib = \">= 0.70.0 and < 2.0.0\"
gleam_erlang = \">= 1.3.0 and < 2.0.0\"
gleam_http = \">= 4.5.0 and < 5.0.0\"
envoy = \">= 1.2.0 and < 2.0.0\"
mist = \">= 6.0.0 and < 7.0.0\"
wisp = \">= 2.2.2 and < 3.0.0\"
lustre = \">= 5.7.0 and < 6.0.0\"
gleam_json = \">= 3.1.0 and < 4.0.0\"
refrakt = \">= 0.5.0 and < 1.0.0\"" <> db_dep <> "

[dev-dependencies]
gleeunit = \">= 1.11.0 and < 2.0.0\"
refrakt_cli = \">= 0.5.0 and < 1.0.0\"
"
}

pub fn gitignore() -> String {
  "/build/
.DS_Store
*.db
erl_crash.dump
"
}

pub fn readme(name: String, db: DbChoice) -> String {
  let test_database = case db {
    Postgres -> "
Tests that use the database run against `" <> name <> "_test` (or
`DATABASE_URL`), each in a transaction that is rolled back. Create it once:

```bash
createdb -h localhost -U postgres " <> name <> "_test
```
"
    Sqlite ->
      "
Tests that use the database get a fresh in-memory SQLite database each,
with the migrations applied.
"
    NoDb -> ""
  }

  "# " <> name <> "

A web application built with [Refrakt](https://github.com/raskell-io/refrakt).

## Development

```bash
gleam run    # Start the server at http://localhost:4000
gleam test   # Run tests
```
" <> test_database <> "
## Generators

The Refrakt code generator is a dev-dependency of this project:

```bash
gleam run -m refrakt_cli -- gen resource posts title:string body:text
gleam run -m refrakt_cli -- gen page about
gleam run -m refrakt_cli -- routes
gleam run -m refrakt_cli -- help
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

  "import envoy
import gleam/erlang/process
import gleam/io
import mist
import " <> name <> "/config
import " <> name <> "/context
import " <> name <> "/router
import wisp
import wisp/wisp_mist" <> db_import <> "

pub fn main() {
  wisp.configure_logger()
  warn_if_app_env_unset()

  let cfg = case config.load() {
    Ok(cfg) -> cfg
    Error(error) -> {
      io.println_error(\"Refusing to start: \" <> config.describe_error(error))
      halt(1)
    }
  }" <> db_ctx <> "

  let assert Ok(_) =
    wisp_mist.handler(router.handle_request(_, ctx), cfg.secret_key_base)
    |> mist.new
    |> mist.port(cfg.port)
    |> mist.start

  io.println(\"Listening on http://localhost:\" <> cfg.port_string)
  process.sleep_forever()
}

/// Without APP_ENV the app runs in development mode, which shows stack
/// traces and request details when a handler crashes. That is right for
/// `refrakt dev` (which sets APP_ENV=dev) but not for a deployment.
fn warn_if_app_env_unset() -> Nil {
  case envoy.get(\"APP_ENV\") {
    Ok(_) -> Nil
    Error(_) ->
      wisp.log_warning(
        \"APP_ENV is not set, so this app runs in development mode and shows \"
        <> \"stack traces and request details on errors. Set APP_ENV=prod in \"
        <> \"production.\",
      )
  }
}

/// Stop the Erlang VM with an exit status.
@external(erlang, \"erlang\", \"halt\")
fn halt(status: Int) -> a
"
}

pub fn config_module(name: String) -> String {
  "import envoy
import gleam/int
import gleam/result
import gleam/string

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

/// Why `load` refused the environment.
pub type ConfigError {
  /// APP_ENV=prod, but SECRET_KEY_BASE is not set.
  MissingSecretKeyBase
  /// APP_ENV=prod, but SECRET_KEY_BASE is the development key below.
  DevelopmentSecretKeyBase
  /// SECRET_KEY_BASE is shorter than 64 bytes.
  ShortSecretKeyBase(bytes: Int)
}

/// Signs cookies in development and test when SECRET_KEY_BASE is unset.
/// It is in your source code, so production refuses to use it.
const development_secret_key_base = \"dev-secret-key-base-that-is-at-least-64-bytes-long-for-security!!\"

pub fn load() -> Result(Config, ConfigError) {
  let port =
    envoy.get(\"PORT\")
    |> result.try(int.parse)
    |> result.unwrap(4000)

  let env = case envoy.get(\"APP_ENV\") {
    Ok(\"prod\") -> Prod
    Ok(\"test\") -> Test
    _ -> Dev
  }

  use secret_key_base <- result.try(load_secret_key_base(env))

  Ok(Config(
    port: port,
    port_string: int.to_string(port),
    secret_key_base: secret_key_base,
    env: env,
  ))
}

/// Production needs its own secret of at least 64 bytes; development and
/// test fall back to the development key.
fn load_secret_key_base(env: Env) -> Result(String, ConfigError) {
  case envoy.get(\"SECRET_KEY_BASE\"), env {
    Error(_), Prod -> Error(MissingSecretKeyBase)
    Error(_), _ -> Ok(development_secret_key_base)
    Ok(key), Prod if key == development_secret_key_base ->
      Error(DevelopmentSecretKeyBase)
    Ok(key), _ ->
      case string.byte_size(key) {
        bytes if bytes < 64 -> Error(ShortSecretKeyBase(bytes))
        _ -> Ok(key)
      }
  }
}

pub fn describe_error(error: ConfigError) -> String {
  let generate = \" Generate one with `openssl rand -hex 64`.\"
  case error {
    MissingSecretKeyBase ->
      \"SECRET_KEY_BASE is not set. Production needs its own secret key.\"
      <> generate
    DevelopmentSecretKeyBase ->
      \"SECRET_KEY_BASE is the development key from src/" <> name <> "/config.gleam, \"
      <> \"which is not secret.\"
      <> generate
    ShortSecretKeyBase(bytes) ->
      \"SECRET_KEY_BASE is \"
      <> int.to_string(bytes)
      <> \" bytes long; it must be at least 64 bytes.\"
      <> generate
  }
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
import " <> name <> "/config
import " <> name <> "/context.{type Context}
import " <> name <> "/web/error_handler
import " <> name <> "/web/home_handler
import refrakt/csrf
import refrakt/dev_error
import wisp.{type Request, type Response}

pub fn handle_request(req: Request, ctx: Context) -> Response {
  use req <- middleware(req, ctx)

  case wisp.path_segments(req), req.method {
    [], http.Get -> home_handler.index(req, ctx)
    _, _ -> error_handler.not_found(req)
  }
}

fn middleware(
  req: Request,
  ctx: Context,
  next: fn(Request) -> Response,
) -> Response {
  let req = wisp.method_override(req)
  use <- wisp.log_request(req)
  use <- rescue_crashes(req, ctx)
  // Forms posted from another site get 403 Forbidden; see refrakt/csrf.
  use req <- csrf.protect(req)
  use <- wisp.serve_static(req, under: \"/static\", from: priv_static())
  next(req)
}

/// In development a crash shows the detailed error page (error, stack
/// trace, request). Everywhere else it is logged and the visitor gets a
/// plain 500, so internals never leak in production.
fn rescue_crashes(
  req: Request,
  ctx: Context,
  next: fn() -> Response,
) -> Response {
  case ctx.config.env {
    config.Dev -> dev_error.rescue(req, next)
    config.Test | config.Prod -> wisp.rescue_crashes(next)
  }
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
import envoy
import gleam/erlang/process
import gleam/result
import pog

/// Connect to PostgreSQL. The connection URL comes from `DATABASE_URL`;
/// without it, development and test use a local server as the
/// `postgres` user.
pub fn connect(cfg: Config) -> Result(pog.Connection, Nil) {
  let default_url = case cfg.env {
    config.Test -> \"postgres://postgres@localhost:5432/" <> name <> "_test\"
    _ -> \"postgres://postgres@localhost:5432/" <> name <> "_dev\"
  }
  let db_url = envoy.get(\"DATABASE_URL\") |> result.unwrap(default_url)

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

pub fn router_test(name: String, db: DbChoice) -> String {
  let #(context_imports, context_value) = test_context(db)

  "import gleam/http
import gleeunit/should
import " <> name <> "/config
import " <> name <> "/context.{type Context}
import " <> name <> "/router" <> context_imports <> "
import wisp/simulate

pub fn home_page_test() {
  let response =
    simulate.request(http.Get, \"/\")
    |> router.handle_request(test_context())

  response.status
  |> should.equal(200)
}

pub fn cross_site_post_is_rejected_test() {
  let response =
    simulate.request(http.Post, \"/\")
    |> simulate.header(\"origin\", \"https://evil.example\")
    |> router.handle_request(test_context())

  response.status
  |> should.equal(403)
}

pub fn same_origin_post_passes_csrf_check_test() {
  // browser_request sends an Origin header matching the host, as a
  // browser does when it submits one of this app's forms. No route
  // handles POST /, so the request gets past the CSRF check to a 404.
  let response =
    simulate.browser_request(http.Post, \"/\")
    |> router.handle_request(test_context())

  response.status
  |> should.equal(404)
}

fn test_context() -> Context {
  let assert Ok(cfg) = config.load()
  " <> context_value <> "
}
"
}

/// `test/<app>/support/test_db.gleam`: a real, migrated database for
/// tests that need one. `gen resource` and `gen auth` write it when it is
/// missing.
pub fn test_db_module(name: String, db: DbChoice) -> String {
  case db {
    Postgres -> test_db_postgres(name)
    Sqlite -> test_db_sqlite(name)
    NoDb -> ""
  }
}

fn test_db_postgres(name: String) -> String {
  "//// A real, migrated database for tests.
////
//// `with_context` runs a test with a `Context` whose database is a
//// transaction on the test database, with the migrations in
//// src/" <> name <> "/data/migrations applied inside it. The transaction is
//// always rolled back, also when the test fails, so every test starts
//// from empty tables and leaves nothing behind.
////
//// ```gleam
//// pub fn create_post_test() {
////   use ctx <- test_db.with_context()
////   // ... send requests through router.handle_request(req, ctx)
//// }
//// ```
////
//// The test database is `DATABASE_URL`, or
//// postgres://postgres@localhost:5432/" <> name <> "_test when it is unset.
//// Create it once:
////
////     createdb -h localhost -U postgres " <> name <> "_test
////
//// Everything a test does runs in that one transaction, so the code under
//// test must not start its own with `pog.transaction`: its COMMIT would
//// end the test's transaction. After a failing query, such as a unique
//// constraint violation, Postgres refuses further queries in the
//// transaction, so make that the last query of a test.

import envoy
import gleam/dynamic/decode
import gleam/erlang/process
import gleam/list
import gleam/result
import gleam/string
import " <> name <> "/config
import " <> name <> "/context.{type Context}
import pog
import refrakt/migrate
import refrakt/testing

const default_url = \"postgres://postgres@localhost:5432/" <> name <> "_test\"

const migrations_dir = \"src/" <> name <> "/data/migrations\"

/// Run `body` with a context on a rolled-back transaction of the test
/// database.
pub fn with_context(body: fn(Context) -> a) -> a {
  let assert Ok(cfg) = config.load()
  let cfg = config.Config(..cfg, env: config.Test)
  use #(_pid, pool) <- testing.with_database(open: start_pool, close: stop_pool)

  let outcome =
    pog.transaction(pool, fn(conn) {
      // pog rolls the transaction back when the callback returns an Error,
      // so the test's result travels out inside one.
      Error(
        migrate_in_transaction(conn)
        |> result.map(fn(_) { body(context.Context(config: cfg, db: conn)) }),
      )
    })

  case outcome {
    Error(pog.TransactionRolledBack(Ok(value))) -> value
    Error(pog.TransactionRolledBack(Error(message))) -> panic as message
    Error(pog.TransactionQueryError(error)) ->
      panic as {
        \"Could not use the test database at \"
        <> database_url()
        <> \": \"
        <> string.inspect(error)
        <> \". Is Postgres running? Create the database with \"
        <> \"`createdb -h localhost -U postgres " <> name <> "_test`.\"
      }
    Ok(_) -> panic as \"unreachable: the test transaction is always rolled back\"
  }
}

fn database_url() -> String {
  envoy.get(\"DATABASE_URL\")
  |> result.unwrap(default_url)
}

/// A pool of one connection, for one test.
fn start_pool() -> Result(#(process.Pid, pog.Connection), String) {
  let name = process.new_name(prefix: \"" <> name <> "_test_db\")
  use config <- result.try(
    pog.url_config(name, database_url())
    |> result.replace_error(\"not a Postgres URL: \" <> database_url()),
  )
  config
  |> pog.pool_size(1)
  |> pog.start
  |> result.map(fn(started) { #(started.pid, started.data) })
  |> result.map_error(string.inspect)
}

/// The pool was started by this process, so an exit signal from it shuts
/// the pool down cleanly and closes its connection.
fn stop_pool(pool: #(process.Pid, pog.Connection)) -> Nil {
  process.send_exit(pool.0)
}

/// Apply the migrations on the test's connection. They run statement by
/// statement without a transaction of their own: the test's transaction
/// holds them, and its rollback undoes them.
fn migrate_in_transaction(conn: pog.Connection) -> Result(Int, String) {
  migrate.run_quietly(
    migrations_dir,
    query: fn(sql) {
      pog.query(sql)
      |> pog.returning(decode.at([0], decode.string))
      |> pog.execute(conn)
      |> result.map(fn(returned) { returned.rows })
      |> result.map_error(string.inspect)
    },
    transaction: fn(scripts) {
      scripts
      |> list.flat_map(migrate.split_statements)
      |> list.try_each(fn(statement) {
        pog.query(statement)
        |> pog.execute(conn)
        |> result.map_error(fn(error) {
          string.inspect(error) <> \"\\n  in statement: \" <> statement
        })
      })
    },
  )
  |> result.map_error(fn(error) {
    \"Could not migrate the test database: \" <> error
  })
}
"
}

fn test_db_sqlite(name: String) -> String {
  "//// A real, migrated database for tests.
////
//// `with_context` runs a test with a `Context` on a fresh in-memory
//// SQLite database, with the migrations in src/" <> name <> "/data/migrations
//// applied. The database lives as long as the test: when the test ends,
//// also when it fails, it is gone, so every test starts from empty tables.
////
//// ```gleam
//// pub fn create_post_test() {
////   use ctx <- test_db.with_context()
////   // ... send requests through router.handle_request(req, ctx)
//// }
//// ```

import gleam/dynamic/decode
import gleam/int
import gleam/list
import gleam/result
import " <> name <> "/config
import " <> name <> "/context.{type Context}
import refrakt/migrate
import refrakt/testing
import sqlight

const migrations_dir = \"src/" <> name <> "/data/migrations\"

/// Run `body` with a context on a fresh, migrated in-memory database.
pub fn with_context(body: fn(Context) -> a) -> a {
  let assert Ok(cfg) = config.load()
  let cfg = config.Config(..cfg, env: config.Test)
  // Repos open a connection per query from `ctx.db_path`. A named
  // in-memory database with a shared cache is the same database for all
  // of them while one connection stays open; it disappears when the last
  // connection closes.
  let path =
    \"file:" <> name <> "_test_\"
    <> int.to_string(int.random(1_000_000_000))
    <> \"?mode=memory&cache=shared\"
  use _keep_open <- testing.with_database(
    open: fn() { open(path) },
    close: close,
  )
  body(context.Context(config: cfg, db_path: path))
}

fn open(path: String) -> Result(sqlight.Connection, String) {
  use conn <- result.try(
    sqlight.open(path)
    |> result.map_error(fn(error) { error.message }),
  )
  case migrate(conn) {
    Ok(_) -> Ok(conn)
    Error(error) -> {
      close(conn)
      Error(error)
    }
  }
}

fn close(conn: sqlight.Connection) -> Nil {
  let _ = sqlight.close(conn)
  Nil
}

fn migrate(conn: sqlight.Connection) -> Result(Int, String) {
  migrate.run_quietly(
    migrations_dir,
    query: fn(sql) {
      sqlight.query(sql, on: conn, with: [], expecting: decode.at([0], decode.string))
      |> result.map_error(fn(error) { error.message })
    },
    // A fresh database per test: a failed migration fails the test, so
    // there is nothing to roll back.
    transaction: fn(scripts) {
      list.try_each(scripts, fn(script) {
        sqlight.exec(script, on: conn)
        |> result.map_error(fn(error) { error.message })
      })
    },
  )
  |> result.map_error(fn(error) { \"the migrations failed: \" <> error })
}
"
}

/// Imports and the `Context` expression a generated test uses to call the
/// router. The database is never opened: the tests only take paths that
/// do not reach a repo.
pub fn test_context(db: DbChoice) -> #(String, String) {
  case db {
    Postgres -> #(
      "\nimport gleam/erlang/process\nimport pog",
      "context.Context(
    config: cfg,
    db: pog.named_connection(process.new_name(prefix: \"test_db\")),
  )",
    )
    Sqlite -> #("", "context.Context(config: cfg, db_path: \":memory:\")")
    NoDb -> #("", "context.Context(config: cfg)")
  }
}

// =============================================================================
// Resource generator templates
// =============================================================================

pub fn resource_handler(
  app_name: String,
  resource_plural: String,
  resource_singular: String,
  type_name: String,
  _first_field: String,
  db: DbChoice,
) -> String {
  let db_arg = case db {
    Sqlite -> "ctx.db_path"
    _ -> "ctx.db"
  }
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
  let items = " <> resource_singular <> "_repo.list(" <> db_arg <> ")
  " <> resource_singular <> "_views.index_view(items)
  |> root_layout.wrap(\"" <> type_name <> "s\")
  |> wisp.html_response(200)
}

pub fn show(req: Request, ctx: Context, id: String) -> Response {
  case int.parse(id) {
    Error(_) -> error_handler.not_found(req)
    Ok(id) ->
      case " <> resource_singular <> "_repo.get(" <> db_arg <> ", id) {
        Error(_) -> error_handler.not_found(req)
        Ok(item) ->
          " <> resource_singular <> "_views.show_view(item)
          |> root_layout.wrap(\"" <> type_name <> "\")
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
      case " <> resource_singular <> "_repo.create(" <> db_arg <> ", params) {
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
      case " <> resource_singular <> "_repo.get(" <> db_arg <> ", id) {
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
          case " <> resource_singular <> "_repo.update(" <> db_arg <> ", id, params) {
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
      let _ = " <> resource_singular <> "_repo.delete(" <> db_arg <> ", id)
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
