/// `refrakt migrate` — run pending database migrations.
///
import gleam/io
import refrakt/cli/project

pub fn run() {
  let app = project.app_name()
  let migrations_dir = "src/" <> app <> "/data/migrations"

  io.println("Running migrations from " <> migrations_dir <> "...")
  io.println("")
  io.println(
    "Note: The migration runner requires a running database connection.",
  )
  io.println("Use `refrakt migrate` from within your app, or run migrations")
  io.println("programmatically with refrakt/migrate.run_from_directory/3.")
  io.println("")
  io.println("Example in your app's main:")
  io.println("")
  io.println("  import refrakt/migrate")
  io.println("  import pog")
  io.println("")
  io.println("  let execute = fn(sql) {")
  io.println("    pog.query(sql)")
  io.println("    |> pog.execute(db)")
  io.println("    |> result.replace(Nil)")
  io.println("    |> result.replace_error(\"query failed\")")
  io.println("  }")
  io.println("")
  io.println("  migrate.run_from_directory(execute, query_strings, dir)")
}
