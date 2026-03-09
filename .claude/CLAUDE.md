# Refrakt

> **A convention-first web framework for Gleam. Productive like Phoenix, explicit like Gleam, composable with Wisp and Lustre.**

Refrakt gives Gleam developers Phoenix-like coherence and Rails-like convention without macros, magic, or hidden runtime tricks. It is a CLI code generator that produces plain Gleam code, plus a small library of helpers for validation, flash messages, migrations, and testing.

## Philosophy

1. **Conventions over assembly** — One obvious way to structure an app. Default project layout, naming rules, routing shape.
2. **Generated code is your code** — The CLI produces plain Gleam files you own and modify. No "framework code" vs "your code" distinction.
3. **No magic, no macros** — Gleam intentionally lacks metaprogramming. Refrakt respects that. Routing is pattern matching. Views are functions. Validation is functions.
4. **Wisp + Lustre, not NIH** — Build on the ecosystem, don't replace it. Wisp handles HTTP. Lustre handles HTML. Refrakt adds the conventions and generators.
5. **Boring where boring is good** — CRUD, forms, validation, sessions, layouts. Get this right before chasing real-time cleverness.

**Before adding anything, ask:**
- Does this make a new Gleam developer more productive in their first hour?
- Is this convention or configuration? Prefer convention.
- Could this be generated code instead of framework code?

## Architecture

```
refrakt (monorepo)
├── packages/
│   ├── refrakt/          ← Library: validation, flash, migrations, test helpers
│   └── refrakt_cli/      ← CLI: code generators, project scaffolding
└── docs/                 ← Golden path, ADRs, tutorials
```

### Two Deliverables

**`refrakt` (library)** — Published to Hex. Imported by generated projects. Contains:
- Validation helpers (required, min_length, max_length, format, etc.)
- Flash message helpers (signed cookies)
- Migration runner (SQL files, tracking table)
- Test helpers (request builders)
- Dev error page

**`refrakt_cli` (CLI tool)** — Installed as a binary. Generates code. Contains:
- `refrakt new` — scaffold a project
- `refrakt gen page` — handler + route
- `refrakt gen resource` — full CRUD (handler, views, form, domain type, repo, migration)
- `refrakt gen auth` — starter auth system
- `refrakt gen migration` — SQL migration file
- `refrakt migrate` — run pending migrations
- `refrakt dev` — dev server wrapper
- `refrakt routes` — print route table

### Generated App Structure

```
my_app/
  src/
    my_app.gleam                    ← entry point
    my_app/
      config.gleam                  ← typed config, env-driven
      router.gleam                  ← all routes, pattern matched

      web/                          ← HTTP/UI layer
        handlers, views, forms,
        layouts, components, middleware

      domain/                       ← business logic (no framework imports)

      data/                         ← persistence (repos, migrations)

  priv/static/                      ← CSS, JS, assets
  test/                             ← tests mirror src/ structure
```

### Dependency Flow

```
web/ → domain/     ✓
data/ → domain/    ✓
domain/ → web/     ✗ (never)
domain/ → data/    ✗ (never)
```

## Key Concepts

### Router

One file. Pattern matching on `wisp.path_segments(req)` and `req.method`. No DSL, no registration. Generators patch this file by inserting before the catch-all.

### Handlers

Plain functions: `fn(Request, Context) -> Response` or `fn(Request, Context, String) -> Response` for parameterized routes. No traits, no interfaces.

### Views

Lustre HTML functions for type-safe templating. Views produce `Element(Nil)`. Layouts wrap `Element(Nil) → String` via `element.to_document_string`.

### Forms

Typed decoders with validation. Two types per form: `PostForm` (display state for re-rendering) and `PostParams` (validated input). Errors are `List(#(String, String))`.

### Domain

Pure Gleam types. No framework imports. No database imports. Your business logic.

### Repos

Raw SQL via Pog (Postgres) or Sqlight (SQLite). Typed decoders. No ORM.

## Ecosystem Dependencies

| Package | Version | Purpose |
|---------|---------|---------|
| `wisp` | >= 2.2 | HTTP handlers, middleware, request/response |
| `lustre` | >= 5.6 | HTML templating (server-side), views |
| `mist` | >= 5.0 | HTTP server (BEAM) |
| `pog` | >= 4.1 | PostgreSQL client (optional) |
| `sqlight` | >= 1.0 | SQLite client (optional) |
| `gleam_http` | >= 4.3 | Core HTTP types |
| `gleam_stdlib` | >= 0.44 | Standard library |
| `gleam_erlang` | >= 0.34 | Erlang interop |
| `gleeunit` | >= 1.0 | Test runner |

## Rules

| File | Purpose |
|------|---------|
| [gleam-standards.md](rules/gleam-standards.md) | Gleam coding standards |
| [architecture.md](rules/architecture.md) | Architecture decisions and constraints |
| [conventions.md](rules/conventions.md) | Naming, structure, and generated code conventions |
| [workflow.md](rules/workflow.md) | Commands, testing, releases |

## Quick Reference

### Common Commands

```bash
# Development
gleam build
gleam test
gleam format --check

# Run the CLI locally
gleam run -m refrakt_cli -- new my_app
gleam run -m refrakt_cli -- gen resource posts title:string body:text

# Docs
gleam docs build
```

### Key Files

| Path | Purpose |
|------|---------|
| `packages/refrakt/src/refrakt.gleam` | Library entry point |
| `packages/refrakt/src/refrakt/validate.gleam` | Validation helpers |
| `packages/refrakt/src/refrakt/flash.gleam` | Flash message helpers |
| `packages/refrakt/src/refrakt/migrate.gleam` | Migration runner |
| `packages/refrakt/src/refrakt/testing.gleam` | Test helpers |
| `packages/refrakt_cli/src/refrakt_cli.gleam` | CLI entry point |
| `packages/refrakt_cli/src/refrakt_cli/gen/` | Code generators |
| `docs/GOLDEN_PATH.md` | Golden path specification |
