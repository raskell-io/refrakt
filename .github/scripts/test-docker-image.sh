#!/usr/bin/env bash
#
# Build the Docker image that `refrakt gen deploy` writes for a generated
# app and smoke-test the container (#26).
#
#   1. `refrakt_cli new app --db <db>`, run from packages/refrakt_cli
#   2. copy the in-repo library and CLI into app/vendor/ and point the
#      app's path dependencies there, so they are inside the Docker build
#      context and the image covers HEAD rather than Hex
#   3. `gen resource posts ...`, `gen auth` (argus compiles a C NIF in the
#      build stage) and `gen deploy --fly`
#   4. `docker build`
#   5. sqlite: run the container with a volume on /data (it migrates on
#      start), smoke-test /, /healthz, /posts and /register, restart it and
#      check that the data survived on the volume
#      postgres: start postgres:17 on a Docker network, run `bin/migrate`
#      in a one-off container (twice: the second applies nothing), then run
#      the app against it and smoke-test the same routes
#
# Usage:
#   .github/scripts/test-docker-image.sh <sqlite|postgres> [work-dir]
#
# Needs docker, plus gleam/erlang on PATH for the generators (locally:
# mise exec -- .github/scripts/test-docker-image.sh sqlite).
#
# Environment:
#   PORT  host port the container is published on (default 4000)

set -euo pipefail

db="${1:-}"
case "$db" in
  sqlite | postgres) ;;
  *)
    echo "usage: $0 <sqlite|postgres> [work-dir]" >&2
    exit 2
    ;;
esac

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
work="${2:-$(mktemp -d "${TMPDIR:-/tmp}/refrakt-docker.XXXXXX")}"
mkdir -p "$work"
work="$(cd "$work" && pwd)"
app_dir="$work/app"
port="${PORT:-4000}"
base_url="http://localhost:$port"
name="refrakt-gen-$db-$$"
image="$name:latest"

step() { printf '\n==> %s\n' "$*"; }
fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

cleanup() {
  docker logs "$name-app" > "$work/container.log" 2>&1 || true
  docker rm -f "$name-app" "$name-db" > /dev/null 2>&1 || true
  docker network rm "$name-net" > /dev/null 2>&1 || true
  docker volume rm "$name-data" > /dev/null 2>&1 || true
  docker image rm "$image" > /dev/null 2>&1 || true
}
trap cleanup EXIT

# Run gleam, retrying when the Hex API rate-limits or fails the resolution.
gleam_hex() {
  local attempt log
  log="$(mktemp)"
  for attempt in 1 2 3 4 5; do
    if gleam "$@" 2>&1 | tee "$log"; then
      rm -f "$log"
      return 0
    fi
    if ! grep -q "Hex API" "$log"; then
      rm -f "$log"
      return 1
    fi
    echo "Hex API error (attempt $attempt), retrying..." >&2
    sleep $((attempt * 15))
  done
  rm -f "$log"
  return 1
}

cli() { gleam_hex run --no-print-progress -m refrakt_cli -- "$@"; }

rm -rf "$app_dir"

step "Generating app (db: $db) in $app_dir"
(
  cd "$root/packages/refrakt_cli"
  gleam_hex deps download
  cli new "$app_dir" --db "$db"
)

step "Vendoring the in-repo refrakt and refrakt_cli into the build context"
cd "$app_dir"
mkdir vendor
for package in refrakt refrakt_cli; do
  mkdir "vendor/$package"
  (cd "$root/packages/$package" && tar --exclude ./build -cf - .) |
    (cd "vendor/$package" && tar xf -)
done
sed -i.bak \
  -e 's|^refrakt = .*|refrakt = { path = "vendor/refrakt" }|' \
  -e 's|^refrakt_cli = .*|refrakt_cli = { path = "vendor/refrakt_cli" }|' \
  gleam.toml
rm gleam.toml.bak
grep -q '^refrakt = { path = "vendor/refrakt" }' gleam.toml || fail "gleam.toml has no refrakt dependency"
gleam_hex deps download

step "Running generators"
cli gen resource posts title:string body:text published:bool
cli gen auth
gleam_hex deps download
deploy_output="$(cli gen deploy --fly)"
echo "$deploy_output"
for file in Dockerfile .dockerignore bin/migrate src/app/migrate.gleam fly.toml; do
  [ -f "$file" ] || fail "gen deploy did not write $file"
done
[ -x bin/migrate ] || fail "bin/migrate is not executable"
grep -q '\["healthz"\], http.Get' src/app/router.gleam || fail "no /healthz route"
second="$(cli gen deploy --fly)"
grep -q <<<"$second" "Skipped (already exists):" || fail "a second gen deploy did not skip"
gleam_hex build --warnings-as-errors
gleam format --check src test

step "docker build"
docker build -t "$image" .

key="$(openssl rand -hex 64)"

