# Contributing to Refrakt

Thanks for your interest in contributing to Refrakt.

## Setup

```bash
git clone https://github.com/raskell-io/refrakt.git
cd refrakt

# Install toolchain (Gleam 1.19, Erlang 27, rebar3)
mise install
```

The repository holds two Gleam packages. Work inside the one you are
changing:

```bash
cd packages/refrakt        # runtime library (30 tests)
cd packages/refrakt_cli    # code generator  (19 tests)

gleam build --warnings-as-errors
gleam test
gleam format src test
```

Or run a task across both packages from the repository root:
`mise run build`, `mise run test`, `mise run fmt`, `mise run ci`.

## Before submitting

```bash
mise run fmt:check
mise run build
mise run test
```

All three must pass. There are no exceptions.

If you touched the CLI, also check a generated app end to end (below).

## Testing generated apps

`.github/scripts/test-generated-app.sh` is what CI's `generated` job runs.
It generates an app with the in-repo CLI, points the app's `refrakt`
dependency and `refrakt_cli` dev-dependency at `packages/` (so it tests
your working copy, not Hex), runs `gen resource`, `gen page` and
`gen auth`, then builds with warnings as errors, tests and format-checks
the app. With a database it also runs `refrakt_cli migrate`, boots the
app and smoke-tests `/posts` and the register/login flow with curl.

```bash
mise exec -- .github/scripts/test-generated-app.sh none
mise exec -- .github/scripts/test-generated-app.sh sqlite

# Postgres needs a server on localhost:5432 that accepts the postgres user
# without a password (CI uses a service container):
mise exec -- .github/scripts/test-generated-app.sh postgres
# ...or only build and test the generated Postgres app:
SKIP_RUNTIME=1 mise exec -- .github/scripts/test-generated-app.sh postgres
```

Pass a second argument to keep the generated app in a directory of your
choice (default: a fresh temp directory). `PORT` changes the port used
for the smoke test (default 4000).

The example apps are checked with `mise run test:examples`.

### Checking `refrakt dev` by hand

CI doesn't run `refrakt dev`: the unit tests in
`packages/refrakt_cli/test/refrakt_cli/dev_test.gleam` cover watcher
choice, change detection, debouncing and the event stream, and
`packages/refrakt/test/refrakt/live_reload_test.gleam` covers the script
appearing only in dev, but the rebuild/restart loop needs a running app
and real timing. If you touched `dev.gleam`, `refrakt_cli_dev_ffi.erl` or
`refrakt/live_reload`, check a generated SQLite app (the one the script
above leaves in its work directory works):

1. In the app, run `gleam run -m refrakt_cli -- dev`. It prints which
   watcher it uses (fswatch, inotifywait or polling) and
   `Live reload on http://localhost:35729/events`.
2. Open `http://localhost:4000/` in a browser; the page source ends with
   a `<script data-refrakt-live-reload>`. In another terminal, run
   `curl -N http://localhost:35729/events`.
3. Edit the text in `src/<app>/web/home_handler.gleam`. The terminal
   shows one rebuild, curl prints `event: reload`, and the browser shows
   the new text without a manual reload.
4. Add a syntax error and save. The compiler error is printed, followed
   by `Build failed. The previous server keeps running`; the page still
   loads, and curl prints no event.
5. Fix the error and save: the server restarts and the page reloads.
6. Append a comment to `priv/static/css/app.css`: the page reloads with
   no rebuild.
7. Save several files at once (e.g. `touch src/<app>/web/*.gleam`): one
   rebuild, not one per file.
8. Repeat step 3 with the fallback watcher: run `refrakt dev` with a
   `PATH` that lacks `fswatch` (and `inotifywait`), and check that it says
   it is polling.
9. Stop `refrakt dev` (Ctrl-C, or `kill` its Erlang VM). The app's port
   is free again and no `gleam run` is left (`ps`).
10. `APP_ENV=prod SECRET_KEY_BASE=$(openssl rand -hex 64) gleam run`
    (with `REFRAKT_LIVE_RELOAD_PORT=35729` exported, to be sure): the
    page has no live reload script.

## Project structure

