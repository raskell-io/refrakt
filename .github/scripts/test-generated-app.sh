#!/usr/bin/env bash
#
# Generate a Refrakt app with the in-repo CLI and check that it works.
#
#   1. `refrakt_cli new app [--db ...]`, run from packages/refrakt_cli
#   2. point the app at the in-repo library and CLI (path dependencies),
#      so the check covers HEAD rather than whatever is on Hex
#   3. `gen resource posts ...`, `gen page about`, and `gen auth` when the
#      app has a database, all run through the app's own dev-dependency
#   4. `gleam build --warnings-as-errors`, `gleam test`, `gleam format --check`
#   5. with a database: `refrakt_cli migrate`, boot the app and smoke-test
#      /posts and the register/login flow with curl
#
# Usage:
#   .github/scripts/test-generated-app.sh <none|sqlite|postgres> [work-dir]
#
# Locally, run it through mise so gleam/erlang/rebar3 are on PATH:
#   mise exec -- .github/scripts/test-generated-app.sh sqlite
#
# Environment:
#   SKIP_RUNTIME=1  stop after build/test/format (no migrate, boot or curl)
#   PORT            port the app listens on while smoke-testing (default 4000)
#
# The postgres variant expects a server on localhost:5432 that accepts the
# connection URL in the generated src/app/data/repo.gleam
# (postgres://postgres@localhost:5432/app_dev) and creates the app_dev
# database itself, using psql when the database is missing.

set -euo pipefail

db="${1:-}"
case "$db" in
  none) new_flags=() ;;
  sqlite | postgres) new_flags=(--db "$db") ;;
  *)
    echo "usage: $0 <none|sqlite|postgres> [work-dir]" >&2
    exit 2
    ;;
esac

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
work="${2:-$(mktemp -d "${TMPDIR:-/tmp}/refrakt-generated.XXXXXX")}"
mkdir -p "$work"
work="$(cd "$work" && pwd)"
app_dir="$work/app"
port="${PORT:-4000}"
base_url="http://localhost:$port"

step() { printf '\n==> %s\n' "$*"; }
fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

# Hex occasionally rate-limits or times out; retry downloads a few times.
deps_download() {
  local attempt
  for attempt in 1 2 3 4; do
    if gleam deps download; then return 0; fi
    echo "gleam deps download failed (attempt $attempt), retrying..." >&2
    sleep $((attempt * 10))
  done
  return 1
}

cli() { gleam run --no-print-progress -m refrakt_cli -- "$@"; }

rm -rf "$app_dir"

step "Generating app (db: $db) in $app_dir"
(
  cd "$root/packages/refrakt_cli"
  deps_download
  cli new "$app_dir" "${new_flags[@]+"${new_flags[@]}"}"
)

step "Pointing refrakt and refrakt_cli at the in-repo packages"
cd "$app_dir"
sed -i.bak \
  -e "s|^refrakt = .*|refrakt = { path = \"$root/packages/refrakt\" }|" \
  -e "s|^refrakt_cli = .*|refrakt_cli = { path = \"$root/packages/refrakt_cli\" }|" \
  gleam.toml
rm gleam.toml.bak
grep -q "^refrakt = { path = " gleam.toml || fail "gleam.toml has no refrakt dependency"
grep -q "^refrakt_cli = { path = " gleam.toml || fail "gleam.toml has no refrakt_cli dev-dependency"
cat gleam.toml
deps_download

step "Running generators"
if [ "$db" = none ]; then
  # Resources and auth need a database; the CLI must refuse cleanly.
  resource_output="$(cli gen resource posts title:string body:text published:bool)"
  echo "$resource_output"
  echo "$resource_output" | grep -q "No database configured" ||
    fail "gen resource without a database did not refuse"
  [ ! -e src/app/web/post_handler.gleam ] ||
    fail "gen resource without a database wrote files"
else
  cli gen resource posts title:string body:text published:bool
fi
cli gen page about
if [ "$db" != none ]; then
  cli gen auth
  # gen auth adds argus to gleam.toml
  deps_download
fi
cli routes

step "Build, test, format"
gleam build --warnings-as-errors
gleam test
gleam format --check src test