# wait_for_app: poll /healthz until the container answers
wait_for_app() {
  for _ in $(seq 1 60); do
    if curl -fs -o /dev/null "$base_url/healthz"; then return 0; fi
    if [ "$(docker inspect -f '{{.State.Running}}' "$name-app" 2> /dev/null)" != true ]; then
      docker logs "$name-app" >&2 || true
      fail "the container exited during startup"
    fi
    sleep 1
  done
  docker logs "$name-app" >&2 || true
  fail "the container did not answer on $base_url/healthz"
}

status() {
  local method="$1" path="$2"
  shift 2
  curl -sS -o "$work/body.html" -w '%{http_code}' -X "$method" \
    -H "Origin: $base_url" "$@" "$base_url$path"
}

expect() {
  local want="$1" got="$2" what="$3"
  if [ "$got" != "$want" ]; then
    cat "$work/body.html" >&2 || true
    docker logs "$name-app" >&2 || true
    fail "$what: expected HTTP $want, got $got"
  fi
  echo "ok  $what -> $got"
}

smoke_test() {
  expect 200 "$(status GET /)" "GET /"
  expect 200 "$(status GET /healthz)" "GET /healthz"
  expect 200 "$(status GET /posts)" "GET /posts"
  expect 200 "$(status GET /register)" "GET /register"
  expect 303 "$(status POST /posts --data-urlencode "title=From Docker" \
    --data-urlencode "body=In a container")" "POST /posts"
  expect 200 "$(status GET /posts)" "GET /posts after create"
  grep -q "From Docker" "$work/body.html" || fail "the created post is missing from /posts"
  # register hashes the password with Argon2: the argus NIF loaded
  expect 303 "$(status POST /register --data-urlencode "email=docker@example.com" \
    --data-urlencode "password=correct horse battery staple" \
    --data-urlencode "password_confirmation=correct horse battery staple")" \
    "POST /register (Argon2 NIF)"
}

if [ "$db" = sqlite ]; then
  step "Running the container with a volume on /data"
  docker volume create "$name-data" > /dev/null
  docker run -d --name "$name-app" -p "$port:4000" \
    -e SECRET_KEY_BASE="$key" -v "$name-data:/data" "$image" > /dev/null
  wait_for_app
  grep -q <<<"$(docker logs "$name-app" 2>&1)" "migration(s) applied" ||
    fail "the container did not apply the migrations on start"
  [ "$(docker exec "$name-app" id -un)" = app ] || fail "the container does not run as the app user"
  smoke_test

  step "Restarting: the database survives on the volume"
  docker restart "$name-app" > /dev/null
  wait_for_app
  expect 200 "$(status GET /posts)" "GET /posts after restart"
  grep -q "From Docker" "$work/body.html" || fail "the post did not survive a restart"
  grep -q <<<"$(docker logs "$name-app" 2>&1)" "Done. 0 migration(s) applied" ||
    fail "the restart did not find the migrations applied"
else
  step "Starting postgres:17 on a Docker network"
  docker network create "$name-net" > /dev/null
  docker run -d --name "$name-db" --network "$name-net" \
    -e POSTGRES_HOST_AUTH_METHOD=trust postgres:17 > /dev/null
  for _ in $(seq 1 60); do
    if docker exec "$name-db" pg_isready -U postgres > /dev/null 2>&1; then break; fi
    sleep 1
  done
  # pg_isready can pass during the init script's temporary server; retry
  for _ in $(seq 1 30); do
    if docker exec "$name-db" createdb -U postgres app 2> /dev/null; then break; fi
    sleep 1
  done
  docker exec "$name-db" psql -U postgres -tAc "SELECT 1 FROM pg_database WHERE datname = 'app'" |
    grep -q 1 || fail "could not create the app database"
  database_url="postgres://postgres@$name-db:5432/app"

  step "bin/migrate in a one-off container"
  output="$(docker run --rm --network "$name-net" -e DATABASE_URL="$database_url" \
    -e SECRET_KEY_BASE="$key" "$image" bin/migrate)"
  echo "$output"
  grep -q <<<"$output" "Done. 2 migration(s) applied" || fail "bin/migrate did not apply the migrations"
  output="$(docker run --rm --network "$name-net" -e DATABASE_URL="$database_url" \
    -e SECRET_KEY_BASE="$key" "$image" bin/migrate)"
  grep -q <<<"$output" "Done. 0 migration(s) applied" || fail "a second bin/migrate applied migrations"

  step "Running the app container"
  docker run -d --name "$name-app" --network "$name-net" -p "$port:4000" \
    -e DATABASE_URL="$database_url" -e SECRET_KEY_BASE="$key" "$image" > /dev/null
  wait_for_app
  smoke_test
fi

step "Production configuration: no SECRET_KEY_BASE, no start"
if docker run --rm "$image" > "$work/refusal.log" 2>&1; then
  fail "the container started without SECRET_KEY_BASE"
fi
grep -q "SECRET_KEY_BASE is not set" "$work/refusal.log" || {
  cat "$work/refusal.log" >&2
  fail "the container did not say why it refused to start"
}
echo "ok  refuses to start without SECRET_KEY_BASE"

step "OK (docker, $db)"