```
packages/
  refrakt/                     ← library, published to Hex as `refrakt`
    src/refrakt.gleam
    src/refrakt/
      validate.gleam           ← validation helpers
      flash.gleam              ← flash message helpers
      migrate.gleam            ← migration runner
      testing.gleam            ← test helpers
      dev_error.gleam          ← dev error page
      live_reload.gleam        ← live reload script for refrakt dev
      ...                      ← jobs, token, mailer, paginate, upload, cors,
                                 rate_limit, pubsub, telemetry
    test/

  refrakt_cli/                 ← CLI, published to Hex as `refrakt_cli`
    src/refrakt_cli.gleam      ← entry point (`gleam run -m refrakt_cli`)
    src/refrakt_cli/
      new.gleam                ← refrakt_cli new
      gen.gleam                ← gen resource, page, auth, island, live, migration
      templates.gleam          ← file content templates
      routes.gleam             ← refrakt_cli routes
      deploy.gleam             ← gen deploy (Dockerfile, fly.toml, bin/migrate)
      diff.gleam               ← refrakt_cli diff (replays generators)
      manifest.gleam           ← .refrakt/generated.toml
      build.gleam              ← refrakt_cli build (island JS)
      dev.gleam                ← refrakt_cli dev (watcher choice, debounce,
                                 change detection; process work in
                                 src/refrakt_cli_dev_ffi.erl)
      migrate_cmd.gleam        ← refrakt_cli migrate
      seed.gleam               ← refrakt_cli seed
      assets.gleam             ← refrakt_cli assets
      project.gleam            ← gleam.toml reader
      format.gleam             ← post-generation formatting
      types.gleam              ← shared types (DbChoice)
    test/refrakt_cli/
      gen_test.gleam           ← integration tests (generators)
      routes_test.gleam

docs/                          ← user documentation
examples/
  blog/                        ← Postgres example (generated)
  tasks_app/                   ← SQLite example (generated)
.github/
  workflows/ci.yml             ← packages, generated apps, examples
  workflows/release.yml        ← publish both packages on a v* tag
  scripts/test-generated-app.sh
```

The CLI never imports the library, and generated apps never depend on
the CLI at runtime: it is a dev-dependency only.

## How generators work

1. Templates in `templates.gleam` produce file content as strings
2. Generator functions in `gen.gleam` write files via `simplifile`
3. Router patching finds `_, _ ->` catch-all and inserts routes before it
4. `gleam format` runs on all generated `.gleam` files automatically
5. The generator records its arguments with `manifest.record` in the
   app's `.refrakt/generated.toml`, which `refrakt diff` replays.
   Generators must be deterministic: the same arguments on the same app
   must write the same files, or `refrakt diff` reports false differences
   (the generated-app check fails on that)

## Adding a new generator

1. Add the template function(s) in `gen.gleam` or `templates.gleam`
2. Add the public function in `gen.gleam`; when it writes templates,
   call `manifest.record([...])` after it succeeds and add the matching
   case to `replay` in `diff.gleam`
3. Add the command match and help line in `refrakt_cli.gleam`
4. Add an integration test in `packages/refrakt_cli/test/refrakt_cli/gen_test.gleam`
5. If it should be covered end to end, call it from
   `.github/scripts/test-generated-app.sh`
6. Update `docs/cli.md`

## Adding a new field type

1. Add to `to_gleam_type()` in `gen.gleam`
2. Add to `to_sql_type()` and `to_sql_type_sqlite()` in `gen.gleam`
3. Add to `form_default_value()` in `gen.gleam`
4. Handle in form view rendering (the `form_field_elements` builder)
5. Handle in `from_form_data` (the form decoder)
6. Update `docs/field-types.md`

## Conventions

- Generated code must pass `gleam format --check`
- Generated code must compile with zero warnings
- No framework abstractions — generated code uses Wisp/Lustre directly
- Domain types have zero framework imports
- Tests use `gleeunit` and `should`

## Releasing

See the release process in [`.claude/rules/workflow.md`](.claude/rules/workflow.md#release-process):
bump both packages, update the changelog, push a `vX.Y.Z` tag, and the
release workflow publishes both packages and creates the GitHub release.

Generated code belongs to the app, so a release cannot update existing
apps. If a pull request changes a template, add an entry to the
`### Upgrading` list under `## [Unreleased]` in `CHANGELOG.md` with the
hand edit an existing app needs. Users find the changes with
`refrakt diff` and apply them with those notes.

## Reporting issues

- Use [GitHub Issues](https://github.com/raskell-io/refrakt/issues)
- Include the Gleam version (`gleam --version`)
- Include the command that failed and the full error output
- If a generated file is wrong, include the generated file content

## License

By contributing, you agree that your contributions will be licensed
under the MIT License.
