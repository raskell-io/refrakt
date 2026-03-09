<div align="center">

<h1 align="center">
  Refrakt
</h1>

<p align="center">
  <em>A convention-first web framework for Gleam.</em><br>
  <em>Productive like Phoenix, explicit like Gleam, composable with Wisp and Lustre.</em>
</p>

<p align="center">
  <a href="https://gleam.run/">
    <img alt="Gleam" src="https://img.shields.io/badge/Gleam-1.14+-ffaff3?logo=data:image/svg%2bxml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHdpZHRoPSIyNCIgaGVpZ2h0PSIyNCIgdmlld0JveD0iMCAwIDI0IDI0IiBmaWxsPSJ3aGl0ZSI+PHBhdGggZD0iTTEyIDJMMiA3bDEwIDUgMTAtNS0xMC01ek0yIDE3bDEwIDUgMTAtNS0xMC01LTEwIDV6TTIgMTJsMTAgNSAxMC01LTEwLTUtMTAgNXoiLz48L3N2Zz4=&style=for-the-badge" />
  </a>
  <a href="https://hex.pm/packages/refrakt">
    <img alt="Hex" src="https://img.shields.io/badge/Hex-v0.2.0-8b5cf6?style=for-the-badge" />
  </a>
  <a href="LICENSE">
    <img alt="License" src="https://img.shields.io/badge/License-MIT-22c55e?style=for-the-badge" />
  </a>
  <a href="https://github.com/raskell-io/refrakt/actions">
    <img alt="CI" src="https://img.shields.io/badge/CI-passing-22c55e?style=for-the-badge" />
  </a>
</p>

<p align="center">
  <a href="docs/tutorial.md">Tutorial</a> ·
  <a href="docs/README.md">Documentation</a> ·
  <a href="docs/cli.md">CLI Reference</a> ·
  <a href="https://hex.pm/packages/refrakt">Hex Package</a> ·
  <a href="CONTRIBUTING.md">Contributing</a>
</p>

</div>

---

