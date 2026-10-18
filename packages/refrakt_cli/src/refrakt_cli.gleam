//// Refrakt CLI entry point.
////
//// Run with: gleam run -m refrakt_cli -- <command>
////

import argv
import gleam/io
import gleam/string
import refrakt_cli/assets
import refrakt_cli/build
import refrakt_cli/deploy
import refrakt_cli/dev
import refrakt_cli/diff
import refrakt_cli/gen
import refrakt_cli/migrate_cmd
import refrakt_cli/new
import refrakt_cli/routes
import refrakt_cli/seed

pub fn main() {
  case argv.load().arguments {
    ["new", name, ..flags] -> new.run(name, flags)
    ["gen", "page", name, ..] -> gen.page(name)
    ["gen", "resource", name, ..fields] -> gen.resource(name, fields)
    ["gen", "migration", name, ..] -> gen.migration(name)
    ["gen", "auth", ..] -> gen.auth()
    ["gen", "island", name, ..] -> gen.island(name)
    ["gen", "live", name, ..] -> gen.live(name)
    ["gen", "deploy", ..flags] -> deploy.run(flags)
    ["routes", ..] -> routes.run()
    ["diff", ..args] -> diff.main(args)
    ["migrate", ..] -> migrate_cmd.run()
    ["build", ..] -> build.run()
    ["assets", "setup", ..] -> assets.setup()
    ["assets", "build", ..] -> assets.build()
    ["assets", ..] -> assets.setup()
    ["seed", ..] -> seed.run()
    ["dev", ..] -> dev.run()
    ["help", ..] | ["--help", ..] | ["-h", ..] -> print_help()
    ["version", ..] | ["--version", ..] | ["-v", ..] ->
      io.println("refrakt_cli 0.6.0")
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
      "refrakt_cli — code generator for Refrakt, a convention-first web framework for Gleam",
      "",
      "Usage: gleam run -m refrakt_cli -- <command> [options]",
      "",
      "Commands:",
      "  new <name>                        Create a new project",
      "    --db postgres                   Add PostgreSQL support",
      "    --db sqlite                     Add SQLite support",
      "",
      "  gen page <name>                   Generate a page (handler + route)",
      "  gen resource <name> <fields...>   Generate CRUD resource",
      "    --api                           JSON API mode (no views)",
      "    --belongs-to <parent>           Belong to an existing resource: foreign key,",
      "                                    parent select, children on the parent's page",
      "  gen migration <name>              Generate a SQL migration file",
      "  gen auth                          Generate starter authentication",
      "  gen island <name>                 Generate a Lustre interactive island",
      "  gen live <name>                   Generate a Lustre server component",
      "  gen deploy                        Generate a Dockerfile and .dockerignore",
      "    --fly                           Also generate fly.toml for Fly.io",
      "",
      "  routes                            Print the route table",
      "  diff [path...]                    Diff the app against what this CLI generates",
      "    --stat                          Only list the changed files",
      "  migrate                           Run pending migrations",
      "  seed                              Run database seeds",
      "  build                             Compile Lustre islands to JS",
      "  assets setup                      Set up Tailwind CSS",
      "  assets build                      Build CSS/JS assets",
      "  dev                               Start the dev server (rebuilds, live reload)",
      "",
      "  help                              Show this help",
      "  version                           Show version",
      "",
      "Field types for gen resource:",
      "  string, text, int, float, bool, date, datetime,",
      "  optional(<type>) for a nullable field (quote it: 'price:optional(float)')",
      "",
      "Examples:",
      "  gleam run -m refrakt_cli -- new my_app --db postgres",
      "  gleam run -m refrakt_cli -- gen resource posts title:string body:text published:bool",
      "  gleam run -m refrakt_cli -- gen page about",
    ],
    "\n",
  ))
}
