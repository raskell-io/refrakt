/// `refrakt new <name>` — scaffold a new Refrakt project.
///
import gleam/io
import gleam/list
import gleam/string
import refrakt/cli/format
import refrakt/cli/templates
import refrakt/cli/types.{type DbChoice, NoDb, Postgres, Sqlite}
import simplifile

pub fn run(path: String, flags: List(String)) {
  let db = parse_db_flag(flags)

  // Extract package name from path (last segment)
  let name = case string.split(path, "/") {
    [] -> path
    parts -> {
      let assert Ok(last) = list.last(parts)
      last
    }
  }

  io.println("Creating " <> path <> "...")
  io.println("")

  // Create directory structure
  let dirs = [
    path,
    path <> "/src",
    path <> "/src/" <> name,
    path <> "/src/" <> name <> "/web",
    path <> "/src/" <> name <> "/web/layouts",
    path <> "/src/" <> name <> "/web/components",
    path <> "/src/" <> name <> "/web/forms",
    path <> "/src/" <> name <> "/web/middleware",
    path <> "/src/" <> name <> "/domain",
    path <> "/src/" <> name <> "/data",
    path <> "/priv/static/css",
    path <> "/priv/static/js",
    path <> "/test",
    path <> "/test/" <> name <> "/web",
  ]

  list.each(dirs, fn(dir) {
    let assert Ok(_) = simplifile.create_directory_all(dir)
  })

  // Write files
  let files = [
    #(path <> "/gleam.toml", templates.gleam_toml(name, db)),
    #(path <> "/.gitignore", templates.gitignore()),
    #(path <> "/README.md", templates.readme(name)),
    #(path <> "/src/" <> name <> ".gleam", templates.main_module(name, db)),
    #(path <> "/src/" <> name <> "/config.gleam", templates.config_module(name)),
    #(
      path <> "/src/" <> name <> "/context.gleam",
      templates.context_module(name, db),
    ),
    #(
      path <> "/src/" <> name <> "/router.gleam",
      templates.router_module(name, db),
    ),
    #(
      path <> "/src/" <> name <> "/web/home_handler.gleam",
      templates.home_handler(name),
    ),
    #(
      path <> "/src/" <> name <> "/web/error_handler.gleam",
      templates.error_handler(name),
    ),
    #(
      path <> "/src/" <> name <> "/web/layouts/root_layout.gleam",
      templates.root_layout(),
    ),
    #(
      path <> "/src/" <> name <> "/web/components/flash.gleam",
      templates.flash_component(),
    ),
    #(path <> "/priv/static/css/app.css", templates.app_css()),
    #(path <> "/priv/static/js/app.js", templates.app_js()),
    #(path <> "/test/" <> name <> "_test.gleam", templates.main_test(name)),
    #(
      path <> "/test/" <> name <> "/web/home_handler_test.gleam",
      templates.home_handler_test(name),
    ),
  ]

  // Add repo module if DB is selected
  let files = case db {
    Postgres | Sqlite -> [
      #(
        path <> "/src/" <> name <> "/data/repo.gleam",
        templates.repo_module(name, db),
      ),
      ..files
    ]
    NoDb -> files
  }

  list.each(files, fn(file) {
    let #(file_path, content) = file
    let assert Ok(_) = simplifile.write(file_path, content)
  })

  // Format generated Gleam files
  let gleam_paths =
    list.filter_map(files, fn(file) {
      let #(fp, _) = file
      case string.ends_with(fp, ".gleam") {
        True -> Ok(fp)
        False -> Error(Nil)
      }
    })
  format.format_files(gleam_paths)

  // Print results
  io.println("  " <> path <> "/")
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
  io.println("  cd " <> path)
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
