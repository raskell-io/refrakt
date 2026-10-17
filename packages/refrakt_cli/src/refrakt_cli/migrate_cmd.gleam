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
                Ok(_) -> Nil
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

fn migrate_module_postgres(app: String) -> String {
  "/// Run pending database migrations.
///
/// Usage: gleam run -m " <> app <> "/migrate
///
import gleam/dynamic/decode
import gleam/int
import gleam/io
import gleam/result
import " <> app <> "/config
import " <> app <> "/data/repo
import pog
import refrakt/migrate

pub fn main() {
  let cfg = config.load()
  let assert Ok(db) = repo.connect(cfg)
  let migrations_dir = \"src/" <> app <> "/data/migrations\"

  let execute = fn(sql: String) -> Result(Nil, String) {
    pog.query(sql)
    |> pog.execute(db)
    |> result.replace(Nil)
    |> result.replace_error(\"query failed\")
  }

  let query_strings = fn(sql: String) -> Result(List(String), String) {
    pog.query(sql)
    |> pog.returning(name_decoder())
    |> pog.execute(db)
    |> result.map(fn(r) { r.rows })
    |> result.replace_error(\"query failed\")
  }

  case migrate.run_from_directory(execute, query_strings, migrations_dir) {
    Ok(count) ->
      io.println(\"Done. \" <> int.to_string(count) <> \" migration(s) applied.\")
    Error(err) -> io.println(\"Error: \" <> err)
  }
}

fn name_decoder() -> decode.Decoder(String) {
  use name <- decode.field(0, decode.string)
  decode.success(name)
}
"
}

fn migrate_module_sqlite(app: String) -> String {
  "/// Run pending database migrations.
///
/// Usage: gleam run -m " <> app <> "/migrate
///
import gleam/dynamic/decode
import gleam/int
import gleam/io
import gleam/result
import " <> app <> "/config
import " <> app <> "/data/repo
import refrakt/migrate
import sqlight

pub fn main() {
  let cfg = config.load()
  let db_path = repo.database_path(cfg)
  let migrations_dir = \"src/" <> app <> "/data/migrations\"

  use conn <- sqlight.with_connection(db_path)

  let execute = fn(sql: String) -> Result(Nil, String) {
    sqlight.exec(sql, conn)
    |> result.replace_error(\"query failed\")
  }

  let query_strings = fn(sql: String) -> Result(List(String), String) {
    sqlight.query(sql, on: conn, with: [], expecting: name_decoder())
    |> result.replace_error(\"query failed\")
  }

  case migrate.run_from_directory(execute, query_strings, migrations_dir) {
    Ok(count) ->
      io.println(\"Done. \" <> int.to_string(count) <> \" migration(s) applied.\")
    Error(err) -> io.println(\"Error: \" <> err)
  }
}

fn name_decoder() -> decode.Decoder(String) {
  use name <- decode.field(0, decode.string)
  decode.success(name)
}
"
}

import gleam/list
