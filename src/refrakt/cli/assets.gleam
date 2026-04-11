/// `refrakt assets` — set up and build CSS/JS assets.
///
/// Configures Tailwind CSS and esbuild for the project.
///
import gleam/io
import gleam/string
import refrakt/cli/project
import simplifile

@external(erlang, "refrakt_build_ffi", "run_cmd")
fn run_cmd(cmd: String) -> String

pub fn setup() {
  let app = project.app_name()

  io.println("Setting up asset pipeline...")
  io.println("")

  // Check for npx/tailwind
  let has_npx = string.length(string.trim(run_cmd("which npx"))) > 0

  case has_npx {
    False -> {
      io.println("npx not found. Install Node.js for Tailwind CSS support.")
      io.println("Or use the default app.css in priv/static/css/")
    }
    True -> {
      // Create tailwind config
      let tailwind_config =
        "/** @type {import('tailwindcss').Config} */
module.exports = {
  content: [\"./src/**/*.gleam\"],
  theme: { extend: {} },
  plugins: [],
}
"
      let _ = simplifile.write("tailwind.config.js", tailwind_config)

      // Create input CSS
      let input_css =
        "@tailwind base;
@tailwind components;
@tailwind utilities;
"
      let _ = simplifile.write("assets/css/app.css", input_css)
      let _ = simplifile.create_directory_all("assets/css")
      let _ = simplifile.write("assets/css/app.css", input_css)

      io.println("Created:")
      io.println("  tailwind.config.js")
      io.println("  assets/css/app.css")
      io.println("")
      io.println("Build assets:")
      io.println(
        "  npx tailwindcss -i assets/css/app.css -o priv/static/css/app.css",
      )
      io.println("")
      io.println("Watch mode:")
      io.println(
        "  npx tailwindcss -i assets/css/app.css -o priv/static/css/app.css --watch",
      )
    }
  }
}

pub fn build() {
  io.println("Building assets...")
  let output =
    run_cmd(
      "npx tailwindcss -i assets/css/app.css -o priv/static/css/app.css --minify",
    )
  case string.contains(output, "error") || string.contains(output, "Error") {
    True -> {
      io.println("Asset build failed:")
      io.println(output)
    }
    False -> {
      io.println("Assets built successfully.")
      io.println("  priv/static/css/app.css")
    }
  }
}
