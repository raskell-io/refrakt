/// Project utilities — reads gleam.toml to discover the app name and DB choice.
///
import gleam/string
import refrakt/cli/types.{type DbChoice, NoDb, Postgres, Sqlite}
import simplifile
import tom

/// Read the project name from gleam.toml in the current directory.
pub fn app_name() -> String {
  let assert Ok(content) = simplifile.read("gleam.toml")
  let assert Ok(parsed) = tom.parse(content)
  let assert Ok(name) = tom.get_string(parsed, ["name"])
  name
}

/// Detect DB choice from gleam.toml dependencies.
pub fn detect_db() -> DbChoice {
  let assert Ok(content) = simplifile.read("gleam.toml")
  case string.contains(content, "pog") {
    True -> Postgres
    False ->
      case string.contains(content, "sqlight") {
        True -> Sqlite
        False -> NoDb
      }
  }
}
