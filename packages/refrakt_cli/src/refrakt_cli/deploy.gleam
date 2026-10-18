//// `refrakt gen deploy [--fly]`: a Dockerfile, a .dockerignore and, with
//// `--fly`, a fly.toml for the app in the current directory.
////
//// The Dockerfile builds an Erlang shipment (`gleam export
//// erlang-shipment`) and runs it on a slim Erlang image. Apps with a
//// database also get `bin/migrate`, which runs `src/<app>/migrate.gleam`
//// from the shipment, since `gleam run` is not available there.
////
//// Existing files are never overwritten: each one is either written or
//// reported as skipped.

import gleam/int
import gleam/io
import gleam/list
import gleam/option.{None, Some}
import gleam/order
import gleam/result
import gleam/string
import refrakt_cli/format
import refrakt_cli/gen
import refrakt_cli/manifest
import refrakt_cli/migrate_cmd
import refrakt_cli/project
import refrakt_cli/types.{type DbChoice, NoDb, Postgres, Sqlite}
import simplifile
import tom

/// The Gleam image the Dockerfile builds with,
/// `ghcr.io/gleam-lang/gleam:v<version>-erlang-alpine`.
pub const gleam_version = "1.19.2"

/// The Erlang/OTP release that Gleam image is built on. The runtime image,
/// `erlang:<version>-alpine`, must run the same release.
pub const erlang_version = "29.1.1"

/// The port the container listens on.
const port = "4000"

pub fn run(args: List(String)) {
  case parse_args(args, False) {
    Error(message) -> {
      io.println("Error: " <> message)
      io.println("Nothing was generated.")
    }
    Ok(fly) -> {
      generate(fly)
      manifest.record([
        "deploy",
        ..case fly {
          True -> ["--fly"]
          False -> []
        }
      ])
    }
  }
}

fn parse_args(args: List(String), fly: Bool) -> Result(Bool, String) {
  case args {
    [] -> Ok(fly)
    ["--fly", ..rest] -> parse_args(rest, True)
    [arg, ..] -> Error("Unknown option " <> arg <> " (use --fly).")
  }
}

