//// `refrakt migrate` — generate and run a migration script.
////
//// Creates a `src/<app>/migrate.gleam` module that connects to the
//// database and runs pending migrations, then executes it.
////

import gleam/io
import gleam/string
import refrakt_cli/format
import refrakt_cli/project
import refrakt_cli/types.{NoDb, Postgres, Sqlite}
import simplifile

@external(erlang, "refrakt_cli_build_ffi", "run_cmd")
fn run_cmd(cmd: String) -> String

pub fn run() {
  let app = project.app_name()
  let db = project.detect_db()
  let migrations_dir = "src/" <> app <> "/data/migrations"
  let migrate_module = "src/" <> app <> "/migrate.gleam"

  case db {
    NoDb -> {
      io.println("No database configured.")
      io.println("Create a project with --db postgres or --db sqlite.")
    }
    _ -> {
      // Check migrations exist
      case simplifile.read_directory(migrations_dir) {
        Error(_) -> {
          io.println("No migrations directory found at " <> migrations_dir)
          io.println(
            "Generate a resource first: gleam run -m refrakt_cli -- gen resource ...",
          )
        }
        Ok(files) -> {
          let sql_files =
            files
            |> list.filter(fn(f) { string.ends_with(f, ".sql") })

          case sql_files {
            [] -> io.println("No migration files found.")
            _ -> {
              // Generate the migrate module if it doesn't exist
              case simplifile.read(migrate_module) {
                Ok(existing) -> warn_if_outdated(existing, migrate_module)
                Error(_) -> {
                  let content = case db {
                    Postgres -> migrate_module_postgres(app)
                    Sqlite -> migrate_module_sqlite(app)
                    NoDb -> ""
                  }
                  let assert Ok(_) = simplifile.write(migrate_module, content)
                  format.format_files([migrate_module])
                  io.println("Created: " <> migrate_module)
                }
              }

              // Run it
              io.println("Running migrations...")
              io.println("")
              let output = run_cmd("gleam run -m " <> app <> "/migrate")
              io.println(output)
            }
          }
        }
      }
    }
  }
}

/// Modules generated before Refrakt 0.5 call `migrate.run_from_directory`,
/// which runs each file as one query (so multi-statement files fail on
/// Postgres) and does not use transactions.
fn warn_if_outdated(module: String, path: String) -> Nil {
  case string.contains(module, "run_from_directory") {
    True -> {
      io.println("Warning: " <> path <> " is outdated: it calls")
      io.println(
        "migrate.run_from_directory, which runs migrations without transactions",
      )
      io.println(
        "and fails on multi-statement files on Postgres. Delete it and run",
      )
      io.println("`refrakt migrate` again to regenerate it.")
      io.println("")
    }
    False -> Nil
  }
}

