# Contributing to Refrakt

Thanks for your interest in contributing to Refrakt.

## Setup

```bash
git clone https://github.com/raskell-io/refrakt.git
cd refrakt

# Install toolchain (Gleam 1.14, Erlang 27, rebar3)
mise install

# Build
gleam build

# Run tests (21 tests: 12 unit + 9 integration)
gleam test

# Format
gleam format
```

## Before submitting

```bash
gleam format --check
gleam build
gleam test
```

All three must pass. There are no exceptions.

## Project structure

```
src/
  refrakt.gleam              ← library entry point
  refrakt/
    validate.gleam           ← validation helpers
    flash.gleam              ← flash message helpers
    migrate.gleam            ← migration runner
    testing.gleam            ← test helpers
    cli.gleam                ← CLI entry point
    cli/
      new.gleam              ← refrakt new
      gen.gleam              ← gen resource, gen page, gen auth, gen island
      templates.gleam        ← file content templates
      routes.gleam           ← refrakt routes
      build.gleam            ← refrakt build (island JS)
      dev.gleam              ← refrakt dev
      migrate_cmd.gleam      ← refrakt migrate
      project.gleam          ← gleam.toml reader
      format.gleam           ← post-generation formatting
      types.gleam             ← shared types (DbChoice)

test/
  refrakt_test.gleam         ← unit tests (validation)
  refrakt/cli/
    gen_test.gleam           ← integration tests (generators)

docs/                        ← user documentation
examples/
  blog/                      ← Postgres example
  tasks_app/                 ← SQLite example
```

## How generators work

1. Templates in `templates.gleam` produce file content as strings
2. Generator functions in `gen.gleam` write files via `simplifile`
3. Router patching finds `_, _ ->` catch-all and inserts routes before it
4. `gleam format` runs on all generated `.gleam` files automatically

## Adding a new generator

1. Add the template function(s) in `gen.gleam` or `templates.gleam`
2. Add the public function in `gen.gleam`
3. Add the command match in `cli.gleam`
4. Add an integration test in `test/refrakt/cli/gen_test.gleam`
5. Update `docs/cli.md`

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

## Reporting issues

- Use [GitHub Issues](https://github.com/raskell-io/refrakt/issues)
- Include the Gleam version (`gleam --version`)
- Include the command that failed and the full error output
- If a generated file is wrong, include the generated file content

## License

By contributing, you agree that your contributions will be licensed
under the MIT License.
