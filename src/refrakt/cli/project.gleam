/// Project utilities — reads gleam.toml to discover the app name.
///
import simplifile
import tom

/// Read the project name from gleam.toml in the current directory.
pub fn app_name() -> String {
  let assert Ok(content) = simplifile.read("gleam.toml")
  let assert Ok(parsed) = tom.parse(content)
  let assert Ok(name) = tom.get_string(parsed, ["name"])
  name
}
