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
| `HOST` | In containers | `localhost` | Interface to listen on (`0.0.0.0` in the `gen deploy` image) |
| `DATABASE_URL` | Postgres | local `_dev` database | PostgreSQL connection URL |
| `DATABASE_PATH` | SQLite | `<app>.db` | SQLite database file (`/data/<app>.db` in the image) |

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

Generate the container files:

```bash
refrakt gen deploy          # Dockerfile, .dockerignore (and bin/migrate)
refrakt gen deploy --fly    # also fly.toml, see below
```

They are your files: edit them freely. Running `gen deploy` again
writes only the files that are missing and lists the others as
skipped.

The `Dockerfile` has two stages:

1. **Build** on `ghcr.io/gleam-lang/gleam:v1.19.2-erlang-alpine`, with
   `build-base` installed: argus (Argon2 password hashing from
   `refrakt gen auth`) and sqlight's SQLite driver compile C code. It
   runs `gleam export erlang-shipment`.
2. **Runtime** on `erlang:29.1.1-alpine`, the Erlang/OTP release the
   Gleam image is built on. It copies the shipment to `/app` and runs
   `entrypoint.sh run` as the non-root user `app`, with `APP_ENV=prod`,
   `HOST=0.0.0.0` (the app listens on `localhost` otherwise, which
   nothing outside the container reaches), `PORT=4000`, `EXPOSE 4000`
   and a `HEALTHCHECK` on the health route.

The versions are `ARG`s at the top (`GLEAM_VERSION`,
`ERLANG_VERSION`). Raise them together: the runtime must run the same
OTP release the build used. `gen deploy` warns when `gleam.toml`
requires a newer Gleam than the image has.

The build compiles from source, so the context must hold everything
the app needs at runtime: commit or build `priv/static` assets (Tailwind
CSS, `refrakt build` islands) before `docker build`.

```bash
docker build -t my_app .
docker run -p 4000:4000 -e SECRET_KEY_BASE=$(openssl rand -hex 64) my_app
```

### SQLite

The database file lives in `/data` (`DATABASE_PATH=/data/my_app.db`).
Mount a volume there, or it disappears with the container:

```bash
docker run -p 4000:4000 -v my_app_data:/data \
  -e SECRET_KEY_BASE=$(openssl rand -hex 64) my_app
```

The container applies pending migrations when it starts
(`bin/migrate && exec ./entrypoint.sh run`). One container owns a
SQLite file, so this is safe; do not run several against one volume.

Apps generated before 0.7 keep the database at `my_app.db` in the
working directory. In `data/repo.gleam`, return
`envoy.get("DATABASE_PATH") |> result.unwrap("my_app.db")` outside of
tests (`gen deploy` warns until you do).

### PostgreSQL

Pass `DATABASE_URL`. Run migrations with the same image before the
new release takes traffic:

```bash
docker run --rm -e DATABASE_URL=postgres://user:password@db:5432/my_app \
  -e SECRET_KEY_BASE=... my_app bin/migrate
docker run -p 4000:4000 -e DATABASE_URL=postgres://user:password@db:5432/my_app \
  -e SECRET_KEY_BASE=... my_app
```

## Run migrations in production

A shipment has no Gleam and no sources, so `gleam run -m my_app/migrate`
(what `refrakt migrate` runs) does not work there. `gen deploy` writes
`bin/migrate`, which runs the compiled module instead:

```sh
erl -pa ./*/ebin -noshell -eval "my_app@@main:run(my_app@migrate)"
```

It runs from `/app`, where the Dockerfile copies
`src/my_app/data/migrations`, applies the pending migrations (each in a
transaction, recorded in `_migrations`) and exits with status 1 when
one fails. `src/my_app/migrate.gleam` is the same module `refrakt
migrate` uses; `gen deploy` writes it when it is missing. The migration
reads the config like the app, so it needs `SECRET_KEY_BASE` under
`APP_ENV=prod`.

- **SQLite:** the container runs `bin/migrate` on start.
- **PostgreSQL:** run `bin/migrate` once per release, before the new
  containers start (`docker run --rm ... bin/migrate`, a Kubernetes
  job, or Fly's `release_command`).

Without Docker, run the same command from `build/erlang-shipment` after
copying `src/my_app/data/migrations` next to it, or apply the SQL files
with `psql` / `sqlite3` in order.

## Deploy to Fly.io

```bash
refrakt gen deploy --fly
fly apps create my-app
fly secrets set SECRET_KEY_BASE=$(openssl rand -hex 64)
fly deploy
```

`fly.toml` names the app after the project (underscores become dashes,
which Fly requires), builds the `Dockerfile`, sets `APP_ENV=prod` and
`PORT=4000`, and checks `GET /healthz` (or your existing health route):

```toml
app = "my-app"

[build]
  dockerfile = "Dockerfile"

[env]
  APP_ENV = "prod"
  PORT = "4000"

[http_service]
  internal_port = 4000
  force_https = true

  [[http_service.checks]]
    method = "GET"
    path = "/healthz"
```

**PostgreSQL:** attach a database, which sets the `DATABASE_URL`
secret (`fly postgres attach <postgres-app>`, or `fly secrets set
DATABASE_URL=...`). `fly.toml` has

```toml
[deploy]
  release_command = "/app/bin/migrate"
```

so `fly deploy` migrates before the new machines start, and stops when
a migration fails.

**SQLite:** create the volume first, `fly volumes create my_app_data
--size 1`. `fly.toml` mounts it on `/data`, sets `DATABASE_PATH`, and
keeps one machine running. A release_command machine has no volume, so
migrations run when the machine starts instead. Run a single machine:
each machine gets a volume, and so a database, of its own.

## Production checklist

- [ ] `SECRET_KEY_BASE` set to a random 64+ byte string (the app refuses to start in prod otherwise)
- [ ] `APP_ENV=prod` set (otherwise crashes show the dev error page and session cookies are not forced `Secure`)
- [ ] Served over HTTPS, with the proxy passing the original `Host` header
- [ ] Database migrations run
- [ ] Static assets accessible at `/static/`
- [ ] Health check endpoint (`gen deploy` adds `GET /healthz`)
- [ ] Logging configured (Wisp logs requests by default)
- [ ] TLS termination (via reverse proxy, Vela, or cloud provider)

## Health check

`refrakt gen deploy` adds a route for load balancers and the
Dockerfile's `HEALTHCHECK`, unless the router already has a
`["healthz"]` or `["health"]` route:

```gleam
// In router.gleam:
["healthz"], http.Get -> wisp.ok()
```
