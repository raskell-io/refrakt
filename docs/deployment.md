# Deployment

Refrakt apps are Gleam applications targeting the Erlang/BEAM runtime.
Deploy them like any BEAM application.

## Build for production

```bash
gleam export erlang-shipment
```

This creates a precompiled Erlang release in `build/erlang-shipment/`
that can run on any machine with the same Erlang/OTP version installed.

## Environment variables

Set these in production:

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `PORT` | No | `4000` | HTTP port |
| `SECRET_KEY_BASE` | **Yes** | dev fallback (not in prod) | Cookie signing key (64+ bytes) |
| `APP_ENV` | **Yes** (set to `prod`) | `dev` | `dev`, `test`, or `prod` |

Leaving `APP_ENV` unset means `dev`, which shows the detailed error page
(error, stack trace, request headers) to anyone who triggers a crash.
Always set `APP_ENV=prod` in production; crashes then return a plain 500.
When `APP_ENV` is unset the app logs a warning at startup.

With `APP_ENV=prod` the app refuses to start, printing why and exiting
with status 1, when `SECRET_KEY_BASE` is

- not set,
- the development key from `src/<app>/config.gleam` (it is in your
  source code, so it is not secret), or
- shorter than 64 bytes.

### Reverse proxies

The CSRF check compares the browser's `Origin` with the `Host` header,
so a proxy in front of the app must pass the original `Host` (nginx:
`proxy_set_header Host $host;`; Caddy and Fly.io do this already).
Otherwise form posts from browsers without `Sec-Fetch-Site` get
`403 Forbidden`. See [Routing](routing.md#csrf-protection).

### Generate a secret key

```bash
openssl rand -hex 64
```

### PostgreSQL

Set `DATABASE_URL`; the generated `repo.gleam` reads the connection
string from it (for example
`postgres://user:password@db.internal:5432/my_app`).

## Deploy with Vela

[Vela](https://github.com/raskell-io/vela) deploys BEAM releases to
bare metal with zero downtime.

```bash
# Create a Vela.toml
vela init --name my_app --domain my-app.example.com

# Build and deploy
gleam export erlang-shipment
vela deploy build/erlang-shipment
```

## Deploy with Docker

Create a `Dockerfile`:

```dockerfile
FROM ghcr.io/gleam-lang/gleam:v1.14.0-erlang-alpine

WORKDIR /app
COPY . .

# Only needed after `refrakt gen auth`: argus builds an Argon2 NIF from C.
RUN apk add --no-cache build-base

RUN gleam export erlang-shipment

CMD ["build/erlang-shipment/entrypoint.sh", "run"]
```

Build and run:

```bash
docker build -t my_app .
docker run -p 4000:4000 \
  -e SECRET_KEY_BASE=$(openssl rand -hex 64) \
  -e APP_ENV=prod \
  my_app
```

## Deploy to Fly.io

Create a `fly.toml`:

```toml
app = "my-app"

[build]
  dockerfile = "Dockerfile"

[http_service]
  internal_port = 4000
  force_https = true

[env]
  APP_ENV = "prod"
```

```bash
fly launch
fly secrets set SECRET_KEY_BASE=$(openssl rand -hex 64)
fly deploy
```

## Run migrations in production

### PostgreSQL

```bash
psql $DATABASE_URL < src/my_app/data/migrations/001_create_posts.sql
```

Or use the programmatic migration runner in your app startup:

```gleam
import refrakt/migrate

pub fn main() {
  // ... connect to database ...
  let _ = migrate.run_from_directory(execute, query_strings, migrations_dir)
  // ... start server ...
}
```

### SQLite

```bash
sqlite3 /path/to/my_app.db < src/my_app/data/migrations/001_create_posts.sql
```

## Production checklist

- [ ] `SECRET_KEY_BASE` set to a random 64+ byte string (the app refuses to start in prod otherwise)
- [ ] `APP_ENV=prod` set (otherwise crashes show the dev error page and session cookies are not forced `Secure`)
- [ ] Served over HTTPS, with the proxy passing the original `Host` header
- [ ] Database migrations run
- [ ] Static assets accessible at `/static/`
- [ ] Health check endpoint (add `GET /health` route)
- [ ] Logging configured (Wisp logs requests by default)
- [ ] TLS termination (via reverse proxy, Vela, or cloud provider)

## Health check

Add a health check route for load balancers:

```gleam
// In router.gleam:
["health"], http.Get -> wisp.ok() |> wisp.string_body("ok")
```
