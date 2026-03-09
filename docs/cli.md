# CLI Commands

The Refrakt CLI is a code generator. Run it with:

```bash
gleam run -m refrakt/cli -- <command>
```

Or set up an alias:

```bash
alias refrakt='gleam run -m refrakt/cli --'
```

## Commands

### `refrakt new <name>`

Create a new Refrakt project.

```bash
refrakt new my_app
refrakt new my_app --db postgres
refrakt new my_app --db sqlite
refrakt new path/to/my_app    # extracts "my_app" as package name
```

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
```

**Creates:**
- Handler (7 actions: index, show, new, create, edit, update, delete)
- Views (list, detail, form with proper field types)
- Form decoder with validation
- Domain type
- Database repo (Pog or Sqlight, auto-detected)
- SQL migration
- Tests

**Patches:** `router.gleam` with 7 RESTful routes.

**Field types:** See [Field Types](field-types.md).

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

**Patches:** `router.gleam` with 5 auth routes.

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

Show migration instructions. The migration runner is a library module
(`refrakt/migrate`) that runs from within your app.

---

### `refrakt dev`

Start the dev server with `APP_ENV=dev`.

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
