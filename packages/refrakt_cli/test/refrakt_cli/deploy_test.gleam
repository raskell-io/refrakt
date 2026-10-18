/// Tests for `refrakt gen deploy [--fly]` (#26).
///
import gleam/list
import gleam/string
import gleeunit/should
import refrakt_cli/deploy
import refrakt_cli/gen
import refrakt_cli/new
import simplifile

// =============================================================================
// SQLite
// =============================================================================

pub fn deploy_sqlite_test() {
  in_project("deploy_sqlite", ["--db", "sqlite"], fn(app) {
    gen.resource("posts", ["title:string"])
    deploy.run([])

    let dockerfile = read("Dockerfile")
    [
      "FROM ghcr.io/gleam-lang/gleam:${GLEAM_VERSION}-erlang-alpine AS build",
      "ARG GLEAM_VERSION=v" <> deploy.gleam_version,
      "ARG ERLANG_VERSION=" <> deploy.erlang_version,
      "FROM erlang:${ERLANG_VERSION}-alpine",
      "RUN apk add --no-cache build-base",
      "RUN gleam export erlang-shipment",
      "COPY --from=build --chown=app:app /build/build/erlang-shipment /app",
      "COPY --from=build --chown=app:app /build/src/"
        <> app
        <> "/data /app/src/"
        <> app
        <> "/data",
      "COPY --from=build --chown=app:app /build/bin/migrate /app/bin/migrate",
      "ENV DATABASE_PATH=/data/" <> app <> ".db",
      "RUN mkdir /data && chown app:app /data",
      "ENV APP_ENV=prod",
      "HOST=0.0.0.0",
      "PORT=4000",
      "EXPOSE 4000",
      "USER app",
      "/healthz",
      "CMD [\"/bin/sh\", \"-c\", \"bin/migrate && exec ./entrypoint.sh run\"]",
    ]
    |> list.each(fn(line) { contains(dockerfile, line) })
    string.contains(dockerfile, "DATABASE_URL") |> should.be_false

    let ignore = read(".dockerignore")
    ["build\n", ".git\n", "**/*.db\n", "erl_crash.dump\n"]
    |> list.each(contains(ignore, _))

    // bin/migrate runs the migrate module from the shipment
    let migrate = read("bin/migrate")
    contains(migrate, "#!/bin/sh")
    contains(
      migrate,
      "erl -pa ./*/ebin -noshell -eval \""
        <> app
        <> "@@main:run("
        <> app
        <> "@migrate)\"",
    )
    let assert Ok(info) = simplifile.file_info("bin/migrate")
    { info.mode % 0o1000 } |> should.equal(0o755)
    contains(read("src/" <> app <> "/migrate.gleam"), "halt(1)")

    // A health route for the HEALTHCHECK
    contains(
      read("src/" <> app <> "/router.gleam"),
      "[\"healthz\"], http.Get -> wisp.ok()",
    )

    // No fly.toml without --fly
    simplifile.is_file("fly.toml") |> should.equal(Ok(False))
  })
}

pub fn deploy_sqlite_fly_test() {
  in_project("deploy_sqlite_fly", ["--db", "sqlite"], fn(app) {
    deploy.run(["--fly"])

    let fly = read("fly.toml")
    [
      "app = \"deploy-sqlite-fly-app\"",
      "APP_ENV = \"prod\"",
      "internal_port = 4000",
      "path = \"/healthz\"",
      "DATABASE_PATH = \"/data/" <> app <> ".db\"",
      "[mounts]",
      "source = \"" <> app <> "_data\"",
      "destination = \"/data\"",
      "min_machines_running = 1",
    ]
    |> list.each(contains(fly, _))
    // A release_command machine has no volume: migrations run on start
    string.contains(fly, "release_command =") |> should.be_false
  })
}

// =============================================================================
// Postgres
// =============================================================================

pub fn deploy_postgres_fly_test() {
  in_project("deploy_pg", ["--db", "postgres"], fn(app) {
    deploy.run(["--fly"])

    let dockerfile = read("Dockerfile")
    contains(dockerfile, "DATABASE_URL")
    contains(dockerfile, "CMD [\"./entrypoint.sh\", \"run\"]")
    contains(dockerfile, "/build/bin/migrate /app/bin/migrate")
    string.contains(dockerfile, "DATABASE_PATH") |> should.be_false
    string.contains(dockerfile, "bin/migrate &&") |> should.be_false

    let fly = read("fly.toml")
    contains(fly, "release_command = \"/app/bin/migrate\"")
    contains(fly, "min_machines_running = 0")
    string.contains(fly, "[mounts]") |> should.be_false

    contains(read("src/" <> app <> "/migrate.gleam"), "import pog")
  })
}

// =============================================================================
// No database
// =============================================================================

