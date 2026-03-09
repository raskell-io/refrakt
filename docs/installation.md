# Installation

## Prerequisites

- **Gleam** 1.14 or later — [gleam.run/getting-started](https://gleam.run/getting-started/)
- **Erlang/OTP** 27 or later
- **rebar3** (installed automatically with most Erlang distributions)

Optional:
- **PostgreSQL** — if using `--db postgres`
- **SQLite** — if using `--db sqlite` (usually pre-installed on macOS/Linux)

### Using mise (recommended)

If you use [mise](https://mise.jdx.dev/) for toolchain management:

```bash
mise use gleam@1.14
mise use erlang@27
mise use rebar@3
```

## Install Refrakt

Refrakt is a Gleam package on Hex. Install the CLI by adding it to a
global or project dependency:

```bash
gleam add refrakt
```

Then run commands with:

```bash
gleam run -m refrakt/cli -- <command>
```

Or create an alias in your shell:

```bash
alias refrakt='gleam run -m refrakt/cli --'
```

## Create your first project

```bash
refrakt new my_app
cd my_app
gleam run
```

Visit http://localhost:4000 — you should see the welcome page.

### With a database

```bash
# PostgreSQL
refrakt new my_app --db postgres

# SQLite
refrakt new my_app --db sqlite
```

### Without a database

```bash
refrakt new my_app
```

This is the default. You can add a database later by manually adding
`pog` or `sqlight` to your `gleam.toml` dependencies.

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
