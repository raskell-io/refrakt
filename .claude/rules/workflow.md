# Workflow

Commands, processes, and common tasks for working on Refrakt.

---

## Development Environment

### Prerequisites

- Gleam 1.14+ (via mise)
- Erlang/OTP 27+ (via mise)
- rebar3 (via mise)

### Setup

```bash
mise install
gleam build
gleam test
```

---

## Common Commands

### Building

```bash
# Build all packages
gleam build

# Check types without full build
gleam check
```

### Testing

```bash
# Run all tests
gleam test

# Run with output
gleam test -- --nocapture
```

### Formatting

```bash
# Format all code
gleam format

# Check formatting (CI)
gleam format --check
```

### Documentation

```bash
# Generate docs
gleam docs build

# Open in browser
gleam docs build --open
```

---

## Working on the CLI

### Running CLI Commands Locally

```bash
# Test `refrakt new`
gleam run -m refrakt_cli -- new test_app

# Test `refrakt gen resource`
cd test_app
gleam run -m refrakt_cli -- gen resource posts title:string body:text published:bool

# Test `refrakt gen page`
gleam run -m refrakt_cli -- gen page about
```

### Testing Generated Output

After running a generator, verify:

1. `gleam build` compiles without errors
2. `gleam test` passes
3. Generated files follow conventions (check against `rules/conventions.md`)
4. Router patch is correct (routes before catch-all)
5. `gleam format --check` passes on generated code

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
gleam format
gleam build
gleam test
```

---

## Release Process

### Version Bump

1. Update version in `gleam.toml` for both packages
2. Update `CHANGELOG.md`
3. Commit: `chore: bump version to X.Y.Z`
4. Tag: `git tag vX.Y.Z`
5. Push: `git push && git push --tags`

### Publishing to Hex

```bash
# Publish library first (CLI depends on it)
cd packages/refrakt && gleam publish
cd packages/refrakt_cli && gleam publish
```

---

## CI

### GitHub Actions

| Workflow | Trigger | Purpose |
|----------|---------|---------|
| `ci.yml` | Push, PR | Build, test, format check |
| `release.yml` | Tag push | Publish to Hex |

### Local CI Simulation

```bash
gleam format --check
gleam build
gleam test
gleam docs build
```