/// The generated `src/<app>/migrate.gleam` for a Postgres app.
pub fn migrate_module_postgres(app: String) -> String {
  "/// Run pending database migrations.
///
/// Usage: gleam run -m " <> app <> "/migrate
///
/// Each migration file runs in one transaction together with the row that
/// records it in `_migrations`, so a failing migration is rolled back whole.
///
import gleam/dynamic/decode
import gleam/int
import gleam/io
import gleam/list
import gleam/result
import gleam/string
import " <> app <> "/config
import " <> app <> "/data/repo
import pog
import refrakt/migrate

pub fn main() {
  let assert Ok(cfg) = config.load()
  let assert Ok(db) = repo.connect(cfg)
  let migrations_dir = \"src/" <> app <> "/data/migrations\"

  let query_strings = fn(sql: String) -> Result(List(String), String) {
    pog.query(sql)
    |> pog.returning(name_decoder())
    |> pog.execute(db)
    |> result.map(fn(returned) { returned.rows })
    |> result.map_error(describe_error)
  }

  // Run SQL scripts in one transaction: commit if all of them succeed,
  // roll back otherwise. A Postgres query runs a single statement, so each
  // script is split into its statements first.
  let transaction = fn(scripts: List(String)) -> Result(Nil, String) {
    pog.transaction(db, fn(conn) {
      scripts
      |> list.flat_map(migrate.split_statements)
      |> list.try_each(fn(statement) {
        pog.query(statement)
        |> pog.execute(conn)
        |> result.map_error(fn(error) {
          describe_error(error) <> \"\\n  in statement: \" <> statement
        })
      })
    })
    |> result.map_error(fn(error) {
      case error {
        pog.TransactionRolledBack(message) -> message
        pog.TransactionQueryError(error) -> describe_error(error)
      }
    })
  }

  case
    migrate.run(migrations_dir, query: query_strings, transaction: transaction)
  {
    Ok(count) ->
      io.println(\"Done. \" <> int.to_string(count) <> \" migration(s) applied.\")
    Error(err) -> io.println(\"Error: \" <> err)
  }
}

fn name_decoder() -> decode.Decoder(String) {
  use name <- decode.field(0, decode.string)
  decode.success(name)
}

fn describe_error(error: pog.QueryError) -> String {
  case error {
    pog.PostgresqlError(code:, name:, message:) ->
      message <> \" (\" <> name <> \", SQLSTATE \" <> code <> \")\"
    pog.ConstraintViolated(message:, constraint:, ..) ->
      message <> \" (constraint \" <> constraint <> \")\"
    pog.ConnectionUnavailable -> \"could not connect to the database\"
    pog.QueryTimeout -> \"the query timed out\"
    _ -> string.inspect(error)
  }
}
"
}

/// The generated `src/<app>/migrate.gleam` for a SQLite app.
pub fn migrate_module_sqlite(app: String) -> String {
  "/// Run pending database migrations.
///
/// Usage: gleam run -m " <> app <> "/migrate
///
/// Each migration file runs in one transaction together with the row that
/// records it in `_migrations`, so a failing migration is rolled back whole.
///
import gleam/dynamic/decode
import gleam/int
import gleam/io
import gleam/list
import gleam/result
import " <> app <> "/config
import " <> app <> "/data/repo
import refrakt/migrate
import sqlight

pub fn main() {
  let assert Ok(cfg) = config.load()
  let db_path = repo.database_path(cfg)
  let migrations_dir = \"src/" <> app <> "/data/migrations\"

  use conn <- sqlight.with_connection(db_path)

  let query_strings = fn(sql: String) -> Result(List(String), String) {
    sqlight.query(sql, on: conn, with: [], expecting: name_decoder())
    |> result.map_error(fn(error) { error.message })
  }

  // Run SQL scripts in one transaction: commit if all of them succeed,
  // roll back otherwise. sqlight.exec runs every statement in a script.
  let transaction = fn(scripts: List(String)) -> Result(Nil, String) {
    use _ <- result.try(exec(\"BEGIN\", conn))
    let outcome =
      list.try_each(scripts, fn(script) { exec(script, conn) })
      |> result.try(fn(_) { exec(\"COMMIT\", conn) })
    case outcome {
      Ok(Nil) -> Ok(Nil)
      Error(error) -> {
        let _ = exec(\"ROLLBACK\", conn)
        Error(error)
      }
    }
  }

  case
    migrate.run(migrations_dir, query: query_strings, transaction: transaction)
  {
    Ok(count) ->
      io.println(\"Done. \" <> int.to_string(count) <> \" migration(s) applied.\")
    Error(err) -> io.println(\"Error: \" <> err)
  }
}

fn exec(sql: String, conn: sqlight.Connection) -> Result(Nil, String) {
  sqlight.exec(sql, on: conn)
  |> result.map_error(fn(error) { error.message })
}

fn name_decoder() -> decode.Decoder(String) {
  use name <- decode.field(0, decode.string)
  decode.success(name)
}
"
}

import gleam/list