fn generate(fly: Bool) {
  let app = project.app_name()
  let db = project.detect_db()

  let #(health_path, router_patched) = ensure_health_route(app)

  let files =
    [
      Some(#("Dockerfile", dockerfile(app, db, health_path))),
      Some(#(".dockerignore", dockerignore())),
      case db {
        NoDb -> None
        _ -> Some(#("bin/migrate", migrate_script(app)))
      },
      case db {
        Postgres ->
          Some(#(
            "src/" <> app <> "/migrate.gleam",
            migrate_cmd.migrate_module_postgres(app),
          ))
        Sqlite ->
          Some(#(
            "src/" <> app <> "/migrate.gleam",
            migrate_cmd.migrate_module_sqlite(app),
          ))
        NoDb -> None
      },
      case fly {
        True -> Some(#("fly.toml", fly_toml(app, db, health_path)))
        False -> None
      },
    ]
    |> option.values

  let #(created, skipped) = list.partition(files, fn(file) { !exists(file.0) })
  list.each(created, fn(file) {
    let #(path, content) = file
    ensure_dir_for(path)
    let assert Ok(_) = simplifile.write(path, content)
  })
  let created = list.map(created, fn(file) { file.0 })
  let skipped = list.map(skipped, fn(file) { file.0 })
  case list.contains(created, "bin/migrate") {
    True -> {
      let _ = simplifile.set_permissions_octal("bin/migrate", 0o755)
      Nil
    }
    False -> Nil
  }
  let router_path = "src/" <> app <> "/router.gleam"
  format.format_files(
    list.filter([router_path, ..created], fn(path) {
      string.ends_with(path, ".gleam")
      && { path != router_path || router_patched }
    }),
  )

  print_list("Created:", created)
  print_list("Skipped (already exists):", skipped)
  case router_patched {
    True ->
      print_list("Updated:", [
        router_path
        <> " (GET "
        <> health_path
        <> " answers 200 for health checks)",
      ])
    False -> Nil
  }

  warn_about_gleam_version()
  warn_about_old_modules(app, db)
  print_next_steps(app, db, fly)
}

// =============================================================================
// Health check route
// =============================================================================

/// The path health checks request. A router with a `["healthz"]` or
/// `["health"]` route keeps it; otherwise `GET /healthz` is added before
/// the catch-all. Returns the path and whether the router changed.
fn ensure_health_route(app: String) -> #(String, Bool) {
  let router_path = "src/" <> app <> "/router.gleam"
  case simplifile.read(router_path) {
    Error(_) -> #("/", False)
    Ok(content) ->
      case
        string.contains(content, "[\"healthz\"]"),
        string.contains(content, "[\"health\"]")
      {
        True, _ -> #("/healthz", False)
        _, True -> #("/health", False)
        False, False -> {
          let patched =
            gen.add_route(
              content,
              "    // Health checks of load balancers and `gen deploy`'s Dockerfile\n    [\"healthz\"], http.Get -> wisp.ok()",
            )
          case patched == content {
            // No catch-all to insert before: check the home page instead
            True -> #("/", False)
            False -> {
              let assert Ok(_) = simplifile.write(router_path, patched)
              #("/healthz", True)
            }
          }
        }
      }
  }
}

// =============================================================================
// Templates
// =============================================================================

pub fn dockerfile(app: String, db: DbChoice, health_path: String) -> String {
  let migrations = case db {
    NoDb -> ""
    _ -> "
# bin/migrate runs src/" <> app <> "/migrate.gleam from the shipment; it reads
# the SQL files in src/" <> app <> "/data/migrations relative to /app.
COPY --from=build --chown=app:app /build/src/" <> app <> "/data /app/src/" <> app <> "/data
COPY --from=build --chown=app:app /build/bin/migrate /app/bin/migrate
"
  }
  let database = case db {
    Sqlite -> "
# The SQLite database lives in /data. Mount a volume there so that it
# outlives the container:
#   docker run -v " <> app <> "_data:/data ...
RUN mkdir /data && chown app:app /data
ENV DATABASE_PATH=/data/" <> app <> ".db
"
    Postgres -> "
# The database connection comes from DATABASE_URL at runtime, e.g.
#   docker run -e DATABASE_URL=postgres://user:password@host:5432/" <> app <> " ...
"
    NoDb -> ""
  }
  let cmd = case db {
    Sqlite ->
      "
# Apply pending migrations to the database on the volume, then start the
# server. (One container owns a SQLite file, so migrating on start is safe.)
CMD [\"/bin/sh\", \"-c\", \"bin/migrate && exec ./entrypoint.sh run\"]
"
    Postgres ->
      "
# Start the server. Run migrations before a new release goes live, with
# the same image: docker run --rm -e DATABASE_URL=... <image> bin/migrate
# (fly.toml runs it as the release_command).
CMD [\"./entrypoint.sh\", \"run\"]
"
    NoDb ->
      "
CMD [\"./entrypoint.sh\", \"run\"]
"
  }

  "# Container image for " <> app <> ", written by `refrakt gen deploy`.
#
#   docker build -t " <> app <> " .
#   docker run -p " <> port <> ":" <> port <> " -e SECRET_KEY_BASE=$(openssl rand -hex 64) " <> app <> "
#
# The build stage compiles the app and its dependencies into an Erlang
# shipment (gleam export erlang-shipment); the runtime stage runs it on the
# same Erlang/OTP release, without Gleam or a C compiler.

# Raise both together: the runtime image must run the Erlang/OTP release
# the Gleam image is built on (`docker run --rm <gleam image> erl -version`).
ARG GLEAM_VERSION=v" <> gleam_version <> "
ARG ERLANG_VERSION=" <> erlang_version <> "

# -- Build ---------------------------------------------------------------------
FROM ghcr.io/gleam-lang/gleam:${GLEAM_VERSION}-erlang-alpine AS build

# A C toolchain for dependencies with native code: argus (Argon2 password
# hashing, added by `refrakt gen auth`) and sqlight's SQLite driver.
RUN apk add --no-cache build-base

WORKDIR /build
COPY . .
RUN gleam export erlang-shipment

# -- Runtime -------------------------------------------------------------------
FROM erlang:${ERLANG_VERSION}-alpine

RUN addgroup -S app && adduser -S -G app -h /app app
WORKDIR /app
COPY --from=build --chown=app:app /build/build/erlang-shipment /app
" <> migrations <> database <> "
ENV APP_ENV=prod \\
    HOST=0.0.0.0 \\
    PORT=" <> port <> "
# SECRET_KEY_BASE is a secret: pass it at runtime (docker run -e, fly secrets).
EXPOSE " <> port <> "
USER app

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s \\
  CMD wget -q -O /dev/null \"http://127.0.0.1:${PORT}" <> health_path <> "\" || exit 1
" <> cmd
}

pub fn dockerignore() -> String {
  "# Kept out of the Docker build context (written by `refrakt gen deploy`).
# The build compiles the app from source, so local build output and
# databases stay out.
build
.git
**/*.db
**/*.db-journal
**/*.db-shm
**/*.db-wal
erl_crash.dump
.env
.env.*
node_modules
.DS_Store
"
}

/// `bin/migrate`: run the app's migrate module from the shipment.
pub fn migrate_script(app: String) -> String {
  "#!/bin/sh
# Apply pending migrations from the Erlang shipment in the Docker image
# (written by `refrakt gen deploy`). `gleam run -m " <> app <> "/migrate` needs
# Gleam and the sources; this runs the compiled module instead:
#
#   docker run --rm -e DATABASE_URL=... -e SECRET_KEY_BASE=... <image> bin/migrate
#
# It reads the SQL files from src/" <> app <> "/data/migrations and exits with
# status 1 when a migration fails.
set -eu
cd \"$(dirname \"$0\")/..\"

if [ ! -d src/" <> app <> "/data/migrations ]; then
  echo \"No migrations to apply.\"
  exit 0
fi

exec erl -pa ./*/ebin -noshell -eval \"" <> app <> "@@main:run(" <> app <> "@migrate)\"
"
}

pub fn fly_toml(app: String, db: DbChoice, health_path: String) -> String {
  let deploy = case db {
    Postgres ->
      "
# Apply migrations before the new release takes traffic. A failing
# migration stops the deploy.
[deploy]
  release_command = \"/app/bin/migrate\"
"
    _ -> ""
  }
  let env_extra = case db {
    Sqlite -> "\n  DATABASE_PATH = \"/data/" <> app <> ".db\""
    _ -> ""
  }
  let mounts = case db {
    Sqlite -> "
# The SQLite database lives on a volume: fly volumes create " <> app <> "_data --size 1
# The Dockerfile applies pending migrations when the machine starts (a
# release_command machine has no volume). Run a single machine: every
# machine gets a volume, and so a database, of its own.
[mounts]
  source = \"" <> app <> "_data\"
  destination = \"/data\"
"
    _ -> ""
  }
  let machines = case db {
    Sqlite -> "1"
    _ -> "0"
  }

  "# Fly.io configuration for "
  <> app
  <> ", written by `refrakt gen deploy --fly`.
# Secrets are not kept here: fly secrets set SECRET_KEY_BASE=$(openssl rand -hex 64)
# Fly app names allow no underscores; change the name if it is taken.

app = \""
  <> string.replace(app, "_", "-")
  <> "\"
# primary_region = \"fra\"

[build]
  dockerfile = \"Dockerfile\"

[env]
  APP_ENV = \"prod\"
  PORT = \""
  <> port
  <> "\""
  <> env_extra
  <> "
"
  <> deploy
  <> "
[http_service]
  internal_port = "
  <> port
  <> "
  force_https = true
  auto_stop_machines = \"stop\"
  auto_start_machines = true
  min_machines_running = "
  <> machines
  <> "

  [[http_service.checks]]
    method = \"GET\"
    path = \""
  <> health_path
  <> "\"
    interval = \"15s\"
    timeout = \"5s\"
    grace_period = \"20s\"
"
  <> mounts
}

// =============================================================================
// Warnings and instructions
// =============================================================================

/// Warn when gleam.toml requires a Gleam the Dockerfile's image is not.
fn warn_about_gleam_version() -> Nil {
  let requirement =
    simplifile.read("gleam.toml")
    |> result.replace_error(Nil)
    |> result.try(fn(content) {
      tom.parse(content) |> result.replace_error(Nil)
    })
    |> result.try(fn(parsed) {
      tom.get_string(parsed, ["gleam"]) |> result.replace_error(Nil)
    })
  case requirement {
    Ok(requirement) ->
      case satisfies(gleam_version, requirement) {
        True -> Nil
        False -> {
          io.println("")
          io.println(
            "Warning: gleam.toml requires gleam "
            <> requirement
            <> ", but the Dockerfile builds with Gleam "
            <> gleam_version
            <> ". Set GLEAM_VERSION in the Dockerfile to a matching tag of",
          )
          io.println(
            "ghcr.io/gleam-lang/gleam and ERLANG_VERSION to the Erlang/OTP release it is built on.",
          )
        }
      }
    Error(Nil) -> Nil
  }
}

/// Apps generated before `gen deploy` existed listen on localhost only and
/// keep the SQLite database at a fixed path. Say what to change.
fn warn_about_old_modules(app: String, db: DbChoice) -> Nil {
  let main_path = "src/" <> app <> ".gleam"
  case simplifile.read(main_path) {
    Ok(main) ->
      case
        string.contains(main, "mist.new") && !string.contains(main, "mist.bind")
      {
        True -> {
          io.println("")
          io.println(
            "Warning: "
            <> main_path
            <> " does not call mist.bind, so the server listens on localhost",
          )
          io.println(
            "only and nothing outside the container reaches it. Add a `host` field to the",
          )
          io.println(
            "config (envoy.get(\"HOST\") |> result.unwrap(\"localhost\")) and `|> mist.bind(cfg.host)`",
          )
          io.println("after `|> mist.new`; the Dockerfile sets HOST=0.0.0.0.")
        }
        False -> Nil
      }
    Error(_) -> Nil
  }
  case db {
    Sqlite -> {
      let repo_path = "src/" <> app <> "/data/repo.gleam"
      case simplifile.read(repo_path) {
        Ok(repo) ->
          case string.contains(repo, "DATABASE_PATH") {
            True -> Nil
            False -> {
              io.println("")
              io.println(
                "Warning: "
                <> repo_path
                <> " does not read DATABASE_PATH, so the database is not",
              )
              io.println(
                "written to the /data volume. In database_path, return",
              )
              io.println(
                "  envoy.get(\"DATABASE_PATH\") |> result.unwrap(\""
                <> app
                <> ".db\")",
              )
              io.println("outside of tests.")
            }
          }
        Error(_) -> Nil
      }
    }
    _ -> Nil
  }
}

fn print_next_steps(app: String, db: DbChoice, fly: Bool) -> Nil {
  io.println("")
  io.println("Build and run the image:")
  io.println("  docker build -t " <> app <> " .")
  let run = case db {
    Sqlite ->
      "  docker run -p "
      <> port
      <> ":"
      <> port
      <> " -v "
      <> app
      <> "_data:/data -e SECRET_KEY_BASE=$(openssl rand -hex 64) "
      <> app
    Postgres ->
      "  docker run -p "
      <> port
      <> ":"
      <> port
      <> " -e DATABASE_URL=postgres://... -e SECRET_KEY_BASE=$(openssl rand -hex 64) "
      <> app
    NoDb ->
      "  docker run -p "
      <> port
      <> ":"
      <> port
      <> " -e SECRET_KEY_BASE=$(openssl rand -hex 64) "
      <> app
  }
  case db {
    Postgres -> {
      io.println(
        "  docker run --rm -e DATABASE_URL=postgres://... -e SECRET_KEY_BASE=... "
        <> app
        <> " bin/migrate",
      )
      io.println(run)
    }
    Sqlite -> {
      io.println(run)
      io.println("  (pending migrations run when the container starts)")
    }
    NoDb -> io.println(run)
  }
  case fly {
    False -> Nil
    True -> {
      io.println("")
      io.println("Deploy to Fly.io:")
      io.println("  fly apps create " <> string.replace(app, "_", "-"))
      io.println("  fly secrets set SECRET_KEY_BASE=$(openssl rand -hex 64)")
      case db {
        Postgres -> {
          io.println(
            "  fly postgres attach <postgres-app>   # sets the DATABASE_URL secret",
          )
          io.println("  (or: fly secrets set DATABASE_URL=postgres://...)")
        }
        Sqlite -> io.println("  fly volumes create " <> app <> "_data --size 1")
        NoDb -> Nil
      }
      io.println("  fly deploy")
      case db {
        Postgres ->
          io.println(
            "  (fly deploy runs bin/migrate as the release_command first)",
          )
        _ -> Nil
      }
    }
  }
}

// =============================================================================
// Version requirements
// =============================================================================

/// Whether `version` (such as "1.19.2") meets a gleam.toml requirement
/// such as ">= 1.14.0" or ">= 1.14.0 and < 2.0.0". A requirement this
/// cannot read counts as met.
pub fn satisfies(version: String, requirement: String) -> Bool {
  case parse_version(version) {
    Error(Nil) -> True
    Ok(version) ->
      requirement
      |> string.split(" and ")
      |> list.all(fn(part) {
        let part = string.trim(part)
        let #(operator, rest) = case part {
          ">=" <> rest -> #(">=", rest)
          "<=" <> rest -> #("<=", rest)
          "==" <> rest -> #("==", rest)
          "~>" <> rest -> #("~>", rest)
          ">" <> rest -> #(">", rest)
          "<" <> rest -> #("<", rest)
          rest -> #("==", rest)
        }
        let rest = string.trim(rest)
        case parse_version(rest) {
          Error(Nil) -> True
          Ok(bound) -> {
            let compared = compare(version, bound)
            case operator {
              ">=" -> compared != order.Lt
              "<=" -> compared != order.Gt
              ">" -> compared == order.Gt
              "<" -> compared == order.Lt
              "~>" ->
                compared != order.Lt
                && compare(version, pessimistic_bound(rest, bound)) == order.Lt
              _ -> compared == order.Eq
            }
          }
        }
      })
  }
}

/// `~> 1.14` allows up to 2.0.0, `~> 1.14.0` up to 1.15.0.
fn pessimistic_bound(text: String, bound: List(Int)) -> List(Int) {
  case string.split(text, "."), bound {
    [_, _], [major, ..] -> [major + 1, 0, 0]
    _, [major, minor, ..] -> [major, minor + 1, 0]
    _, _ -> bound
  }
}

fn parse_version(text: String) -> Result(List(Int), Nil) {
  // Pre-release suffixes (1.20.0-rc1) compare as their release
  let text = case string.split_once(text, "-") {
    Ok(#(release, _)) -> release
    Error(Nil) -> text
  }
  use parts <- result.try(list.try_map(string.split(text, "."), int.parse))
  case parts {
    [major] -> Ok([major, 0, 0])
    [major, minor] -> Ok([major, minor, 0])
    [major, minor, patch] -> Ok([major, minor, patch])
    _ -> Error(Nil)
  }
}

fn compare(a: List(Int), b: List(Int)) -> order.Order {
  case a, b {
    [x, ..a], [y, ..b] ->
      case int.compare(x, y) {
        order.Eq -> compare(a, b)
        other -> other
      }
    _, _ -> order.Eq
  }
}

// =============================================================================
// Helpers
// =============================================================================

fn exists(path: String) -> Bool {
  case simplifile.is_file(path) {
    Ok(True) -> True
    _ -> False
  }
}

fn ensure_dir_for(path: String) -> Nil {
  case string.split(path, "/") |> list.reverse {
    [_, ..dirs] if dirs != [] -> {
      let _ =
        simplifile.create_directory_all(string.join(list.reverse(dirs), "/"))
      Nil
    }
    _ -> Nil
  }
}

fn print_list(title: String, paths: List(String)) -> Nil {
  case paths {
    [] -> Nil
    _ -> {
      io.println("")
      io.println(title)
      list.each(paths, fn(path) { io.println("  " <> path) })
    }
  }
}