pub fn deploy_without_db_test() {
  in_project("deploy_none", [], fn(app) {
    deploy.run(["--fly"])

    let dockerfile = read("Dockerfile")
    contains(dockerfile, "CMD [\"./entrypoint.sh\", \"run\"]")
    string.contains(dockerfile, "migrate") |> should.be_false
    string.contains(dockerfile, "DATABASE") |> should.be_false
    simplifile.is_file("bin/migrate") |> should.equal(Ok(False))
    simplifile.is_file("src/" <> app <> "/migrate.gleam")
    |> should.equal(Ok(False))
    contains(read("fly.toml"), "path = \"/healthz\"")
  })
}

// =============================================================================
// Idempotence
// =============================================================================

pub fn deploy_skips_existing_files_test() {
  in_project("deploy_skip", ["--db", "sqlite"], fn(app) {
    let assert Ok(_) = simplifile.write("Dockerfile", "FROM scratch\n")
    deploy.run([])
    read("Dockerfile") |> should.equal("FROM scratch\n")
    // the others are written
    simplifile.is_file(".dockerignore") |> should.equal(Ok(True))

    // A second run changes nothing, and adds no second health route
    let router_path = "src/" <> app <> "/router.gleam"
    let router = read(router_path)
    let ignore = read(".dockerignore")
    deploy.run([])
    read(router_path) |> should.equal(router)
    read(".dockerignore") |> should.equal(ignore)
  })
}

pub fn deploy_keeps_an_existing_health_route_test() {
  in_project("deploy_health", [], fn(app) {
    let router_path = "src/" <> app <> "/router.gleam"
    let router =
      read(router_path)
      |> gen.add_route(
        "    [\"health\"], http.Get -> wisp.ok() |> wisp.string_body(\"ok\")",
      )
    let assert Ok(_) = simplifile.write(router_path, router)

    deploy.run(["--fly"])
    read(router_path) |> should.equal(router)
    contains(read("fly.toml"), "path = \"/health\"")
    contains(read("Dockerfile"), "${PORT}/health\"")
  })
}

pub fn deploy_rejects_unknown_options_test() {
  in_project("deploy_flag", [], fn(_app) {
    deploy.run(["--heroku"])
    simplifile.is_file("Dockerfile") |> should.equal(Ok(False))
  })
}

// =============================================================================
// Generated app support
// =============================================================================

pub fn new_app_listens_on_host_and_reads_database_path_test() {
  in_project("deploy_new", ["--db", "sqlite"], fn(app) {
    contains(read("src/" <> app <> ".gleam"), "|> mist.bind(cfg.host)")
    contains(
      read("src/" <> app <> "/config.gleam"),
      "envoy.get(\"HOST\") |> result.unwrap(\"localhost\")",
    )
    contains(read("src/" <> app <> "/data/repo.gleam"), "DATABASE_PATH")
  })
}

// =============================================================================
// Version requirements
// =============================================================================

pub fn satisfies_test() {
  deploy.satisfies("1.19.2", ">= 1.14.0") |> should.be_true
  deploy.satisfies("1.19.2", ">= 1.14.0 and < 2.0.0") |> should.be_true
  deploy.satisfies("1.19.2", ">= 1.20.0") |> should.be_false
  deploy.satisfies("1.19.2", "< 1.19.0") |> should.be_false
  deploy.satisfies("1.19.2", "~> 1.14") |> should.be_true
  deploy.satisfies("1.19.2", "~> 1.14.0") |> should.be_false
  deploy.satisfies("1.19.2", "== 1.19.2") |> should.be_true
  deploy.satisfies("1.19.2", "1.19.2") |> should.be_true
  deploy.satisfies("1.19.2", "whatever") |> should.be_true
}

// =============================================================================
// Helpers
// =============================================================================

/// Run `f` inside a new project `<name>_app` created with `flags`.
fn in_project(name: String, flags: List(String), f: fn(String) -> Nil) -> Nil {
  let dir = "/tmp/refrakt_test_" <> name
  let app = name <> "_app"
  let _ = simplifile.delete_all([dir])
  let assert Ok(_) = simplifile.create_directory_all(dir)
  new.run(dir <> "/" <> app, flags)

  let assert Ok(cwd) = current_directory()
  let assert Ok(_) = set_cwd(dir <> "/" <> app)
  f(app)
  let assert Ok(_) = set_cwd(cwd)

  let _ = simplifile.delete_all([dir])
  Nil
}

fn read(path: String) -> String {
  let assert Ok(content) = simplifile.read(path)
  content
}

fn contains(content: String, text: String) -> Nil {
  case string.contains(content, text) {
    True -> Nil
    False -> panic as { "missing: " <> text }
  }
}

@external(erlang, "refrakt_cli_test_ffi", "set_cwd")
fn set_cwd(path: String) -> Result(Nil, Nil)

@external(erlang, "refrakt_cli_test_ffi", "current_directory")
fn current_directory() -> Result(String, Nil)
