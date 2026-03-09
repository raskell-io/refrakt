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
| `SECRET_KEY_BASE` | **Yes** | dev fallback | Cookie signing key (64+ chars) |
| `APP_ENV` | No | `dev` | `dev`, `test`, or `prod` |

### Generate a secret key

```bash
openssl rand -hex 64
```

### PostgreSQL

Set `DATABASE_URL` or modify `repo.gleam` to read your connection
string from the environment.

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

- [ ] `SECRET_KEY_BASE` set to a random 64+ character string
- [ ] `APP_ENV=prod` set
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