Light enters a prism, structure emerges. Refrakt takes the Gleam ecosystem — [Wisp](https://github.com/gleam-wisp/wisp), [Lustre](https://github.com/lustre-labs/lustre), [Mist](https://github.com/rawhat/mist) — and gives you one obvious way to build serious web apps. No macros. No magic. Just conventions, generators, and plain Gleam code you own.

**One command, full CRUD.** `refrakt gen resource posts title:string body:text published:bool` generates a handler with 7 actions, Lustre HTML views, typed form validation, a domain type, database repo with raw SQL, a migration, and tests — then wires all routes into your router automatically.

<br>

## Quick Start

```bash
# Add refrakt to a Gleam project (or use it standalone)
gleam add refrakt

# Create a new project with PostgreSQL
gleam run -m refrakt/cli -- new my_app --db postgres
cd my_app

# Generate a full CRUD resource
gleam run -m refrakt/cli -- gen resource posts title:string body:text published:bool

# Start the server
gleam run
# → http://localhost:4000/posts
```

Or with SQLite — no external database needed:

```bash
gleam run -m refrakt/cli -- new my_app --db sqlite
```

<br>

## What You Get

```
my_app/
  src/
    my_app.gleam                    ← entry point (Wisp + Mist)
    my_app/
      config.gleam                  ← typed config, env-driven
      context.gleam                 ← shared context (config + db)
      router.gleam                  ← all routes, pattern matched

      web/                          ← HTTP/UI layer
        post_handler.gleam          ← 7 CRUD actions
        post_views.gleam            ← Lustre HTML (type-safe, no templates)
        forms/post_form.gleam       ← typed decoder + validation
        layouts/root_layout.gleam   ← HTML shell
        middleware/auth.gleam       ← session auth (if gen auth)

      domain/                       ← pure Gleam (zero framework imports)
        post.gleam                  ← pub type Post { Post(...) }

      data/                         ← persistence
        post_repo.gleam             ← raw SQL, typed decoders
        migrations/001_create_posts.sql
```

Every generated file looks like something a skilled Gleam developer would write by hand. There is no "framework code" vs "your code" — you own everything.

<br>

## The Router

```gleam
case wisp.path_segments(req), req.method {
  [], http.Get -> home_handler.index(req, ctx)

  ["posts"], http.Get -> post_handler.index(req, ctx)
  ["posts", "new"], http.Get -> post_handler.new(req, ctx)
  ["posts"], http.Post -> post_handler.create(req, ctx)
  ["posts", id], http.Get -> post_handler.show(req, ctx, id)
  ["posts", id, "edit"], http.Get -> post_handler.edit(req, ctx, id)
  ["posts", id], http.Put -> post_handler.update(req, ctx, id)
  ["posts", id], http.Delete -> post_handler.delete(req, ctx, id)

  _, _ -> error_handler.not_found(req)
}
```

Plain Gleam pattern matching. No DSL, no macros. A new developer reads this file and understands every route in 30 seconds.

<br>

## Commands

| Command | Description |
|---------|-------------|
| `refrakt new <name>` | Create a new project (`--db postgres`, `--db sqlite`) |
| `refrakt gen resource <name> <fields>` | Full CRUD — handler, views, form, domain, repo, migration, tests |
| `refrakt gen resource <name> <fields> --api` | JSON API — handler, domain, repo, migration (no views) |
| `refrakt gen page <name>` | Static page — handler + route |
| `refrakt gen auth` | Authentication — login, register, logout, sessions, middleware |
| `refrakt gen island <name>` | Lustre interactive island (client-side) |
| `refrakt gen live <name>` | Lustre server component (real-time over WebSocket) |
| `refrakt gen migration <name>` | SQL migration file |
| `refrakt migrate` | Run pending migrations |
| `refrakt build` | Compile Lustre islands to JavaScript |
| `refrakt dev` | Dev server with file watching (auto-rebuild) |
| `refrakt routes` | Print the route table |

<br>

## Principles

**Conventions over assembly** — One project layout. One routing shape. One way to structure handlers, views, forms, and repos. Spend time building features, not debating file organization.

**Generated code is your code** — Every file the CLI creates is plain Gleam you can read, modify, and own. No hidden framework internals.

**No magic** — Routing is pattern matching. Views are functions. Validation is functions. If you can read Gleam, you can read a Refrakt app.

**Build on the ecosystem** — Wisp handles HTTP. Lustre handles HTML. Mist runs the server. Pog or Sqlight talk to the database. Refrakt adds conventions and generators — it doesn't reinvent the stack.

<br>

## Features

- [x] Project scaffolding with Postgres or SQLite
- [x] Full CRUD resource generator (handler, views, forms, domain, repo, migration, tests)
- [x] JSON API mode (`--api` flag, routes under `/api/`)
- [x] Authentication generator (login, register, logout, sessions, middleware)
- [x] Lustre interactive islands (`gen island`)
- [x] Lustre server components (`gen live`) with WebSocket transport
- [x] Migration runner (auto-generates and runs migration module)
- [x] Validation helpers (required, min/max length, inclusion, format)
- [x] Flash messages (signed cookies)
- [x] Test helpers (request builders)
- [x] Dev error page (dark theme, error details, stack trace, request info)
- [x] Dev file watcher (auto-rebuild on `src/` changes via fswatch)
- [x] Auto-format all generated code
- [x] Route table printer
- [x] 21 tests (12 unit + 9 integration)
- [x] 17 documentation files
- [x] 2 example apps (blog + tasks)

<br>

## Examples

### Blog (PostgreSQL)

```bash
gleam run -m refrakt/cli -- new blog --db postgres
cd blog
gleam run -m refrakt/cli -- gen resource posts title:string body:text published:bool
gleam run -m refrakt/cli -- gen auth
gleam run -m refrakt/cli -- gen page about
```

See [`examples/blog/`](examples/blog/) for the complete app.

### Tasks (SQLite)

```bash
gleam run -m refrakt/cli -- new tasks_app --db sqlite
cd tasks_app
gleam run -m refrakt/cli -- gen resource tasks title:string completed:bool
```

See [`examples/tasks_app/`](examples/tasks_app/) for the complete app.

<br>

## Documentation

| Guide | Description |
|-------|-------------|
| [Installation](docs/installation.md) | Prerequisites, install, first project |
| [Tutorial: Build a Blog](docs/tutorial.md) | 10 steps from `refrakt new` to working app |
| [Project Structure](docs/project-structure.md) | Directory layout, three layers, dependency flow |
| [Routing](docs/routing.md) | Pattern matching, params, middleware |
| [Handlers](docs/handlers.md) | Request handling, responses, JSON |
| [Views & Templates](docs/views.md) | Lustre HTML, layouts, components |
| [Forms & Validation](docs/forms.md) | Typed decoders, validation helpers |
| [Database](docs/database.md) | Postgres, SQLite, repos, migrations |
| [Authentication](docs/authentication.md) | Sessions, middleware, customization |
| [Testing](docs/testing.md) | Generated tests, test helpers |
| [Deployment](docs/deployment.md) | Production builds, Docker, Fly.io |
| [CLI Reference](docs/cli.md) | All commands with flags and examples |
| [Configuration](docs/configuration.md) | Environment variables, config types |
| [Field Types](docs/field-types.md) | All types with Gleam/HTML/SQL mappings |
| [Lustre Integration](docs/lustre-integration.md) | Islands and server components |

<br>

## Built On

| Package | Role |
|---------|------|
| [Wisp](https://github.com/gleam-wisp/wisp) | HTTP handlers, middleware, request/response |
| [Lustre](https://github.com/lustre-labs/lustre) | HTML templating, interactive islands, server components |
| [Mist](https://github.com/rawhat/mist) | HTTP server, WebSocket |
| [Pog](https://hex.pm/packages/pog) | PostgreSQL client |
| [Sqlight](https://hex.pm/packages/sqlight) | SQLite client |

<br>

## Building from Source

```bash
git clone https://github.com/raskell-io/refrakt.git
cd refrakt

# Install toolchain
mise install   # Gleam 1.14, Erlang 27, rebar3

# Build and test
gleam build
gleam test     # 21 tests
```

<br>

## License

MIT — see [LICENSE](LICENSE).
