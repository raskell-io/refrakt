# Workflow

Commands, processes, and common tasks for working on Refrakt.

---

## Development Environment

### Prerequisites

- Gleam 1.14+ (via mise; the repo pins 1.19)
- Erlang/OTP 27+ (via mise)
- rebar3 (via mise)

### Setup

```bash
mise install
mise run build   # both packages
mise run test    # both packages
```

The repository holds two Gleam packages. Run `gleam` inside one of them:

| Directory | Package |
|-----------|---------|
| `packages/refrakt` | runtime library |
| `packages/refrakt_cli` | code generator |

---

## Common Commands

Run these in `packages/refrakt` or `packages/refrakt_cli`, or use the
`mise run` task that loops over both.

### Building

```bash
# Build (warnings fail the build, as in CI)          mise run build
gleam build --warnings-as-errors

# Check types without full build                     mise run check
gleam check
```

### Testing

```bash
# Run all tests                                      mise run test
gleam test
```

### Formatting

```bash
# Format all code                                    mise run fmt
gleam format src test

# Check formatting (CI)                              mise run fmt:check
gleam format --check src test
```

### Documentation

```bash
# Generate docs                                      mise run doc
gleam docs build

# Open in browser
gleam docs build --open
```

---

## Working on the CLI

### Running CLI Commands Locally

```bash
cd packages/refrakt_cli

# Test `refrakt_cli new`
gleam run -m refrakt_cli -- new /tmp/test_app --db sqlite
```

A generated app depends on `refrakt` and `refrakt_cli` from Hex. To run
generators against your working copy, point both at the repo with path
dependencies in the app's `gleam.toml`:

```toml
[dependencies]
refrakt = { path = "/path/to/refrakt/packages/refrakt" }

[dev-dependencies]
refrakt_cli = { path = "/path/to/refrakt/packages/refrakt_cli" }
```

```bash
cd /tmp/test_app
gleam run -m refrakt_cli -- gen resource posts title:string body:text published:bool
gleam run -m refrakt_cli -- gen page about
```

### Testing Generated Output

`.github/scripts/test-generated-app.sh` does all of this (it is what CI
runs):

```bash
mise exec -- .github/scripts/test-generated-app.sh none
mise exec -- .github/scripts/test-generated-app.sh sqlite
SKIP_RUNTIME=1 mise exec -- .github/scripts/test-generated-app.sh postgres
```

After running a generator, verify:

1. `gleam build --warnings-as-errors` compiles without errors
2. `gleam test` passes
3. Generated files follow conventions (check against `rules/conventions.md`)
4. Router patch is correct (routes before catch-all)
5. `gleam format --check src test` passes on generated code

---

## Working on the Library

### Validation Helpers

Test with:
```bash
gleam test -- validate
```

### Migration Runner

Test with SQLite in-memory database:
```bash
gleam test -- migrate
```

### Flash Messages

Test with mock request/response:
```bash
gleam test -- flash
```

---

## Git Workflow

### Branch Naming

```
feature/gen-resource-command
feature/validation-helpers
fix/router-patch-ordering
docs/golden-path-update
```

### Commit Messages

```
feat(cli): add gen resource command

Generates handler, views, form, domain type, repo, and migration
for a full CRUD resource. Patches router with RESTful routes.
```

```
feat(lib): add validation helpers

Required, min_length, max_length, format, inclusion validators.
All composable, return List(#(String, String)) errors.
```

### Pre-commit Checklist

```bash
mise run fmt
mise run build
mise run test
```

---

## Release Process

Both packages share one version number and are released together.

### Version Bump

1. Update `version` in `packages/refrakt/gleam.toml` and
   `packages/refrakt_cli/gleam.toml`
2. Update the version printed by `refrakt_cli version`
   (`packages/refrakt_cli/src/refrakt_cli.gleam`) and, for a new minor
   version, the `refrakt`/`refrakt_cli` requirements in the generated
   `gleam.toml` (`templates.gleam_toml`)
3. Update `CHANGELOG.md`: rename `## [Unreleased]` to
   `## [X.Y.Z] - YYYY-MM-DD`, add a fresh `## [Unreleased]`, fix the
   compare links at the bottom. If any template changed (anything an
   existing app would get differently from `refrakt diff`), the section
   must have an `### Upgrading` list with the hand edit for each change.
   Generated code belongs to the app, so this is the only way existing
   apps learn about it
4. Commit: `chore: bump version to X.Y.Z`
5. Tag: `git tag vX.Y.Z`
6. Push: `git push && git push --tags`

### Publishing

Pushing the tag runs `.github/workflows/release.yml`, which:

1. Fails unless the tag matches both package versions, the CLI version
   string and a `CHANGELOG.md` section
2. Runs format check, build and tests for both packages
3. Publishes `packages/refrakt`, then `packages/refrakt_cli`, with
   `gleam publish --yes` (needs the `HEXPM_API_KEY` repository secret)
4. Creates the GitHub release with the changelog section as notes

Do not publish by hand unless the workflow is broken. If you must:

```bash
cd packages/refrakt && gleam publish
cd ../refrakt_cli && gleam publish
```

---

## CI

### GitHub Actions

| Workflow | Trigger | Purpose |
|----------|---------|---------|
| `ci.yml` | Push, PR | Per package: format, build, test, docs. Generated apps (none/sqlite/postgres): build, test, format, migrate, boot, curl. Examples: build, test |
| `release.yml` | Tag push (`v*`) | Verify versions, test, publish both packages to Hex, GitHub release |

### Local CI Simulation

```bash
mise run ci
mise exec -- .github/scripts/test-generated-app.sh sqlite
mise run test:examples
```
