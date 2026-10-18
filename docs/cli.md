# CLI Commands

The Refrakt CLI is a code generator, published as the `refrakt_cli`
package. Generated apps list it as a dev-dependency, so inside an app you
run it with:

```bash
gleam run -m refrakt_cli -- <command>
```

The commands below are written as `refrakt <command>`, which assumes this
alias:

```bash
alias refrakt='gleam run -m refrakt_cli --'
```

To create your first app, when there is no project to run the CLI from
yet, see [Installation](installation.md#create-your-first-project).

## Commands

### `refrakt new <name>`

Create a new Refrakt project.

```bash
refrakt new my_app
refrakt new my_app --db postgres
refrakt new my_app --db sqlite
refrakt new path/to/my_app    # extracts "my_app" as package name
```

The generated `gleam.toml` depends on `refrakt` and lists `refrakt_cli`
under `[dev-dependencies]`, so the generators keep working inside the new
app.

**Flags:**

| Flag | Description |
|------|-------------|
| `--db postgres` | Add PostgreSQL (Pog) dependency and repo |
| `--db sqlite` | Add SQLite (Sqlight) dependency and repo |
| `--no-db` | No database (default) |

**Creates:** Full project with config, router, home handler, layout,
CSS, tests, and optionally a database repo, plus
`.refrakt/generated.toml`, the record of generators that
[`refrakt diff`](#refrakt-diff-path) replays.

---

### `refrakt gen resource <name> <fields...>`

Generate a full CRUD resource.

```bash
refrakt gen resource posts title:string body:text published:bool
refrakt gen resource products name:string price:float in_stock:bool

# Optional (nullable) fields; quote them, ( ) is shell syntax
refrakt gen resource events title:string 'starts_on:optional(date)' 'capacity:optional(int)'

# A child of posts: post_id foreign key, select of posts, comments on the post's page
refrakt gen resource comments author:string body:text --belongs-to posts

# JSON API mode (no views/forms, routes under /api/)
refrakt gen resource posts title:string body:text --api
```

**Creates (HTML mode):**
- Handler (7 actions: index, show, new, create, edit, update, delete)
- Views (list, detail, form with proper field types)
- Form decoder with validation
- Domain type
- Database repo (Pog or Sqlight, auto-detected)
- SQL migration
- Tests, including create/show/update/delete and pagination through the
  router against a real database
- `test/<app>/support/test_db.gleam`, if the app has none yet (see
  [Testing](testing.md#tests-against-the-database))

**Creates (API mode with `--api`):**
- Handler (5 actions: index, show, create, update, delete — JSON)
- Params module (`web/forms/<singular>_form.gleam`): the params type,
  a `gleam/dynamic/decode` decoder for the JSON body, and
  `validate_params` with the same checks the HTML form runs
- Domain type
- Database repo
- SQL migration
- Tests: bad bodies and unknown ids (no database needed), and
  create/show/update/delete and pagination against the test database
- `test/<app>/support/test_db.gleam`, if the app has none yet

**Patches:** `router.gleam` with RESTful routes (HTML: 7 routes,
API: 5 routes under `/api/` prefix).

**`--belongs-to <parent>`** (also `--belongs-to=<parent>`): the parent
resource must already exist. Adds a `<parent>_id` field with a foreign
key (`ON DELETE CASCADE`), `list_for_<parent>` (and, for HTML,
`<parent>_options`) in the repo, a check that the parent exists (422
otherwise), a select of parents in the form, and
`web/components/<child>_list.gleam`, which the CLI renders on the
parent's show page when the parent's handler is as generated (it
prints the lines to add otherwise). The child's DB-backed tests insert
their parent through `test/<app>/support/<parent>_fixture.gleam`, which
the CLI writes when it is missing, along with the fixtures of the
parent's own parents (see [Testing](testing.md#fixtures-for---belongs-to-parents)).
Routes stay flat. Details in
[Relations](database.md#relations---belongs-to).

**Errors.** An unknown field type (`price:money`), a spec without a
type, an invalid or repeated field name, an unknown option, or a
`--belongs-to` parent that does not exist is reported, and nothing is
written.

**API responses.** Every response, errors included, is JSON:

| Request | Success | Errors |
|---------|---------|--------|
| `GET /api/posts?page=1&per_page=20` | 200, one page of records (below) | |
| `GET /api/posts/:id` | 200, the record | 404 |
| `POST /api/posts` | 201, the record, `Location: /api/posts/:id` | 400, 422 |
| `PUT /api/posts/:id` | 200, the record | 400, 422, 404 |
| `DELETE /api/posts/:id` | 204, no body | 404 |

**Pagination.** Both index actions show one page, newest first, with
`LIMIT`/`OFFSET`. The page size is a constant in the handler,
`pub const per_page = 20`; change it there.

- HTML: `GET /posts?page=2`. A missing, invalid, zero or negative `page`
  is page 1. The index view renders "Previous" and "Next" links
  (`rel="prev"`/`rel="next"`) and "Page 2 of 5". A page past the end
  lists nothing and links back to the last page.
- API: `GET /api/posts?page=2&per_page=50` answers an envelope with the
  page's records under `data`:

  ```json
  {"data": [{"id": 7, "title": "..."}], "page": 2, "per_page": 50, "total": 57, "total_pages": 2}
  ```

  `per_page` defaults to the handler's constant and is kept between 1
  and 100 (`paginate.max_per_page`); `page` behaves as in HTML.

- **404** `{"error": "not found"}` — no row with that id, or an id that
  is not a number.
- **422** `{"errors": {"title": "Title is required"}}` — the body
  decoded but failed validation (one message per field).
- **400** `{"error": "invalid request body", "details": [{"path":
  "title", "expected": "String", "found": "Int"}]}` — a field has the
  wrong type or is `null` (only `optional(T)` fields may be `null`), or
  the body is not an object. A body that is
  not JSON at all is rejected by `wisp.require_json` with a plain-text
  400, and a content type other than `application/json` with 415.

Fields missing from the body get the value an empty HTML form field
would (`""`, `0`, `0.0`, `false`), so a missing `string` or `text`
field is a 422 "is required", like in the HTML form. An `optional(T)`
field may be missing or `null` (both `None`), and `None` is answered as
`null`. A `float` field
accepts JSON integers too. `update` checks the body before looking up
the record, so a bad body gets 400/422 even for an unknown id.

**Field types:** See [Field Types](field-types.md).

**Requires** a database (`--db postgres` or `--db sqlite`); in a
project without one the command refuses and writes nothing.

**Naming:** The resource name should be plural (`posts`, not `post`).
The generator singularizes it for types (`Post`) and file names
(`post_handler.gleam`).

---

### `refrakt gen page <name>`

Generate a simple page handler.

```bash
refrakt gen page about
refrakt gen page contact
refrakt gen page pricing
```

**Creates:** Handler and test file.
**Patches:** `router.gleam` with a GET route.

---

### `refrakt gen auth`

Generate a complete authentication system.

```bash
refrakt gen auth
```

**Creates:** 9 files — user domain, user repo, auth handler, auth
views, auth form, auth middleware, migration, tests (including a
register and log-in round trip against the test database), plus
`test/<app>/support/test_db.gleam` if the app has none yet.

**Patches:** `router.gleam` with 5 auth routes, and `gleam.toml` with the
`argus` dependency (Argon2 password hashing) if it isn't there yet.

Works with PostgreSQL and SQLite projects; the repo and migration match
the project's database. Requires a database (`--db postgres` or
`--db sqlite`).

See [Authentication](authentication.md) for details.

---

### `refrakt gen deploy [--fly]`

Generate the files to run the app in a container.

```bash
refrakt gen deploy          # Dockerfile, .dockerignore
refrakt gen deploy --fly    # also fly.toml
```

**Creates** (each only if it does not exist; existing files are listed
as skipped and left alone):

- `Dockerfile`: a build stage on `ghcr.io/gleam-lang/gleam` (Erlang,
  Alpine) with a C toolchain for NIFs (argus, sqlight) that runs
  `gleam export erlang-shipment`, and a runtime stage on the matching
  `erlang` Alpine image that runs the shipment as a non-root user with
  `APP_ENV=prod`, `HOST=0.0.0.0`, `PORT=4000` and a `HEALTHCHECK`.
- `.dockerignore`: `build`, `.git`, SQLite files, `.env` files.
- With a database: `bin/migrate`, which runs `src/<app>/migrate.gleam`
  from the shipment, and that module if `refrakt migrate` has not
  written it yet. SQLite images migrate on start, Postgres ones through
  `bin/migrate` before a release.
- With `--fly`: `fly.toml` with the app name, internal port,
  `APP_ENV=prod`, an HTTP health check, and a `release_command`
  (Postgres) or a volume mount on `/data` (SQLite).

**Patches:** `router.gleam` with `GET /healthz` (200) unless it already
has a `["healthz"]` or `["health"]` route, which the health checks then
use.

Prints the `docker build` / `docker run` and `fly` commands to run
next, and warns when gleam.toml requires a Gleam the image does not
have, or when an app generated before 0.7 does not read `HOST` or
`DATABASE_PATH`. See [Deployment](deployment.md).

---

### `refrakt gen island <name>`

Generate a Lustre interactive island.

```bash
refrakt gen island counter
refrakt gen island search
```

**Creates:**
- Island module (Lustre client-side app with init/update/view)
- Embed helper (server-side mount point and script tag)

See [Lustre Integration](lustre-integration.md) for details.

---

### `refrakt gen live <name>`

Generate a Lustre server component with WebSocket transport.

```bash
refrakt gen live dashboard
refrakt gen live chat
```

**Creates:**
- Server component (Lustre app with init/update/view running on server)
- WebSocket socket module (transport scaffold with TODO instructions)
- Live handler (HTML page that connects via WebSocket)

**Patches:** `router.gleam` with a GET route for the live page.

The server component runs on the BEAM. DOM patches are sent to the
browser over WebSocket. See [Lustre Integration](lustre-integration.md).

---

### `refrakt gen migration <name>`

Generate an empty SQL migration file.

```bash
refrakt gen migration add_email_to_posts
refrakt gen migration create_comments
```

**Creates:** Timestamped SQL file in `data/migrations/`.

---

### `refrakt routes`

Print the route table from `router.gleam`.

```bash
refrakt routes
```

**Output:**

```
GET     /                   home_handler.index
GET     /posts              post_handler.index
GET     /posts/new          post_handler.new
POST    /posts              post_handler.create
GET     /posts/:id          post_handler.show
```

---

### `refrakt diff [path...]`

Show how the app differs from what the installed `refrakt_cli` would
generate for it. Generated code belongs to your app, so upgrading
`refrakt_cli` never changes it; `refrakt diff` shows which template
improvements you are missing.

```bash
refrakt diff                          # every generated file
refrakt diff src/my_app/router.gleam  # one file
refrakt diff src/my_app/web           # a directory (several paths are fine)
refrakt diff --stat                   # only list the changed files
```

It renders the app again into a temporary directory: `refrakt new` with
the app's name and database, then every generator the app ran, in order.
It then prints a unified diff of each generated file against the app's
copy (with `diff -u` when available). Lines with `-` are the app's, lines
with `+` are what the current templates generate. It never writes into
the app.

Framework files come first (router, config, context, entry point,
layouts, middleware, session, test support), then everything else by
path. A summary follows:

```
--- a/src/my_app/router.gleam
+++ b/src/my_app/router.gleam
@@ -49,7 +49,6 @@
     ["events", id], http.Delete -> event_handler.delete(req, ctx, id)
-    ["about-us"], http.Get -> about_handler.index(req, ctx)
     ["about"], http.Get -> about_handler.index(req, ctx)
...

Differ from the templates (2):
  src/my_app/router.gleam
  src/my_app/web/post_views.gleam
Only in the app (not generated; not compared) (1):
  src/my_app/data/migrations/006_create_tags.sql

Lines with + are what this refrakt_cli generates; lines with - are the app's.
```

- **Differ from the templates:** generated files you (or an older
  refrakt_cli) changed.
- **Only in the templates:** files the current generators write that the
  app lacks, shown as new files in the diff, such as a module a newer
  version added.
- **Only in the app:** your own files under `src/`, `test/` and `priv/`
  (hand-written modules, `gen migration` files), and a `Dockerfile`,
  `.dockerignore`, `fly.toml` or `bin/migrate` that `gen deploy` did not
  write. Listed for reference, never compared.

The files of `gen deploy` (`Dockerfile`, `.dockerignore`, `fly.toml`,
`bin/migrate`) are compared like the others, so a newer Dockerfile
template shows up as a difference; `refrakt diff src test priv` leaves
them out.

Migration numbers depend on how many migrations existed when a generator
ran, so a rendered `003_create_posts.sql` is compared with the app's
`*_create_posts.sql`.

**Exit status:** `0` when no generated file differs or is missing, `1`
when some do, `2` on a usage error (for example outside an app). That
makes it usable in CI, for instance to check that an app still matches
its templates exactly, or limited to the files you never customise:
`refrakt diff src/my_app/web/layouts`.

**Which generators ran:** `refrakt new` writes `.refrakt/generated.toml`
and every `gen page`, `gen resource`, `gen auth`, `gen island`,
`gen live` and `gen deploy` appends its arguments (running the same command twice records
it once). Commit the file. If you delete a resource or page, delete its
entry; if you renamed one, adjust it.

```toml
[new]
name = "my_app"
db = "sqlite"

[[gen]]
args = ["resource", "posts", "title:string", "body:text", "published:bool"]

[[gen]]
args = ["auth"]
```

Apps created before refrakt_cli 0.7 have no manifest. `refrakt diff`
then infers the generators from the app's files and prints what it
inferred: resources from `data/migrations/*_create_<plural>.sql` with a
matching handler and domain type (fields, `optional(...)` and
`--belongs-to` from the CREATE TABLE, Bool vs Int from the domain type,
text from the form's textarea, `--api` when there are no views), auth
from `auth_handler.gleam`, pages, live components and islands from their
modules, ordered like their routes. On SQLite a `date` or `datetime`
field of an `--api` resource cannot be told from a string. To pin it
down, save the inferred manifest and correct it:

```bash
mkdir -p .refrakt
refrakt diff --print-manifest > .refrakt/generated.toml
```

#### Upgrading an app

1. Bump `refrakt` and `refrakt_cli` in `gleam.toml` (see the
   **Upgrading** notes of each release in the
   [changelog](../CHANGELOG.md)) and run `gleam deps download`.
2. Run `refrakt diff` (or `refrakt diff --stat` first) to see what the
   new templates generate differently.
3. Apply the changes you want by hand. To take a file's changes whole,
   `refrakt diff src/my_app/router.gleam | git apply` (or `patch -p1`)
   applies that diff; it also undoes your own edits to that file, so
   review it first.

---

### `refrakt migrate`

Run pending database migrations.

```bash
refrakt migrate
```

On first run, generates a `src/<app>/migrate.gleam` module that
connects to the database and runs pending SQL files. Then executes it.
Each file runs in its own transaction, together with the row that
records it in `_migrations`; see [Database](database.md#running-migrations).

Requires a database (`--db postgres` or `--db sqlite`).

---

### `refrakt build`

Compile Lustre islands to JavaScript.

```bash
refrakt build
```

Finds island modules in `web/islands/`, compiles them to JS, and
copies output to `priv/static/js/islands/`.

---

### `refrakt dev`

Run the app in development, rebuild on changes and reload open pages.

```bash
refrakt dev
```

Sets `APP_ENV=dev`, runs `gleam build` and starts the app with
`gleam run`. Then it watches `src/` and `priv/`:

- **A change under `src/`** runs `gleam build`. When the build succeeds,
  the server restarts and open pages reload once the new server accepts
  connections. When it fails, the compiler error is printed and the
  previous server keeps running; the next successful build takes over.
- **A change only under `priv/`** (CSS, JS, images) needs no rebuild,
  since static files are served as they are: open pages just reload.
- **Bursts of events** (an editor saving in several steps, switching
  branches) are debounced into one rebuild: `refrakt dev` waits until no
  event has arrived for 200ms. Editor scratch files (dotfiles such as
  `.post.gleam.swp`, `post.gleam~`, vim's `4913`) are ignored.

**Watchers.** At startup `refrakt dev` says which watcher it uses:

| Watcher | When |
|---------|------|
| `fswatch` | installed (`brew install fswatch`, or your Linux package manager) |
| `inotifywait` | on Linux without `fswatch`, from `inotify-tools` |
| polling | otherwise: compares size, time and contents of every file under `src/` and `priv/` every 500ms |

Polling works everywhere and needs nothing installed; the other two
notice changes sooner and cost nothing while idle. If `fswatch` or
`inotifywait` exits, `refrakt dev` falls back to polling that directory.

**Live reload.** `refrakt dev` runs a small Server-Sent Events server
next to your app, on `http://localhost:35729/events`, and passes its
port to the app as `REFRAKT_LIVE_RELOAD_PORT`. The generated root layout
ends its `<body>` with `live_reload.script()` from `refrakt/live_reload`,
a few lines of JavaScript that open an `EventSource` to that address and
call `location.reload()` on a `reload` event. `refrakt dev` sends that
event after each restart and after each `priv/` change.

Nothing of this reaches production: `live_reload.script()` renders
nothing unless `APP_ENV=dev` *and* `REFRAKT_LIVE_RELOAD_PORT` holds a
port, so with `APP_ENV=prod` or `APP_ENV=test` (or `gleam run` on its
own) the page has no script, and the app itself never serves a reload
endpoint; the event stream lives in the `refrakt dev` process.

| Variable | Default | Purpose |
|----------|---------|---------|
| `PORT` | `4000` | The app's port; `refrakt dev` waits for it before reloading pages |
| `REFRAKT_LIVE_RELOAD_PORT` | `35729` | Port of the live reload event stream |

If the live reload port is taken, `refrakt dev` says so and runs without
live reload; set `REFRAKT_LIVE_RELOAD_PORT` to a free port. Apps
generated before 0.7 need one line in their root layout to get live
reload; see the changelog.

---

### `refrakt help`

Show the help message with all commands.

```bash
refrakt help
refrakt --help
refrakt -h
```

---

### `refrakt version`

Print the version.

```bash
refrakt version
refrakt --version
```
