/// `refrakt new <name>` — scaffold a new Refrakt project.
///
import gleam/io
import gleam/list
import refrakt/cli/templates
import refrakt/cli/types.{type DbChoice, NoDb, Postgres, Sqlite}
import simplifile

pub fn run(name: String, flags: List(String)) {
  let db = parse_db_flag(flags)

  io.println("Creating " <> name <> "...")
  io.println("")

  // Create directory structure
  let dirs = [
    name,
    name <> "/src",
    name <> "/src/" <> name,
    name <> "/src/" <> name <> "/web",
    name <> "/src/" <> name <> "/web/layouts",
    name <> "/src/" <> name <> "/web/components",
    name <> "/src/" <> name <> "/web/forms",
    name <> "/src/" <> name <> "/web/middleware",
    name <> "/src/" <> name <> "/domain",
    name <> "/src/" <> name <> "/data",
    name <> "/priv/static/css",
    name <> "/priv/static/js",
    name <> "/test",
    name <> "/test/" <> name <> "/web",
  ]

  list.each(dirs, fn(dir) {
    let assert Ok(_) = simplifile.create_directory_all(dir)
  })

  // Write files
  let files = [
    #(name <> "/gleam.toml", templates.gleam_toml(name, db)),
    #(name <> "/.gitignore", templates.gitignore()),
    #(name <> "/README.md", templates.readme(name)),
    #(name <> "/src/" <> name <> ".gleam", templates.main_module(name, db)),
    #(name <> "/src/" <> name <> "/config.gleam", templates.config_module(name)),
    #(
      name <> "/src/" <> name <> "/context.gleam",
      templates.context_module(name, db),
    ),
    #(
      name <> "/src/" <> name <> "/router.gleam",
      templates.router_module(name, db),
    ),
    #(
      name <> "/src/" <> name <> "/web/home_handler.gleam",
      templates.home_handler(name),
    ),
    #(
      name <> "/src/" <> name <> "/web/error_handler.gleam",
      templates.error_handler(name),
    ),
    #(
      name <> "/src/" <> name <> "/web/layouts/root_layout.gleam",
      templates.root_layout(),
    ),
    #(
      name <> "/src/" <> name <> "/web/components/flash.gleam",
      templates.flash_component(),
    ),
    #(name <> "/priv/static/css/app.css", templates.app_css()),
    #(name <> "/priv/static/js/app.js", templates.app_js()),
    #(name <> "/test/" <> name <> "_test.gleam", templates.main_test(name)),
    #(
      name <> "/test/" <> name <> "/web/home_handler_test.gleam",
      templates.home_handler_test(name),
    ),
  ]

  // Add repo module if DB is selected
  let files = case db {
    Postgres | Sqlite -> [
      #(
        name <> "/src/" <> name <> "/data/repo.gleam",
        templates.repo_module(name, db),
      ),
      ..files
    ]
    NoDb -> files
  }

  list.each(files, fn(file) {
    let #(path, content) = file
    let assert Ok(_) = simplifile.write(path, content)
  })

  // Print results
  io.println("  " <> name <> "/")
  io.println("    gleam.toml")
  io.println("    .gitignore")
  io.println("    README.md")
  io.println("    src/")
  io.println("      " <> name <> ".gleam")
  io.println("      " <> name <> "/config.gleam")
  io.println("      " <> name <> "/router.gleam")
  io.println("      " <> name <> "/web/")
  io.println("        home_handler.gleam")
  io.println("        error_handler.gleam")
  io.println("      " <> name <> "/web/layouts/")
  io.println("        root_layout.gleam")
  io.println("      " <> name <> "/web/components/")
  io.println("        flash.gleam")
  case db {
    Postgres | Sqlite -> {
      io.println("      " <> name <> "/data/")
      io.println("        repo.gleam")
    }
    NoDb -> Nil
  }
  io.println("    priv/static/")
  io.println("      css/app.css")
  io.println("      js/app.js")
  io.println("    test/")
  io.println("      " <> name <> "_test.gleam")
  io.println("      " <> name <> "/web/")
  io.println("        home_handler_test.gleam")
  io.println("")
  io.println("Run your app:")
  io.println("  cd " <> name)
  io.println("  gleam run")
  io.println("  → http://localhost:4000")
}

fn parse_db_flag(flags: List(String)) -> DbChoice {
  case flags {
    ["--db", "postgres", ..] -> Postgres
    ["--db", "sqlite", ..] -> Sqlite
    ["--db", "pg", ..] -> Postgres
    ["--no-db", ..] -> NoDb
    [_, ..rest] -> parse_db_flag(rest)
    [] -> NoDb
  }
}
