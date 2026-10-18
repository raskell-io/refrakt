//// The generator manifest, `.refrakt/generated.toml`.
////
//// `refrakt new` creates it and every generator that writes templates
//// (`gen page`, `gen resource`, `gen auth`, `gen island`, `gen live`)
//// appends its arguments. `refrakt diff` replays the entries, in order, to
//// render what the current templates would generate for the app.
////
//// ```toml
//// [new]
//// name = "my_app"
//// db = "sqlite"
////
//// [[gen]]
//// args = ["resource", "posts", "title:string", "body:text"]
//// ```
////

import gleam/dict
import gleam/list
import gleam/result
import gleam/string
import refrakt_cli/types.{type DbChoice, NoDb, Postgres, Sqlite}
import simplifile
import tom

pub const path = ".refrakt/generated.toml"

/// What `refrakt new` was run with, and the generators run since.
pub type Manifest {
  Manifest(name: String, db: DbChoice, gens: List(List(String)))
}

const header =
  "# Generators run in this app, in order, recorded by refrakt_cli.
# `refrakt diff` replays them to show what the current templates generate
# for this app. Commit this file. If you delete a generated resource or
# page, delete its entry too.
"

/// The manifest `refrakt new` writes for a new app.
pub fn new_content(name: String, db: DbChoice) -> String {
  to_toml(Manifest(name: name, db: db, gens: []))
}

pub fn to_toml(manifest: Manifest) -> String {
  let gens =
    list.map(manifest.gens, fn(args) {
      "\n[[gen]]\nargs = " <> string_array(args) <> "\n"
    })
  header
  <> "\n[new]\nname = "
  <> quote(manifest.name)
  <> "\ndb = "
  <> quote(db_name(manifest.db))
  <> "\n"
  <> string.concat(gens)
}

/// Read `.refrakt/generated.toml` from the directory `dir`.
pub fn read(dir: String) -> Result(Manifest, String) {
  let file = dir <> "/" <> path
  use content <- result.try(
    simplifile.read(file) |> result.replace_error("cannot read " <> path),
  )
  use parsed <- result.try(
    tom.parse(content) |> result.replace_error(path <> " is not valid TOML"),
  )
  use name <- result.try(
    tom.get_string(parsed, ["new", "name"])
    |> result.replace_error(path <> " has no [new] name"),
  )
  let db = case tom.get_string(parsed, ["new", "db"]) {
    Ok("postgres") -> Postgres
    Ok("sqlite") -> Sqlite
    _ -> NoDb
  }
  let gens = case dict.get(parsed, "gen") {
    Ok(tom.ArrayOfTables(tables)) ->
      list.filter_map(tables, fn(table) {
        use args <- result.try(
          tom.get_array(table, ["args"]) |> result.replace_error(Nil),
        )
        list.try_map(args, fn(arg) {
          tom.as_string(arg) |> result.replace_error(Nil)
        })
      })
    _ -> []
  }
  Ok(Manifest(name: name, db: db, gens: gens))
}

/// Record a generator run in the manifest of the app in the current
/// directory. Running the same generator with the same arguments again
/// records nothing. Apps created before the manifest existed have none;
/// for those this does nothing and `refrakt diff` infers the generators
/// from the app's files instead.
pub fn record(args: List(String)) -> Nil {
  case simplifile.is_file(path), read(".") {
    Ok(True), Ok(manifest) ->
      case list.contains(manifest.gens, args) {
        True -> Nil
        False -> {
          let entry = "\n[[gen]]\nargs = " <> string_array(args) <> "\n"
          let _ = simplifile.append(path, entry)
          Nil
        }
      }
    _, _ -> Nil
  }
}

pub fn db_name(db: DbChoice) -> String {
  case db {
    Postgres -> "postgres"
    Sqlite -> "sqlite"
    NoDb -> "none"
  }
}

fn string_array(items: List(String)) -> String {
  "[" <> string.join(list.map(items, quote), ", ") <> "]"
}

fn quote(value: String) -> String {
  let escaped =
    value
    |> string.replace("\\", "\\\\")
    |> string.replace("\"", "\\\"")
  "\"" <> escaped <> "\""
}
