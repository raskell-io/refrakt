# Installation

## Prerequisites

- **Gleam** 1.14 or later — [gleam.run/getting-started](https://gleam.run/getting-started/)
- **Erlang/OTP** 27 or later
- **rebar3** (installed automatically with most Erlang distributions)
- A C compiler (`cc`) — `gen auth` uses Argon2 and the SQLite driver is
  a NIF; both compile on first build

Optional:
- **PostgreSQL** — if using `--db postgres`
- **SQLite** — nothing to install for `--db sqlite`; the driver bundles it

### Using mise (recommended)

If you use [mise](https://mise.jdx.dev/) for toolchain management:

```bash
mise use gleam@1.19
mise use erlang@27
mise use rebar@3
```

## The two packages

Refrakt is two Gleam packages on Hex:

| Package | What it is | How an app uses it |
|---------|------------|--------------------|
| [`refrakt`](https://hex.pm/packages/refrakt) | Small runtime library (validation, flash, migrations, ...) | `[dependencies]` |
| [`refrakt_cli`](https://hex.pm/packages/refrakt_cli) | Code generator | `[dev-dependencies]` only |

There is no global binary. The CLI is a Gleam module you run with
`gleam run -m refrakt_cli -- <command>` from a project that depends on it.
Every app created by `refrakt_cli new` already lists it as a
dev-dependency.

## Create your first project

Because the CLI runs from inside a Gleam project, the very first app is
bootstrapped from a throwaway one:

```bash
gleam new refrakt_bootstrap
cd refrakt_bootstrap
gleam add --dev refrakt_cli
gleam run -m refrakt_cli -- new ../my_app
cd ../my_app
rm -rf ../refrakt_bootstrap
gleam run
```

Visit http://localhost:4000 — you should see the welcome page.

From now on, run every generator from inside `my_app`:

```bash
gleam run -m refrakt_cli -- gen page about
gleam run -m refrakt_cli -- help
```

### A shorter command

The rest of the documentation writes CLI commands as `refrakt <command>`.
Create that alias in your shell:

```bash
alias refrakt='gleam run -m refrakt_cli --'
```

The alias works in any project that depends on `refrakt_cli`, i.e. in
every generated app (and in the bootstrap project above).

### With a database

```bash
# PostgreSQL
refrakt new ../my_app --db postgres

# SQLite
refrakt new ../my_app --db sqlite
```

### Without a database

```bash
refrakt new ../my_app
```

This is the default. Pages work without a database; `gen resource` and
`gen auth` need one. You can add a database later by adding `pog` or
`sqlight` to your `gleam.toml` dependencies and a `data/repo.gleam`
(see [Database](database.md)).

## Verify your setup

```bash
cd my_app
gleam build    # Should compile without errors
gleam test     # Should pass
gleam run      # Should start on http://localhost:4000
```

## Next steps

- [Tutorial: Build a Blog](tutorial.md) — 10-minute walkthrough
- [Project Structure](project-structure.md) — understand the directory layout
- [CLI Commands](cli.md) — see all available commands