if [ "$db" = none ] || [ "${SKIP_RUNTIME:-}" = 1 ]; then
  step "OK ($db, runtime checks skipped)"
  exit 0
fi

if [ "$db" = postgres ]; then
  step "Creating the app_dev database if needed"
  if command -v psql > /dev/null; then
    psql "postgres://postgres@localhost:5432/postgres" -tAc \
      "SELECT 1 FROM pg_database WHERE datname = 'app_dev'" | grep -q 1 ||
      psql "postgres://postgres@localhost:5432/postgres" -c "CREATE DATABASE app_dev"
  else
    echo "psql not found; assuming app_dev already exists"
  fi
fi

step "Running migrations"
migrate_output="$(cli migrate)"
echo "$migrate_output"
echo "$migrate_output" | grep -q "migration(s) applied" || fail "migrate did not apply migrations"

step "Booting the app on port $port"
gleam export erlang-shipment > /dev/null
log="$work/server.log"
PORT="$port" ./build/erlang-shipment/entrypoint.sh run > "$log" 2>&1 &
server_pid=$!
cleanup() {
  kill "$server_pid" 2> /dev/null || true
  wait "$server_pid" 2> /dev/null || true
}
trap cleanup EXIT

for _ in $(seq 1 60); do
  if curl -fs -o /dev/null "$base_url/"; then break; fi
  if ! kill -0 "$server_pid" 2> /dev/null; then
    cat "$log"
    fail "server exited during startup"
  fi
  sleep 1
done
curl -fsS -o /dev/null "$base_url/" || {
  cat "$log"
  fail "server did not come up on $base_url"
}

# status <method> <path> [curl args...] -> prints the HTTP status code
status() {
  local method="$1" path="$2"
  shift 2
  curl -sS -o "$work/body.html" -w '%{http_code}' -X "$method" "$@" "$base_url$path"
}

expect() {
  local want="$1" got="$2" what="$3"
  if [ "$got" != "$want" ]; then
    echo "--- response body ---" >&2
    cat "$work/body.html" >&2 || true
    echo "--- server log ---" >&2
    cat "$log" >&2
    fail "$what: expected HTTP $want, got $got"
  fi
  echo "ok  $what -> $got"
}

step "Smoke-testing"
expect 200 "$(status GET /)" "GET /"
expect 200 "$(status GET /about)" "GET /about"
expect 200 "$(status GET /posts)" "GET /posts"
expect 200 "$(status GET /posts/new)" "GET /posts/new"
expect 303 "$(status POST /posts \
  --data-urlencode "title=Hello from CI" \
  --data-urlencode "body=Generated and booted" \
  --data-urlencode "published=on")" "POST /posts"
expect 200 "$(status GET /posts)" "GET /posts after create"
grep -q "Hello from CI" "$work/body.html" || fail "created post missing from /posts"
expect 422 "$(status POST /posts --data-urlencode "title=" --data-urlencode "body=")" \
  "POST /posts with invalid form"

email="ci-$$@example.com"
expect 200 "$(status GET /register)" "GET /register"
expect 303 "$(status POST /register -D "$work/register.headers" \
  --data-urlencode "email=$email" \
  --data-urlencode "password=correct horse battery staple" \
  --data-urlencode "password_confirmation=correct horse battery staple")" \
  "POST /register"
grep -qi "^set-cookie: _user_id=" "$work/register.headers" ||
  fail "register did not set the session cookie"
expect 422 "$(status POST /register \
  --data-urlencode "email=$email" \
  --data-urlencode "password=correct horse battery staple" \
  --data-urlencode "password_confirmation=correct horse battery staple")" \
  "POST /register with a taken email"
expect 200 "$(status GET /login)" "GET /login"
expect 303 "$(status POST /login -D "$work/login.headers" \
  --data-urlencode "email=$email" \
  --data-urlencode "password=correct horse battery staple")" "POST /login"
grep -qi "^set-cookie: _user_id=" "$work/login.headers" ||
  fail "login did not set the session cookie"
expect 422 "$(status POST /login \
  --data-urlencode "email=$email" \
  --data-urlencode "password=wrong password")" "POST /login with a wrong password"

step "OK ($db)"
