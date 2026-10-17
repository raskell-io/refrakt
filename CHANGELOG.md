# Changelog

All notable changes to Refrakt are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project
uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Upgrading

- **Pagination (repos):** generated `list` functions now take
  `paginate.Params` and return `paginate.Page(item)`. In each
  `data/<singular>_repo.gleam`, add `import refrakt/paginate`, add
  `LIMIT`/`OFFSET` to the `list` query and a `SELECT COUNT(*)`, and
  return `paginate.page(items, params, total)`; copy `list` from a
  freshly generated repo (see [Database](docs/database.md#pagination)).
  Keep the old function under another name (`all`) if something needs
  every row.
- **Pagination (HTML):** in each `<singular>_handler.gleam`, add
  `pub const per_page = 20` and build the params in `index` with
  `paginate.Params(page: paginate.page_number(req), per_page:)` (rename
  `_req` to `req`). In `<singular>_views.gleam`, `index_view` takes
  `paginate.Page(Post)` and maps over `page.items`; copy the
  `pagination` function from a fresh view and add `rel`, `nav` and
  `span` to the imports. New apps get a `.pagination` rule in
  `priv/static/css/app.css`.
- **Pagination (JSON API):** `GET /api/<resource>` no longer answers a
  bare array. It answers
  `{"data": [...], "page": 1, "per_page": 20, "total": 3, "total_pages": 1}`
  and reads `?page=` and `?per_page=` (at most 100). Update API clients
  to read `data`. In the handler, add `pub const per_page = 20` and
  build the envelope as a fresh `gen resource ... --api` does.
- **Test database:** copy `test/<app>/support/test_db.gleam` from a
  freshly generated app with the same database (or run any `gen
  resource` or `gen auth`, which writes it when it is missing). On
  Postgres, create the test database once:
  `createdb -h localhost -U postgres <app>_test`, and do the same in
  CI before `gleam test`.
- **Dependencies:** bump `refrakt` to the release with
  `testing.with_database`, `migrate.run_quietly` and the new
  `paginate` functions.

### Added

- `testing.with_database(open:, close:, run:)` runs a test against a
  database and always closes it, also after a failed assertion. It
  knows no database driver.
- `migrate.run_quietly` applies migrations like `migrate.run` without
  printing, for test databases.
- `gen resource` and `gen auth` write `test/<app>/support/test_db.gleam`
  when the app has none. Its `with_context` gives a test a `Context` on
  a real, migrated database that is left clean: on Postgres a
  transaction on `<app>_test` (or `DATABASE_URL`) that is always
  rolled back, on SQLite a fresh shared-cache in-memory database per
  test (#21).
- Generated resource tests create, show, update and delete a record
  through the router and page through the index against the test
  database; `--api` resources do the same with JSON. Generated auth
  tests register and log in (#21).
- `paginate.page_number`, `paginate.from_request_with(req, per_page:)`,
  `paginate.previous_page`, `paginate.next_page`, `paginate.page_path`
  and `paginate.max_per_page`.
- The generated-project CI creates `app_test` on Postgres so the
  DB-backed tests run, and checks pagination of `/posts` and
  `/api/memos` with curl.

### Changed

- Generated resources paginate (#22): `repo.list(db, params)` returns a
  `paginate.Page` with `LIMIT`/`OFFSET` and a total count, the HTML
  index reads `?page=` (missing, invalid or negative is page 1) and
  renders previous/next links, and the page size is
  `pub const per_page = 20` in each handler. The JSON API index answers
  a `data` envelope with `page`, `per_page`, `total` and `total_pages`.
- `paginate.from_request` reads the query with `wisp.get_query`, so
  percent-encoded values decode, and `paginate.page` and
  `paginate.offset` treat a `per_page` below 1 as 1.
- The README of a new app with a database explains the test database.

## [0.5.0] - 2026-10-17

Milestone 0.5, "safe to put in front of users": CSRF protection,
hardened sessions, safer production defaults, working Postgres
migrations and a finished JSON API mode. Read **Upgrading** before
bumping an existing app.

### Upgrading

- **Migrations:** delete `src/<app>/migrate.gleam` and run
  `gleam run -m refrakt_cli -- migrate` to regenerate it. The new module
  calls `migrate.run` instead of `migrate.run_from_directory`, splits
  Postgres files into statements and wraps each migration in a
  transaction. `refrakt migrate` prints a warning while the old module
  is still in place. If you changed your `migrate.gleam`, compare it
  with the regenerated one and carry your changes over.
- **Dependencies:** bump `refrakt` to `>= 0.5.0 and < 1.0.0` and the
  `refrakt_cli` dev-dependency to `>= 0.5.0 and < 1.0.0`.
- **Router (CSRF):** add `import refrakt/csrf` and `use req <- csrf.protect(req)`
  to `middleware`, after `rescue_crashes`. Make sure GET handlers have no side
  effects, that your reverse proxy forwards the original `Host` header, and
  that any API called from other sites' JavaScript is matched before
  `csrf.protect`.
- **Config:** `config.load()` now returns `Result(Config, ConfigError)`. Copy
  `ConfigError`, `load_secret_key_base` and `describe_error` from a new
  `config.gleam`; in `main`, handle the error (print it and halt) and add
  `warn_if_app_env_unset`. Elsewhere (tests, `src/<app>/migrate.gleam`,
  `src/<app>/seed.gleam`) use `let assert Ok(cfg) = config.load()`.
- **Production:** with `APP_ENV=prod`, `SECRET_KEY_BASE` must now be set, be
  at least 64 bytes and differ from the development key, or the app will not
  start. Generate one with `openssl rand -hex 64`.
- **Auth:** add `web/session.gleam` from a freshly generated app and use
  `session.sign_in`, `session.sign_out` and `session.user_id` in place of the
  `_user_id` cookie in `auth_handler.gleam` and `middleware/auth.gleam`. Copy
  `dummy_hash` and `authenticate` into `domain/auth.gleam` and use
  `authenticate` in the login handler. Everyone is logged out once, because
  the cookie changes from `_user_id` to `_session`.

### Added

- `testing.json_request(method, path, body)` builds a `wisp.Request`
  with a JSON body and `content-type: application/json`, ready to pass
  to a handler in tests.
- `gen resource ... --api` generates handler tests: malformed and
  invalid bodies (400, 422) and unknown ids (404). They need no
  database. The generated-project CI now builds two `--api` resources
  and exercises the JSON API of one end to end.

### Changed

- `config.load()` in generated apps returns `Result(Config, ConfigError)`;
  `config.describe_error` explains a failure.
- `refrakt new` generates `test/<app>/router_test.gleam`, and `gen resource`
  tests now go through the router to check CSRF rejection and form
  re-rendering. `gen auth` also generates `web/session.gleam` and
  `test/<app>/web/session_test.gleam`.
- Generated apps require `refrakt >= 0.5.0` for `refrakt/csrf`.

### Fixed

- Postgres migrations with more than one statement failed, because each
  file ran as a single `pog` query. The generated migrate module now
  splits files with the new `migrate.split_statements`, which leaves
  semicolons alone inside strings, quoted identifiers, comments,
  dollar-quoted bodies (`$$ ... $$`, `$tag$ ... $tag$`) and
  `BEGIN ATOMIC ... END`. Each migration and its `_migrations` row now
  run in one transaction on Postgres and SQLite, so a failing migration
  is rolled back whole and not recorded, and the error names the file,
  the database error and, on Postgres, the failing statement. The new
  `migrate.run` takes a `query` and a `transaction` callback;
  `migrate.run_from_directory` is deprecated (#17).
- `gen resource ... --api` generated `create` and `update` handlers that
  answered `501 {"error":"not implemented"}`. The params module now
  decodes the JSON body with `gleam/dynamic/decode` and validates it
  with the same checks as the HTML form; `create` answers 201 with the
  record and a `Location` header, `update` 200, a failed validation 422
  `{"errors": {"field": "message"}}`, and a body with wrong field types
  400. `delete` answers 204 (was 200 `{"ok":true}`), and `update` and
  `delete` answer 404 for an unknown id, like `show` (#18).
- `gen resource ... --api` with a `float` field imported `gleam/float`
  without using it, a warning that failed `--warnings-as-errors` builds.

### Security

- Generated apps reject cross-site form posts (CSRF, #16). The new
  `refrakt/csrf.protect` middleware, added to the generated router, answers
  POST, PUT, PATCH and DELETE requests with `403 Forbidden` when the browser
  says they came from another site (`Sec-Fetch-Site`, else `Origin` or
  `Referer` compared with `Host`). Requests without any of these headers
  (curl, servers, JSON API clients) go ahead without their cookies. Forms
  need no hidden token field. `refrakt/testing` gained `same_origin` and
  `cross_site` request helpers.
- `gen auth` no longer reveals which emails have accounts through login
  timing: an unknown email is checked against a dummy Argon2id hash, like a
  wrong password (#19).
- `gen auth` sessions (#19): the `_session` cookie holds a signed token with
  the user id and its issue time, refused after 7 days on the server as well
  as in the browser. It is `HttpOnly`, `SameSite=Lax`, and `Secure` whenever
  `APP_ENV=prod`. Logout clears it, and `auth_views.logout_form()` renders a
  logout button.
- With `APP_ENV=prod`, generated apps refuse to start when `SECRET_KEY_BASE`
  is missing, is the development key or is shorter than 64 bytes (#20).
- Generated apps log a warning at startup when `APP_ENV` is unset, since that
  means development mode with detailed error pages (#20). `refrakt dev`
  sets `APP_ENV=dev` explicitly.

## [0.4.1] - 2026-10-17

The first release on Hex since 0.2.0. Versions 0.3.0 and 0.4.0 were
tagged but never reached Hex, so everything listed under them ships
here, including the Upgrading notes in 0.4.0.

### Added

- `validate` gained `email`, `int_between`, `float_between` and
  `confirmation`, so forms no longer hand-write those checks. `email` is a
  pragmatic check (one `@`, non-empty local part, dotted domain), the range
  checks fail on values that do not parse as a number, and `confirmation`
  compares two values without trimming them. Thanks to @ElectLive (#24, #29).

### Fixed

- The release workflow passed without publishing: Gleam asks for a
  typed confirmation on 0.x versions even with `--yes`, and printed
  "Not publishing." with exit status 0. Publishing now answers the
  prompt and fails if Gleam refuses.

## [0.4.0] - 2026-10-17

### Upgrading

Generated code belongs to your app, so existing projects need these edits by hand:

- **CLI:** `gleam add --dev refrakt_cli`, then run generators with
  `gleam run -m refrakt_cli -- <command>`. Bump `refrakt` to
  `>= 0.4.0 and < 1.0.0`.
- **Router:** change `middleware(req)` to `middleware(req, ctx)` and
  replace `use <- dev_error.rescue(req)` with a `rescue_crashes` helper
  that only uses `dev_error.rescue` when `ctx.config.env` is `Dev` and
  `wisp.rescue_crashes` otherwise. Compare with a freshly generated
  `router.gleam`. Set `APP_ENV=prod` in production.
- **Auth:** `gleam add argus`, then port `domain/auth.gleam` and the
  register handler from a freshly generated app (`hash_password` now
  returns a `Result`). Stored SHA-256 hashes will not verify; users need
  a password reset.
- **Edit forms:** post to `?_method=PUT` instead of sending `_method`
  as a hidden field.
- **Postgres repo:** read `DATABASE_URL` and include a user in the
  default URL (`postgres://postgres@localhost:5432/<app>_dev`).
- **`rate_limit.check`:** pass `key: rate_limit.by_forwarded_for(trusted_proxies: 1)`
  or `key: rate_limit.by_header("cf-connecting-ip")` to match your proxy.

### Changed

- **Breaking:** the CLI is now its own package, `refrakt_cli`, and is no
  longer part of the `refrakt` library. Run it with
  `gleam run -m refrakt_cli -- <command>` instead of
  `gleam run -m refrakt/cli -- <command>`. The repository holds the two
  packages under `packages/refrakt` and `packages/refrakt_cli`, both
  published to Hex. The library no longer depends on `argv` or `tom`.
- Generated apps depend on `refrakt >= 0.4.0` and list `refrakt_cli`
  under `[dev-dependencies]`, so the generators run from inside the app
  and never ship with it. A brand-new app is bootstrapped from a
  throwaway project; see the installation guide.
- The generated Postgres repo reads `DATABASE_URL`, falling back to a
  local server as the `postgres` user.
- The blog and tasks examples are regenerated with the current CLI
  (Argon2id auth, `mist >= 6`, working edit/delete forms) and depend on
  the in-repo packages.
- CI builds, tests, migrates, boots and smoke-tests a freshly generated
  app for no database, SQLite and Postgres, and builds the examples.
  Pushing a `v*` tag publishes both packages and creates the GitHub
  release.

### Security

- `gen auth` hashed passwords with a single unsalted SHA-256 and
  compared hashes with `==`. Generated code now uses Argon2id from the
  `argus` package (random salt per hash, constant-time verify), and
  `gen auth` adds `argus` to `gleam.toml`. `hash_password` now returns a
  `Result`. Existing projects should regenerate or port
  `domain/auth.gleam`; old SHA-256 hashes will not verify (#6).
- Routers generated by `refrakt new` showed the dev error page (error,
  stack trace, request headers) in every environment. It is now used
  only when `APP_ENV` is `dev`; `test` and `prod` log the crash and
  return a plain 500 via `wisp.rescue_crashes` (#5).
- `rate_limit` keyed clients on the raw `X-Forwarded-For` header, so a
  client could bypass the limit by changing it. **Breaking:** `check`
  now takes a `key` function; use `rate_limit.by_forwarded_for`
  (right-most entries appended by your own proxies) or
  `rate_limit.by_header` behind a proxy, or the Mist peer address when
  exposed directly (#13).

### Fixed

- `rate_limit` never forgot clients. A periodic cleanup now drops keys
  whose requests have all left their window; see
  `start_with_cleanup_interval` and `tracked_keys` (#12).
- `refrakt routes` printed the root route as `/:` instead of `/` (#8).
- Generated Postgres apps could never connect: the default URL had no
  user, which `pog.url_config` rejects, so the app crashed on boot.
- Generated edit forms sent `_method=put` as a form field, which
  `wisp.method_override` ignores, so saving an edit returned 404. Edit
  forms now post to `?_method=PUT`, and show pages get a delete button
  (`?_method=DELETE`).
- `gen resource` in a project without a database generated code that
  did not compile; it now refuses and writes nothing.
- Generated views imported `textarea`, `input` and `value` even when no
  field used them, leaving unused-import warnings.

## [0.3.0] - 2026-10-17

### Added

- Library modules: `cors`, `jobs`, `mailer`, `paginate`, `pubsub`,
  `rate_limit`, `telemetry`, `token`, `upload`.
- CLI commands: `refrakt assets` (Tailwind/esbuild setup) and `refrakt seed`.
- `gen resource --belongs-to` for foreign-key relationships.
- Dev error page with error details, stack trace and request info.

### Fixed

- Newly generated projects failed to compile because they pinned
  `mist < 6`, which pulls in an incompatible `glisten` (#1, #3).
- The library failed to compile against `gleam_otp` 1.x.
- `jobs` now enforces `max_concurrency` and survives crashing jobs.
- `token.verify` accepts data that contains dots.
- `upload` strips NUL bytes from filenames.
- `gen auth` generates SQLite code in SQLite projects and refuses to run
  without a database (#2).
- `refrakt migrate` works in SQLite projects; the generated migration
  module compiles again.
- The generated Postgres users migration is a single statement, as pog
  requires.

### Changed

- Generated projects require `mist >= 6.0`, `wisp >= 2.2.2`,
  `lustre >= 5.7` and `refrakt >= 0.3`.
- Library dependencies updated; `gleam_otp` and `gleam_crypto` are now
  direct dependencies, and the unused `glint` dependency was removed.
- Development toolchain pinned to Gleam 1.19.

## [0.2.0] - 2026-03-09

### Added

- JSON API mode for `gen resource`.
- `gen live` with a WebSocket transport.
- Smarter `refrakt migrate` and a file-watching `refrakt dev`.

## [0.1.0] - 2026-03-09

### Added

- `refrakt new` with optional PostgreSQL or SQLite support.
- Generators: `gen page`, `gen resource`, `gen auth`, `gen migration`,
  and `gen island` for Lustre islands.
- `refrakt migrate`, `refrakt dev`, `refrakt routes`, `refrakt build`.
- Library helpers for validation, flash messages, migrations and testing.
- Documentation, tutorial and examples.

[Unreleased]: https://github.com/raskell-io/refrakt/compare/v0.5.0...HEAD
[0.5.0]: https://github.com/raskell-io/refrakt/compare/v0.4.1...v0.5.0
[0.4.1]: https://github.com/raskell-io/refrakt/compare/v0.4.0...v0.4.1
[0.4.0]: https://github.com/raskell-io/refrakt/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/raskell-io/refrakt/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/raskell-io/refrakt/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/raskell-io/refrakt/releases/tag/v0.1.0
