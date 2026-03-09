/// `refrakt build` — compile islands to JavaScript.
///
/// Finds all Lustre island modules in web/islands/, compiles them
/// to JavaScript, and copies the output to priv/static/js/islands/.
///
import gleam/io
import gleam/list
import gleam/string
import refrakt/cli/project
import simplifile

@external(erlang, "refrakt_build_ffi", "run_cmd")
fn run_cmd(cmd: String) -> String

pub fn run() {
  let app = project.app_name()
  let islands_dir = "src/" <> app <> "/web/islands"
  let output_dir = "priv/static/js/islands"

  // Check if islands directory exists
  case simplifile.read_directory(islands_dir) {
    Error(_) -> {
      io.println("No islands found in " <> islands_dir)
      io.println("Generate one with: refrakt gen island <name>")
    }
    Ok(files) -> {
      let islands =
        files
        |> list.filter(fn(f) {
          string.ends_with(f, ".gleam") && !string.ends_with(f, "_embed.gleam")
        })

      case islands {
        [] -> {
          io.println("No island modules found in " <> islands_dir)
        }
        _ -> {
          io.println(
            "Building "
            <> int_to_string(list.length(islands))
            <> " island(s)...",
          )
          io.println("")

          // Ensure output directory exists
          let _ = simplifile.create_directory_all(output_dir)

          // Build JS target
          let build_output = run_cmd("gleam build --target javascript")
          case string.contains(build_output, "error") {
            True -> {
              io.println("Build failed:")
              io.println(build_output)
            }
            False -> {
              // Copy island JS files to priv/static/js/islands/
              list.each(islands, fn(island_file) {
                let name = string.replace(island_file, ".gleam", "")
                let source =
                  "build/dev/javascript/"
                  <> app
                  <> "/"
                  <> app
                  <> "/web/islands/"
                  <> name
                  <> ".mjs"
                let dest = output_dir <> "/" <> name <> ".js"

                case simplifile.read(source) {
                  Ok(content) -> {
                    let assert Ok(_) = simplifile.write(dest, content)
                    io.println("  " <> dest <> " ✓")
                  }
                  Error(_) -> {
                    io.println(
                      "  "
                      <> name
                      <> " — could not find compiled JS at "
                      <> source,
                    )
                  }
                }
              })
              io.println("")
              io.println("Done. Islands available at /static/js/islands/")
            }
          }
        }
      }
    }
  }
}

fn int_to_string(n: Int) -> String {
  case n {
    0 -> "0"
    1 -> "1"
    2 -> "2"
    3 -> "3"
    4 -> "4"
    5 -> "5"
    _ -> "several"
  }
}
