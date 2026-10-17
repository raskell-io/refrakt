# Configuration

Refrakt uses environment variables for configuration. The generated
`config.gleam` reads them at startup and returns a typed `Config`
record, or a `ConfigError` that stops the app from starting.

## Environment variables

| Variable | Default | Description |
|----------|---------|-------------|
| `PORT` | `4000` | HTTP server port |
| `SECRET_KEY_BASE` | dev fallback, none in prod | Secret for signing cookies (64+ bytes) |
| `APP_ENV` | `dev` (with a startup warning) | Environment: `dev`, `test`, or `prod` |

`refrakt dev` sets `APP_ENV=dev` itself. Running the app any other way
without `APP_ENV` also means `dev`, and `main` logs a warning, since
development mode shows stack traces on errors.

## Config module

Every generated project includes `src/<app>/config.gleam`:

```gleam
pub type Config {
  Config(
    port: Int,
    port_string: String,
    secret_key_base: String,
    env: Env,
  )
}

pub type Env {
  Dev
  Test
  Prod
}

pub type ConfigError {
  MissingSecretKeyBase
  DevelopmentSecretKeyBase
  ShortSecretKeyBase(bytes: Int)
}

const development_secret_key_base = "dev-secret-key-base-..."

pub fn load() -> Result(Config, ConfigError) {
  let port =
    envoy.get("PORT")
    |> result.try(int.parse)
    |> result.unwrap(4000)

  let env = case envoy.get("APP_ENV") {
    Ok("prod") -> Prod
    Ok("test") -> Test
    _ -> Dev
  }

  use secret_key_base <- result.try(load_secret_key_base(env))

  Ok(Config(
    port: port,
    port_string: int.to_string(port),
    secret_key_base: secret_key_base,
    env: env,
  ))
}

fn load_secret_key_base(env: Env) -> Result(String, ConfigError) {
  case envoy.get("SECRET_KEY_BASE"), env {
    Error(_), Prod -> Error(MissingSecretKeyBase)
    Error(_), _ -> Ok(development_secret_key_base)
    Ok(key), Prod if key == development_secret_key_base ->
      Error(DevelopmentSecretKeyBase)
    Ok(key), _ ->
      case string.byte_size(key) {
        bytes if bytes < 64 -> Error(ShortSecretKeyBase(bytes))
        _ -> Ok(key)
      }
  }
}
```

`main` prints `config.describe_error(error)` and exits with status 1
when `load` fails. So production refuses to start without its own
`SECRET_KEY_BASE`, with the development key (it is in your source
code, so it is not secret), or with a key shorter than 64 bytes. A key
shorter than 64 bytes is refused in every environment. Generate one
with `openssl rand -hex 64`.

In tests, `let assert Ok(cfg) = config.load()` gives the development
configuration.

## Adding custom config

Edit `config.gleam` to add your own fields:

```gleam
pub type Config {
  Config(
    port: Int,
    port_string: String,
    secret_key_base: String,
    env: Env,
    database_url: String,           // custom
    smtp_host: String,              // custom
    max_upload_size: Int,           // custom
  )
}
```

Read them from environment variables:

```gleam
let database_url =
  envoy.get("DATABASE_URL")
  |> result.unwrap("postgres://postgres@localhost:5432/my_app_dev")

let smtp_host =
  envoy.get("SMTP_HOST")
  |> result.unwrap("localhost")

let max_upload_size =
  envoy.get("MAX_UPLOAD_SIZE")
  |> result.try(int.parse)
  |> result.unwrap(10_000_000)
```

## Context

The `Context` type in `context.gleam` holds the config and database
connection. It's created in `main()` and passed to every handler:

```gleam
pub type Context {
  Context(config: config.Config, db: pog.Connection)
}
```

Add custom fields (cache, external clients, feature flags) here:

```gleam
pub type Context {
  Context(
    config: config.Config,
    db: pog.Connection,
    redis: redis.Connection,    // custom
  )
}
```

## No .env files

Refrakt does not read `.env` files. Set environment variables using
your shell, a process manager, or your deployment tool:

```bash
# Shell
export PORT=8080
export SECRET_KEY_BASE=abc123...
gleam run

# Inline
PORT=8080 SECRET_KEY_BASE=abc123... gleam run

# direnv (.envrc)
export PORT=8080
export SECRET_KEY_BASE=abc123...
```

## Per-environment config

Use the `Env` type in your code to change behavior:

```gleam
case cfg.env {
  Dev -> // verbose logging, dev error pages
  Test -> // in-memory database, no external calls
  Prod -> // production settings
}
```

The database repo already uses this pattern — `Test` uses a test
database (or `:memory:` for SQLite), while `Dev` and `Prod` use
their respective databases.
