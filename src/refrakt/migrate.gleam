/// Migration runner for Refrakt applications.
///
/// Reads SQL files from a migrations directory, tracks applied migrations
/// in a `_migrations` table, and runs pending ones in order.
///
/// ## Usage from CLI
///
/// ```
/// refrakt migrate
/// ```
///
/// ## Usage from code
///
/// ```gleam
/// import refrakt/migrate
/// migrate.run(db, "src/my_app/data/migrations")
/// ```
///
import gleam/int
import gleam/io
import gleam/list
import gleam/result
import gleam/string
import simplifile

/// A migration file with its number and name.
pub type Migration {
  Migration(number: Int, name: String, filename: String, sql: String)
}

/// Run all pending migrations in a directory.
/// Returns the number of migrations applied.
pub fn run_from_directory(
  db_execute: fn(String) -> Result(Nil, String),
  db_query_strings: fn(String) -> Result(List(String), String),
  migrations_dir: String,
) -> Result(Int, String) {
  // Ensure migrations table exists
  use _ <- result.try(db_execute(
    "CREATE TABLE IF NOT EXISTS _migrations (
      name TEXT PRIMARY KEY,
      applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    )",
  ))

  // Get already applied migrations
  use applied <- result.try(db_query_strings(
    "SELECT name FROM _migrations ORDER BY name",
  ))

  // Read migration files
  use files <- result.try(
    simplifile.read_directory(migrations_dir)
    |> result.replace_error(
      "Could not read migrations directory: " <> migrations_dir,
    ),
  )

  // Parse and sort migration files
  let migrations =
    files
    |> list.filter(fn(f) { string.ends_with(f, ".sql") })
    |> list.filter_map(fn(filename) {
      parse_migration(migrations_dir, filename)
    })
    |> list.sort(fn(a, b) { int.compare(a.number, b.number) })

  // Find pending migrations
  let pending =
    migrations
    |> list.filter(fn(m) { !list.contains(applied, m.filename) })

  // Apply pending migrations
  use _ <- result.try(apply_migrations(pending, db_execute))

  Ok(list.length(pending))
}

fn parse_migration(dir: String, filename: String) -> Result(Migration, Nil) {
  // Extract number from filename like "001_create_posts.sql"
  let parts = string.split(filename, "_")
  case parts {
    [num_str, ..rest] ->
      case int.parse(num_str) {
        Ok(num) -> {
          let name =
            rest
            |> string.join("_")
            |> string.replace(".sql", "")
          case simplifile.read(dir <> "/" <> filename) {
            Ok(sql) ->
              Ok(Migration(
                number: num,
                name: name,
                filename: filename,
                sql: sql,
              ))
            Error(_) -> Error(Nil)
          }
        }
        Error(_) -> Error(Nil)
      }
    _ -> Error(Nil)
  }
}

fn apply_migrations(
  migrations: List(Migration),
  db_execute: fn(String) -> Result(Nil, String),
) -> Result(Nil, String) {
  case migrations {
    [] -> Ok(Nil)
    [migration, ..rest] -> {
      io.println("  " <> migration.filename <> " ...")
      use _ <- result.try(
        db_execute(migration.sql)
        |> result.map_error(fn(e) {
          "Migration " <> migration.filename <> " failed: " <> e
        }),
      )
      use _ <- result.try(db_execute(
        "INSERT INTO _migrations (name) VALUES ('" <> migration.filename <> "')",
      ))
      io.println("  " <> migration.filename <> " ✓")
      apply_migrations(rest, db_execute)
    }
  }
}
