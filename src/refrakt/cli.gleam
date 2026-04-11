/// Refrakt CLI entry point.
///
/// Run with: gleam run -m refrakt/cli
///
import argv
import gleam/io
import gleam/string
import refrakt/cli/assets
import refrakt/cli/build
import refrakt/cli/dev
import refrakt/cli/gen
import refrakt/cli/migrate_cmd
import refrakt/cli/new
import refrakt/cli/routes
import refrakt/cli/seed

pub fn main() {
  case argv.load().arguments {
    ["new", name, ..flags] -> new.run(name, flags)
    ["gen", "page", name, ..] -> gen.page(name)
    ["gen", "resource", name, ..fields] -> gen.resource(name, fields)
    ["gen", "migration", name, ..] -> gen.migration(name)
    ["gen", "auth", ..] -> gen.auth()
    ["gen", "island", name, ..] -> gen.island(name)
    ["gen", "live", name, ..] -> gen.live(name)
    ["routes", ..] -> routes.run()
    ["migrate", ..] -> migrate_cmd.run()
    ["build", ..] -> build.run()
    ["assets", "setup", ..] -> assets.setup()
    ["assets", "build", ..] -> assets.build()
    ["assets", ..] -> assets.setup()
    ["seed", ..] -> seed.run()
    ["dev", ..] -> dev.run()
    ["help", ..] | ["--help", ..] | ["-h", ..] -> print_help()
    ["version", ..] | ["--version", ..] | ["-v", ..] ->
      io.println("refrakt 0.2.0")
    [cmd, ..] -> {
      io.println("Unknown command: " <> cmd)
      io.println("")
      print_help()
    }
    [] -> print_help()
  }
}

fn print_help() {
  io.println(string.join(
    [
      "refrakt — A convention-first web framework for Gleam",
      "",
      "Usage: refrakt <command> [options]",
      "",
      "Commands:",
      "  new <name>                        Create a new project",
      "    --db postgres                   Add PostgreSQL support",
      "    --db sqlite                     Add SQLite support",
      "",
      "  gen page <name>                   Generate a page (handler + route)",
      "  gen resource <name> <fields...>   Generate CRUD resource",
      "    --api                           JSON API mode (no views)",
      "    --belongs-to <parent>           Add foreign key to parent",
      "  gen migration <name>              Generate a SQL migration file",
      "  gen auth                          Generate starter authentication",
      "  gen island <name>                 Generate a Lustre interactive island",
      "  gen live <name>                   Generate a Lustre server component",
      "",
      "  routes                            Print the route table",
      "  migrate                           Run pending migrations",
      "  seed                              Run database seeds",
      "  build                             Compile Lustre islands to JS",
      "  assets setup                      Set up Tailwind CSS",
      "  assets build                      Build CSS/JS assets",
      "  dev                               Start the dev server",
      "",
      "  help                              Show this help",
      "  version                           Show version",
      "",
      "Field types for gen resource:",
      "  string, text, int, float, bool, date, datetime",
      "",
      "Examples:",
      "  refrakt new my_app --db postgres",
      "  refrakt gen resource posts title:string body:text published:bool",
      "  refrakt gen page about",
    ],
    "\n",
  ))
}
