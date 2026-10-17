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
CSS, tests, and optionally a database repo.

---

### `refrakt gen resource <name> <fields...>`

Generate a full CRUD resource.

```bash
refrakt gen resource posts title:string body:text published:bool
refrakt gen resource comments author:string body:text post_id:int
refrakt gen resource products name:string price:float in_stock:bool

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
- Tests

**Creates (API mode with `--api`):**
- Handler (5 actions: index, show, create, update, delete — JSON)
- Params module (`web/forms/<singular>_form.gleam`): the params type,
  a `gleam/dynamic/decode` decoder for the JSON body, and
  `validate_params` with the same checks the HTML form runs
- Domain type
- Database repo
- SQL migration
- Tests (bad bodies and unknown ids; no database needed)

**Patches:** `router.gleam` with RESTful routes (HTML: 7 routes,
API: 5 routes under `/api/` prefix).

**API responses.** Every response, errors included, is JSON:

| Request | Success | Errors |
|---------|---------|--------|
| `GET /api/posts` | 200, array of records | |
| `GET /api/posts/:id` | 200, the record | 404 |
| `POST /api/posts` | 201, the record, `Location: /api/posts/:id` | 400, 422 |
| `PUT /api/posts/:id` | 200, the record | 400, 422, 404 |
| `DELETE /api/posts/:id` | 204, no body | 404 |

- **404** `{"error": "not found"}` — no row with that id, or an id that
  is not a number.
- **422** `{"errors": {"title": "Title is required"}}` — the body
  decoded but failed validation (one message per field).
- **400** `{"error": "invalid request body", "details": [{"path":
  "title", "expected": "String", "found": "Int"}]}` — a field has the
  wrong type or is `null`, or the body is not an object. A body that is
  not JSON at all is rejected by `wisp.require_json` with a plain-text
  400, and a content type other than `application/json` with 415.

Fields missing from the body get the value an empty HTML form field
would (`""`, `0`, `0.0`, `false`), so a missing `string` or `text`
field is a 422 "is required", like in the HTML form. A `float` field
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
views, auth form, auth middleware, migration, tests.

**Patches:** `router.gleam` with 5 auth routes, and `gleam.toml` with the
`argus` dependency (Argon2 password hashing) if it isn't there yet.

Works with PostgreSQL and SQLite projects; the repo and migration match
the project's database. Requires a database (`--db postgres` or
`--db sqlite`).

See [Authentication](authentication.md) for details.

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

Start the dev server with file watching.

```bash
refrakt dev
```

Sets `APP_ENV=dev` and runs `gleam run`. If `fswatch` is installed,
watches `src/` for changes and auto-rebuilds + restarts.

```bash
refrakt dev
```

Wraps `gleam run` with the dev environment variable set.

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
