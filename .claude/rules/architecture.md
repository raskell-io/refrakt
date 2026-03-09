# Architecture Rules

---

## Two Packages, Not One

Refrakt ships as two separate packages:

1. **`refrakt`** (library) — runtime helpers imported by generated projects
2. **`refrakt_cli`** (CLI) — code generator, development tool only

The CLI is never a runtime dependency. Generated code imports `refrakt`,
`wisp`, `lustre`, and database drivers — not `refrakt_cli`.

## Build On the Ecosystem

Refrakt does not replace Wisp, Lustre, or Mist. It wraps and composes them.

| Concern | Owned By |
|---------|----------|
| HTTP request/response | Wisp |
| Middleware/pipeline | Wisp |
| HTML rendering | Lustre |
| HTTP server | Mist |
| Database queries | Pog / Sqlight |
| Routing conventions | Refrakt |
| Form validation | Refrakt |
| Code generation | Refrakt CLI |
| Migration runner | Refrakt |
| Flash messages | Refrakt |
| Test helpers | Refrakt |

**If Wisp or Lustre already does it, don't rebuild it.**

## BEAM Only

Refrakt targets the Erlang/BEAM runtime. No JavaScript target support.
This simplifies everything: one compilation target, one server model,
OTP process supervision, Mist as the blessed HTTP server.

## Generated Code Quality

Generated code must be:

1. **Readable** — A developer who has never seen Refrakt should understand
   a generated file without consulting documentation.
2. **Idiomatic** — It should look like code a skilled Gleam developer
   would write by hand.
3. **Modifiable** — No framework magic. Every generated file can be
   edited freely without breaking other generated files.
4. **Consistent** — Every generator produces files that follow the exact
   same patterns. Handler signatures, view signatures, form patterns,
   repo patterns — all uniform.

## Router Is One File

All routes live in `src/<app>/router.gleam`. One file, pattern matching.
No route registration, no macros, no dynamic dispatch.

Generators patch this file by inserting route patterns before the
catch-all `_, _ -> error_handler.not_found(req)`.

## Dependency Flow

```
web/ → domain/     ✓   (handlers use domain types)
data/ → domain/    ✓   (repos return domain types)
domain/ → web/     ✗   (domain has no HTTP concepts)
domain/ → data/    ✗   (domain has no database concepts)
web/ → data/       ✓   (handlers call repos)
```

Domain modules must have zero framework imports. No wisp, no lustre,
no pog, no sqlight. Pure Gleam types and functions.

## Library Surface Area

The `refrakt` library must stay small. It provides:

1. Validation helpers — composable, return error lists
2. Flash messages — built on signed cookies
3. Migration runner — SQL files, tracking table
4. Test helpers — request builders
5. Dev error page — rich HTML for development mode

**Do not add framework abstractions.** No base handler type, no
controller trait, no model layer, no plugin system. The generated
code is the framework.

## CLI Is a Code Generator

The CLI:
1. Reads `gleam.toml` to find the project name
2. Generates `.gleam` and `.sql` files from templates
3. Patches `router.gleam` to add routes
4. Patches `gleam.toml` to add dependencies when needed

It does not:
- Run at runtime
- Do metaprogramming
- Modify code beyond router patches
- Manage processes or servers (except `refrakt dev` wrapping `gleam run`)

## No ORM

Data access uses raw SQL with typed decoders. No query builder,
no schema DSL, no active record pattern. SQL is readable, debuggable,
and doesn't hide what's happening.

## Migrations Are SQL Files

Migrations are plain `.sql` files in `src/<app>/data/migrations/`.
The migration runner reads them in order, tracks applied migrations
in a `_migrations` table, and runs pending ones. No up/down, no
rollback automation. Keep it simple.
