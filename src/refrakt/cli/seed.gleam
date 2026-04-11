/// `refrakt seed` — run database seeds.
///
/// Generates a seed module if it doesn't exist, then runs it.
///
import gleam/io
import refrakt/cli/format
import refrakt/cli/project
import refrakt/cli/types.{NoDb, Postgres, Sqlite}
import simplifile

@external(erlang, "refrakt_build_ffi", "run_cmd")
fn run_cmd(cmd: String) -> String

pub fn run() {
  let app = project.app_name()
  let db = project.detect_db()
  let seed_path = "src/" <> app <> "/seed.gleam"

  case db {
    NoDb -> {
      io.println("No database configured.")
      io.println("Create a project with --db postgres or --db sqlite.")
    }
    _ -> {
      // Generate seed module if missing
      case simplifile.read(seed_path) {
        Ok(_) -> Nil
        Error(_) -> {
          let content = seed_module(app, db)
          let assert Ok(_) = simplifile.write(seed_path, content)
          format.format_files([seed_path])
          io.println("Created: " <> seed_path)
          io.println("Edit it to add your seed data, then run again.")
          io.println("")
        }
      }

      io.println("Running seeds...")
      let output = run_cmd("gleam run -m " <> app <> "/seed")
      io.println(output)
    }
  }
}

fn seed_module(app: String, db: types.DbChoice) -> String {
  case db {
    Postgres -> "/// Database seeds — populate with sample data.
///
/// Usage: gleam run -m " <> app <> "/seed
///
import gleam/io
import " <> app <> "/config
import " <> app <> "/data/repo

pub fn main() {
  let cfg = config.load()
  let assert Ok(db) = repo.connect(cfg)

  io.println(\"Seeding database...\")

  // Add your seed data here:
  // post_repo.create(db, PostParams(title: \"Hello World\", body: \"...\", published: True))
  // user_repo.create(db, \"admin@example.com\", auth.hash_password(\"password\"))

  io.println(\"Done.\")
}
"
    Sqlite -> "/// Database seeds — populate with sample data.
///
/// Usage: gleam run -m " <> app <> "/seed
///
import gleam/io
import " <> app <> "/config
import " <> app <> "/data/repo

pub fn main() {
  let cfg = config.load()
  let db_path = repo.database_path(cfg)

  io.println(\"Seeding database...\")

  // Add your seed data here:
  // task_repo.create(db_path, TaskParams(title: \"Buy groceries\", completed: False))

  io.println(\"Done.\")
}
"
    NoDb -> ""
  }
}
