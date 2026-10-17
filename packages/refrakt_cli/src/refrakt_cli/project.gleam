//// Project utilities — reads gleam.toml to discover the app name and DB choice.
////

import gleam/string
import refrakt_cli/types.{type DbChoice, NoDb, Postgres, Sqlite}
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

/// Add a dependency to the `[dependencies]` table of gleam.toml, unless the
/// project already depends on it. Returns `True` when gleam.toml changed.
pub fn add_dependency(name: String, requirement: String) -> Bool {
  let assert Ok(content) = simplifile.read("gleam.toml")
  let assert Ok(parsed) = tom.parse(content)

  case tom.get(parsed, ["dependencies", name]) {
    Ok(_) -> False
    Error(_) -> {
      let line = name <> " = \"" <> requirement <> "\""
      let assert Ok(_) =
        simplifile.write("gleam.toml", insert_dependency(content, line))
      True
    }
  }
}

/// Append `line` to the end of the `[dependencies]` table, creating the
/// table if the file has none.
fn insert_dependency(content: String, line: String) -> String {
  case string.split_once(content, "[dependencies]\n") {
    Error(_) ->
      string.trim_end(content) <> "\n\n[dependencies]\n" <> line <> "\n"
    Ok(#(before, after)) -> {
      let #(table, rest) = case string.split_once(after, "\n[") {
        Ok(#(table, rest)) -> #(table, "\n[" <> rest)
        Error(_) -> #(after, "")
      }
      let table = case string.trim_end(table) {
        "" -> line
        entries -> entries <> "\n" <> line
      }
      before <> "[dependencies]\n" <> table <> "\n" <> rest
    }
  }
}
