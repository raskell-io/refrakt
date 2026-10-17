#!/usr/bin/env bash
#
# Generate a Refrakt app with the in-repo CLI and check that it works.
#
#   1. `refrakt_cli new app [--db ...]`, run from packages/refrakt_cli
#   2. point the app at the in-repo library and CLI (path dependencies),
#      so the check covers HEAD rather than whatever is on Hex
#   3. `gen resource posts ...`, `gen resource memos ... --api`, resources
#      with optional(T) fields and a `--belongs-to posts` child, `gen page
#      about`, and `gen auth` when the app has a database, all run through
#      the app's own dev-dependency
#   4. `gleam build --warnings-as-errors`, `gleam test`, `gleam format --check`.
#      With a database, `gleam test` includes the DB-backed tests that go
#      through test/app/support/test_db.gleam (create/show/update/delete,
#      pagination, register/login)
#   5. with a database: `refrakt_cli migrate` (including a hand-written
#      multi-statement migration and a failing one that must roll back),
#      check that APP_ENV=prod refuses a missing, development or short
#      SECRET_KEY_BASE, boot the app and smoke-test /posts, CSRF
#      rejection, the /api/memos JSON API, the register/login/logout
#      flow, pagination of /posts and /api/memos, optional fields and
#      relations with curl
#
# Usage:
#   .github/scripts/test-generated-app.sh <none|sqlite|postgres> [work-dir]
#
# Locally, run it through mise so gleam/erlang/rebar3 are on PATH:
#   mise exec -- .github/scripts/test-generated-app.sh sqlite
#
# Environment:
#   SKIP_RUNTIME=1  stop after build/test/format (no migrate, boot or curl).
#                   For postgres without a server on localhost:5432 it
#                   also skips `gleam test`, whose DB-backed tests need one
#   PORT            port the app listens on while smoke-testing (default 4000)
#
# The postgres variant expects a server on localhost:5432 that accepts the
# connection URLs in the generated src/app/data/repo.gleam
# (postgres://postgres@localhost:5432/app_dev) and
# test/app/support/test_db.gleam (postgres://postgres@localhost:5432/app_test),
# and creates the app_dev and app_test databases itself, using psql when
# they are missing.

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

# Run gleam, retrying when Hex rejects or fails the dependency resolution.
# Projects with path dependencies resolve versions on most commands, so the
# unauthenticated Hex API rate limit can hit any of them. Resolution happens
# before anything runs, so retrying never repeats a generator.
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

deps_download() { gleam_hex deps download; }

cli() { gleam_hex run --no-print-progress -m refrakt_cli -- "$@"; }

# -----------------------------------------------------------------------------
# Migration checks (#17): multi-statement files and one transaction per
# migration. Both functions run inside the app directory.
#
# add_multi_statement_migration writes a hand-written migration with several
# statements, including semicolons inside a string literal and a comment, and
# on Postgres a DO $$ ... $$ block and a dollar-quoted function body. The
# regular "Running migrations" step must apply it.
#
# check_migration_atomicity then adds a migration that creates a table,
# inserts a row and fails on its last statement, and checks that
# `refrakt migrate` reports the file and the database error. It rewrites
# the same file into a working one that creates the same table again and
# asserts, through CHECK constraints (no database client needed), that the
# failed run left no rows and that the multi-statement migration ran in
# full. The rewritten file applies only if the failed run was rolled back
# and never recorded in _migrations. A last migrate must apply nothing.
# -----------------------------------------------------------------------------

new_migration_file() {
  cli gen migration "$1" > /dev/null
  ls src/app/data/migrations/*_"$1".sql
}

add_multi_statement_migration() {
  local file
  file="$(new_migration_file create_tags)"
  if [ "$db" = postgres ]; then
    cat > "$file" << 'SQL'
-- Several statements in one file (refrakt#17)
CREATE TABLE tags (
  id SERIAL PRIMARY KEY,
  name TEXT NOT NULL
);
CREATE INDEX tags_name_index ON tags (name);
/* A comment; with a semicolon */
INSERT INTO tags (name) VALUES ('semi;colon'), ('it''s; quoted');
DO $$
BEGIN
  INSERT INTO tags (name) VALUES ('from a DO; block');
END
$$;
CREATE FUNCTION tag_count() RETURNS bigint AS $body$
  SELECT count(*) FROM tags;
$body$ LANGUAGE sql;
SQL
  else
    cat > "$file" << 'SQL'
-- Several statements in one file (refrakt#17)
CREATE TABLE tags (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL
);
CREATE INDEX tags_name_index ON tags (name);
/* A comment; with a semicolon */
INSERT INTO tags (name) VALUES ('semi;colon'), ('it''s; quoted');
SQL
  fi
  echo "Added $file"
}

check_migration_atomicity() {
  local file name output expected_tags
  file="$(new_migration_file add_broken_partial)"
  name="$(basename "$file")"

  cat > "$file" << 'SQL'
CREATE TABLE broken_partial (id INTEGER PRIMARY KEY);
INSERT INTO tags (name) VALUES ('from the failing migration');
INSERT INTO no_such_table (id) VALUES (1);
SQL
  output="$(cli migrate)"
  echo "$output"
  echo "$output" | grep -q "Error: Migration $name failed and was rolled back" ||
    fail "migrate did not report the failing migration $name"
  echo "$output" | grep -q "no_such_table" ||
    fail "migrate did not show the database error for $name"

  # 2 rows from the multi-statement migration, plus 1 from the DO block
  expected_tags=2
  if [ "$db" = postgres ]; then expected_tags=3; fi
  cat > "$file" << SQL
CREATE TABLE broken_partial (id INTEGER PRIMARY KEY);
CREATE TABLE migration_checks (
  what TEXT NOT NULL,
  ok INTEGER NOT NULL CHECK (ok = 1)
);
INSERT INTO migration_checks (what, ok)
  SELECT 'failed run left no rows', CASE WHEN count(*) = 0 THEN 1 ELSE 0 END
  FROM tags WHERE name = 'from the failing migration';
INSERT INTO migration_checks (what, ok)
  SELECT 'multi-statement rows', CASE WHEN count(*) = $expected_tags THEN 1 ELSE 0 END
  FROM tags;
INSERT INTO migration_checks (what, ok)
  SELECT 'semicolon in a string', CASE WHEN count(*) = 1 THEN 1 ELSE 0 END
  FROM tags WHERE name = 'semi;colon';
SQL
  if [ "$db" = postgres ]; then
    cat >> "$file" << SQL
INSERT INTO migration_checks (what, ok)
  SELECT 'dollar-quoted function', CASE WHEN tag_count() = $expected_tags THEN 1 ELSE 0 END;
SQL
  fi
  output="$(cli migrate)"
  echo "$output"
  echo "$output" | grep -q "Done. 1 migration(s) applied" ||
    fail "rewritten $name did not apply: the failed run was not rolled back or was recorded"

  output="$(cli migrate)"
  echo "$output"
  echo "$output" | grep -q "Done. 0 migration(s) applied" ||
    fail "a second migrate applied migrations again"
}

# -----------------------------------------------------------------------------
# optional(T) fields (#35) and --belongs-to relations (#23)
#
# generate_optional_and_relations runs inside the app directory, after
# `gen resource posts`. It generates
#   - products: optional fields of every kind (HTML form)
#   - gadgets: optional fields in an --api resource
#   - comments: `--belongs-to posts`, which patches the post's show page
# and checks that an unknown field type and a missing parent are refused
# without writing files. smoke_test_optional_and_relations exercises them
# against the running app.
# -----------------------------------------------------------------------------

generate_optional_and_relations() {
  local output
  cli gen resource products name:string 'price:optional(float)' \
    'stock:optional(int)' 'note:optional(text)' 'featured:optional(bool)' \
    'released:optional(date)'
  cli gen resource gadgets label:string 'weight:optional(float)' \
    'count:optional(int)' 'active:optional(bool)' 'code:optional(string)' --api
  cli gen resource comments body:text --belongs-to posts
  grep -q "comment_list.render(" src/app/web/post_handler.gleam ||
    fail "gen resource comments --belongs-to posts did not patch the post's show handler"

  output="$(cli gen resource widgets 'size:optional(money)')"
  echo "$output"
  echo "$output" | grep -q "Unknown type" || fail "an unknown field type was not refused"
  [ ! -e src/app/web/widget_handler.gleam ] || fail "an unknown field type wrote files"

  output="$(cli gen resource drafts body:text --belongs-to nopes)"
  echo "$output"
  echo "$output" | grep -q "there is no nopes resource" ||
    fail "--belongs-to a missing resource was not refused"
  [ ! -e src/app/web/draft_handler.gleam ] ||
    fail "--belongs-to a missing resource wrote files"
}

# body_has <text> <what> / body_lacks <text> <what>: check the last response
body_has() {
  grep -qF -- "$1" "$work/body.html" || {
    cat "$work/body.html" >&2
    fail "$2: response lacks $1"
  }
}
body_lacks() {
  if grep -qF -- "$1" "$work/body.html"; then
    cat "$work/body.html" >&2
    fail "$2: response contains $1"
  fi
}

# location -> the Location header of the last request made with
# `-D "$work/headers"`
location() {
  grep -i "^location:" "$work/headers" | tr -d '\r' | sed 's/^[Ll]ocation: *//'
}

smoke_test_optional_and_relations() {
  local product_path post_path post_id comment_path value

  step "Smoke-testing optional fields (/products)"
  expect 303 "$(status POST /products -D "$work/headers" \
    --data-urlencode "name=All blank" --data-urlencode "price=" \
    --data-urlencode "stock=" --data-urlencode "note=" \
    --data-urlencode "featured=" --data-urlencode "released=")" \
    "POST /products with blank optional fields"
  product_path="$(location)"
  [ -n "$product_path" ] || fail "POST /products did not redirect to the product"
  expect 200 "$(status GET "$product_path")" "GET $product_path"
  body_has "All blank" "GET $product_path"
  # price, stock, note, featured and released are NULL: an em dash each
  [ "$(grep -o '<dd>—</dd>' "$work/body.html" | wc -l | tr -d ' ')" = 5 ] || {
    cat "$work/body.html" >&2
    fail "GET $product_path: blank optional fields do not show as —"
  }
  echo "ok  blank optional fields are NULL and show as —"
  expect 200 "$(status GET "$product_path/edit")" "GET $product_path/edit"
  # Lustre sorts attributes and writes an empty value as a bare `value`
  body_has '<input name="price" step="any" type="number" value>' \
    "GET $product_path/edit renders a NULL price as blank"
  body_has '<option selected value>' "GET $product_path/edit selects the blank featured"

  expect 303 "$(status POST /products -D "$work/headers" \
    --data-urlencode "name=All set" --data-urlencode "price=4" \
    --data-urlencode "stock=7" --data-urlencode "note=Handle with care" \
    --data-urlencode "featured=true" --data-urlencode "released=2026-10-17")" \
    "POST /products with optional values"
  product_path="$(location)"
  expect 200 "$(status GET "$product_path")" "GET $product_path"
  for value in "<dd>4.0</dd>" "<dd>7</dd>" "<dd>Handle with care</dd>" \
    "<dd>Yes</dd>" "<dd>2026-10-17</dd>"; do
    body_has "$value" "GET $product_path"
  done
  echo "ok  optional values round-trip"

  expect 422 "$(status POST /products --data-urlencode "name=Bad price" \
    --data-urlencode "price=cheap")" "POST /products with a price that is not a number"
  body_has "Price must be a number" "POST /products with a bad price"
  expect 422 "$(status POST /products --data-urlencode "name=Bad stock" \
    --data-urlencode "stock=1.5")" "POST /products with a stock that is not a whole number"
  expect 422 "$(status POST /products --data-urlencode "name=Bad flag" \
    --data-urlencode "featured=maybe")" "POST /products with a featured that is not yes/no"

  expect 303 "$(status POST "$product_path?_method=PUT" \
    --data-urlencode "name=All set" --data-urlencode "price=" \
    --data-urlencode "stock=7" --data-urlencode "featured=false")" \
    "PUT $product_path clearing the price"
  expect 200 "$(status GET "$product_path")" "GET $product_path after clearing the price"
  body_has "<dd>No</dd>" "GET $product_path after update"
  body_lacks "<dd>4.0</dd>" "GET $product_path after clearing the price"

  step "Smoke-testing optional fields in the JSON API (/api/gadgets)"
  expect 201 "$(api POST /api/gadgets \
    '{"label":"Nulls","weight":null,"count":null,"active":null,"code":null}')" \
    "POST /api/gadgets with null optional fields"
  for value in '"weight":null' '"count":null' '"active":null' '"code":null'; do
    api_body_has "$value" "POST /api/gadgets with nulls"
  done
  expect 201 "$(api POST /api/gadgets '{"label":"Missing"}')" \
    "POST /api/gadgets with optional fields left out"
  api_body_has '"weight":null' "POST /api/gadgets with missing keys"
  api_body_has '"count":null' "POST /api/gadgets with missing keys"
  expect 201 "$(api POST /api/gadgets \
    '{"label":"Values","weight":2,"count":3,"active":false,"code":"G-1"}')" \
    "POST /api/gadgets with optional values"
  for value in '"weight":2.0' '"count":3' '"active":false' '"code":"G-1"'; do
    api_body_has "$value" "POST /api/gadgets with values"
  done
  expect 400 "$(api POST /api/gadgets '{"label":"Bad","count":"many"}')" \
    "POST /api/gadgets with a count that is not a number"
  # The index answers the pagination envelope, with null for None
  expect 200 "$(api GET /api/gadgets)" "GET /api/gadgets"
  for value in '"data":[' '"total":3' '"label":"Nulls","weight":null'; do
    api_body_has "$value" "GET /api/gadgets"
  done

  step "Smoke-testing --belongs-to (/posts and /comments)"
  expect 303 "$(status POST /posts -D "$work/headers" \
    --data-urlencode "title=Parent post" --data-urlencode "body=Has comments")" \
    "POST /posts (parent)"
  post_path="$(location)"
  post_id="${post_path##*/}"
  [ -n "$post_id" ] || fail "POST /posts did not redirect to the post"
  expect 200 "$(status GET "/comments/new?post_id=$post_id")" \
    "GET /comments/new?post_id=$post_id"
  body_has "Parent post" "GET /comments/new (the select offers the post)"
  body_has "<option selected value=\"$post_id\">" \
    "GET /comments/new?post_id=$post_id preselects the post"

  expect 303 "$(status POST /comments -D "$work/headers" \
    --data-urlencode "body=First comment" --data-urlencode "post_id=$post_id")" \
    "POST /comments for $post_path"
  comment_path="$(location)"
  expect 200 "$(status GET "$comment_path")" "GET $comment_path"
  body_has "href=\"$post_path\"" "GET $comment_path links to its post"
  expect 422 "$(status POST /comments --data-urlencode "body=Lost" \
    --data-urlencode "post_id=999999")" "POST /comments for a missing post"
  body_has "Post does not exist" "POST /comments for a missing post"
  expect 422 "$(status POST /comments --data-urlencode "body=No post")" \
    "POST /comments without a post"
  expect 422 "$(status POST "$comment_path?_method=PUT" --data-urlencode "body=Moved" \
    --data-urlencode "post_id=999999")" "PUT $comment_path to a missing post"

  expect 200 "$(status GET "$post_path")" "GET $post_path"
  body_has "First comment" "GET $post_path lists its comments"
  body_has "href=\"$comment_path\"" "GET $post_path links to the comment"
  body_has "/comments/new?post_id=$post_id" "GET $post_path links to a new comment"

  # ON DELETE CASCADE: deleting the post deletes its comments
  expect 303 "$(status POST "$post_path?_method=DELETE")" "DELETE $post_path"
  expect 404 "$(status GET "$comment_path")" "GET $comment_path after deleting its post"
  expect 200 "$(status GET /comments)" "GET /comments after deleting the post"
  body_lacks "First comment" "GET /comments after deleting the post"
  echo "ok  deleting a post deletes its comments"
}

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
  # Field mixes that change the generated imports (warnings fail the build)
  cli gen resource notes body:text
  cli gen resource tasks title:string done:bool priority:int ratio:float
  # JSON API resources (--api); see smoke_test_json_api below
  cli gen resource memos title:string body:text pinned:bool rating:int --api
  cli gen resource readings value:float count:int --api
  generate_optional_and_relations
fi
cli gen page about
if [ "$db" != none ]; then
  cli gen auth
  # gen auth adds argus to gleam.toml
  deps_download
  add_multi_statement_migration
fi
cli routes

# create_database <name>: create a Postgres database unless it exists
create_database() {
  if command -v psql > /dev/null; then
    psql "postgres://postgres@localhost:5432/postgres" -tAc \
      "SELECT 1 FROM pg_database WHERE datname = '$1'" | grep -q 1 ||
      psql "postgres://postgres@localhost:5432/postgres" -c "CREATE DATABASE $1"
  else
    echo "psql not found; assuming $1 already exists"
  fi
}

postgres_reachable() {
  (exec 3<> /dev/tcp/localhost/5432) 2> /dev/null
}

# The generated tests that use test/app/support/test_db.gleam need the
# database: on SQLite each test gets its own in-memory one, on Postgres
# they run in rolled-back transactions on app_test.
run_tests=1
if [ "$db" = postgres ]; then
  if postgres_reachable; then
    step "Creating the app_test database for the DB-backed tests"
    create_database app_test
  elif [ "${SKIP_RUNTIME:-}" = 1 ]; then
    run_tests=0
  else
    fail "no Postgres server on localhost:5432 for the DB-backed tests"
  fi
fi

step "Build, test, format"
gleam_hex build --warnings-as-errors
if [ "$run_tests" = 1 ]; then
  if [ "$db" != none ]; then
    # gleam test runs every *_test function, so these run below
    for test_file in post_handler_test memo_handler_test auth_handler_test; do
      grep -q "use ctx <- test_db.with_context()" "test/app/web/$test_file.gleam" ||
        fail "test/app/web/$test_file.gleam has no tests against the test database"
    done
  fi
  gleam_hex test
else
  echo "skipping gleam test: the DB-backed tests need Postgres on localhost:5432"
  echo "(gleam build above compiled them; CI runs them against its Postgres service)"
fi
gleam format --check src test

if [ "$db" = none ] || [ "${SKIP_RUNTIME:-}" = 1 ]; then
  step "OK ($db, runtime checks skipped)"
  exit 0
fi

if [ "$db" = postgres ]; then
  step "Creating the app_dev database if needed"
  create_database app_dev
fi

step "Running migrations"
migrate_output="$(cli migrate)"
echo "$migrate_output"
echo "$migrate_output" | grep -q "migration(s) applied" || fail "migrate did not apply migrations"
echo "$migrate_output" | grep -q "_create_tags.sql ✓" ||
  fail "migrate did not apply the multi-statement migration"

step "Checking that a failing migration is rolled back"
check_migration_atomicity

gleam_hex export erlang-shipment > /dev/null

# expect_refusal <message> <env args...>: with these environment changes the
# app must exit with a non-zero status and print the message.
expect_refusal() {
  local message="$1" output="$work/refusal.log" pid
  shift
  env "$@" PORT="$port" ./build/erlang-shipment/entrypoint.sh run > "$output" 2>&1 &
  pid=$!
  for _ in $(seq 1 30); do
    kill -0 "$pid" 2> /dev/null || break
    sleep 1
  done
  if kill -0 "$pid" 2> /dev/null; then
    kill "$pid" 2> /dev/null || true
    wait "$pid" 2> /dev/null || true
    cat "$output" >&2
    fail "app started with $*"
  fi
  if wait "$pid"; then
    cat "$output" >&2
    fail "app exited with status 0 with $*"
  fi
  grep -q "$message" "$output" || {
    cat "$output" >&2
    fail "app refused to start with $* but did not say \"$message\""
  }
  echo "ok  refuses to start with $*"
}

step "Checking production configuration"
dev_key="$(grep -o '"dev-secret-key-base[^"]*"' src/app/config.gleam | tr -d '"')"
[ -n "$dev_key" ] || fail "no development secret key in src/app/config.gleam"
expect_refusal "SECRET_KEY_BASE is not set" -u SECRET_KEY_BASE APP_ENV=prod
expect_refusal "development key" APP_ENV=prod SECRET_KEY_BASE="$dev_key"
expect_refusal "at least 64 bytes" APP_ENV=prod SECRET_KEY_BASE=too-short

step "Booting the app on port $port"
if curl -s -o /dev/null "$base_url/"; then
  fail "something is already listening on port $port; set PORT to a free port"
fi
log="$work/server.log"
# APP_ENV is left unset on purpose: the app must warn about it.
env -u APP_ENV -u SECRET_KEY_BASE PORT="$port" \
  ./build/erlang-shipment/entrypoint.sh run > "$log" 2>&1 &
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

grep -q "APP_ENV is not set" "$log" || {
  cat "$log"
  fail "no warning about the unset APP_ENV"
}
echo "ok  warns that APP_ENV is not set"

# status <method> <path> [curl args...] -> prints the HTTP status code.
# Requests carry the Origin header a browser sends with the app's own forms.
status() {
  local method="$1" path="$2"
  shift 2
  curl -sS -o "$work/body.html" -w '%{http_code}' -X "$method" \
    -H "Origin: $base_url" "$@" "$base_url$path"
}

# cross_site <method> <path> [curl args...] -> HTTP status of the request as
# sent by a page on another site
cross_site() {
  local method="$1" path="$2"
  shift 2
  curl -sS -o "$work/body.html" -w '%{http_code}' -X "$method" \
    -H "Origin: https://evil.example" "$@" "$base_url$path"
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

# -----------------------------------------------------------------------------
# JSON API smoke test: the `gen resource memos ... --api` resource
# -----------------------------------------------------------------------------

# api <method> <path> [json-body] -> prints the HTTP status code. The body
# lands in $work/body.html (where `expect` looks on failure), the headers in
# $work/api.headers.
api() {
  local method="$1" path="$2" body="${3-}"
  local args=(-sS -o "$work/body.html" -D "$work/api.headers" -w '%{http_code}' -X "$method")
  if [ -n "$body" ]; then
    args+=(-H 'content-type: application/json' --data "$body")
  fi
  curl "${args[@]}" "$base_url$path"
}

# api_body_has <text> <what>: fail unless the last API response contains text
api_body_has() {
  grep -qF -- "$1" "$work/body.html" || {
    cat "$work/body.html" >&2
    fail "$2: response body lacks $1"
  }
}

smoke_test_json_api() {
  step "Smoke-testing the JSON API (/api/memos)"
  local memo_id memo_path

  expect 201 "$(api POST /api/memos \
    '{"title":"From CI","body":"Sent as JSON","pinned":true,"rating":4}')" \
    "POST /api/memos"
  api_body_has '"title":"From CI"' "POST /api/memos"
  memo_id="$(grep -o '"id":[0-9]*' "$work/body.html" | head -n 1 | cut -d: -f2)"
  [ -n "$memo_id" ] || fail "POST /api/memos returned no id"
  memo_path="/api/memos/$memo_id"
  grep -qi "^location: $memo_path" "$work/api.headers" ||
    fail "POST /api/memos did not answer with Location: $memo_path"

  expect 422 "$(api POST /api/memos '{"title":"","body":""}')" \
    "POST /api/memos with blank fields"
  api_body_has '"errors":{' "POST /api/memos with blank fields"
  api_body_has '"title":"Title is required"' "POST /api/memos with blank fields"
  expect 400 "$(api POST /api/memos '{not json')" "POST /api/memos with malformed JSON"
  expect 400 "$(api POST /api/memos '{"title":42}')" "POST /api/memos with a wrong field type"
  api_body_has '"error":"invalid request body"' "POST /api/memos with a wrong field type"

  expect 200 "$(api GET "$memo_path")" "GET $memo_path"
  api_body_has '"title":"From CI"' "GET $memo_path"
  expect 200 "$(api PUT "$memo_path" \
    '{"title":"Updated via JSON","body":"Sent as JSON","pinned":false,"rating":5}')" \
    "PUT $memo_path"
  api_body_has '"title":"Updated via JSON"' "PUT $memo_path"
  api_body_has '"rating":5' "PUT $memo_path"
  expect 422 "$(api PUT "$memo_path" '{"title":" "}')" "PUT $memo_path with a blank title"
  expect 404 "$(api PUT /api/memos/999999 \
    '{"title":"Nobody","body":"Home","pinned":false,"rating":1}')" \
    "PUT /api/memos/999999 (missing id)"
  api_body_has '"error":"not found"' "PUT /api/memos/999999 (missing id)"

  expect 200 "$(api GET /api/memos)" "GET /api/memos"
  api_body_has '"title":"Updated via JSON"' "GET /api/memos"

  expect 204 "$(api DELETE "$memo_path")" "DELETE $memo_path"
  expect 404 "$(api GET "$memo_path")" "GET $memo_path after delete"
  expect 404 "$(api DELETE "$memo_path")" "DELETE $memo_path again"
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
expect 403 "$(cross_site POST /posts \
  --data-urlencode "title=Forged" \
  --data-urlencode "body=Sent from another site")" "cross-site POST /posts"
expect 403 "$(curl -sS -o "$work/body.html" -w '%{http_code}' -X POST \
  -H "Sec-Fetch-Site: cross-site" \
  --data-urlencode "title=Forged" \
  --data-urlencode "body=Sent from another site" \
  "$base_url/posts")" "POST /posts with Sec-Fetch-Site: cross-site"
expect 200 "$(status GET /posts)" "GET /posts after forged creates"
if grep -q "Forged" "$work/body.html"; then fail "a cross-site POST created a post"; fi
expect 422 "$(status POST /posts --data-urlencode "title=" --data-urlencode "body=")" \
  "POST /posts with invalid form"
expect 200 "$(status GET /posts)" "GET /posts"
post_path="$(grep -o 'href="/posts/[0-9]*"' "$work/body.html" | head -n 1 | sed 's/href="\(.*\)"/\1/')"
[ -n "$post_path" ] || fail "no link to the created post on /posts"
expect 200 "$(status GET "$post_path")" "GET $post_path"
# wisp.method_override reads _method from the query string of a POST
grep -q "$post_path?_method=DELETE" "$work/body.html" ||
  fail "show page has no delete form posting to ?_method=DELETE"
expect 403 "$(cross_site POST "$post_path?_method=DELETE")" "cross-site DELETE $post_path"
expect 200 "$(status GET "$post_path")" "GET $post_path after forged delete"
expect 200 "$(status GET "$post_path/edit")" "GET $post_path/edit"
grep -q "$post_path?_method=PUT" "$work/body.html" ||
  fail "edit form does not post to ?_method=PUT"
expect 303 "$(status POST "$post_path?_method=PUT" \
  --data-urlencode "title=Updated in CI" \
  --data-urlencode "body=Still booted")" "PUT $post_path (method override)"
expect 200 "$(status GET "$post_path")" "GET $post_path after update"
grep -q "Updated in CI" "$work/body.html" || fail "update did not change the post"
expect 303 "$(status POST "$post_path?_method=DELETE")" "DELETE $post_path (method override)"
expect 404 "$(status GET "$post_path")" "GET $post_path after delete"

email="ci-$$@example.com"
expect 200 "$(status GET /register)" "GET /register"
expect 303 "$(status POST /register -D "$work/register.headers" \
  --data-urlencode "email=$email" \
  --data-urlencode "password=correct horse battery staple" \
  --data-urlencode "password_confirmation=correct horse battery staple")" \
  "POST /register"
session_cookie="$(grep -i "^set-cookie: _session=" "$work/register.headers" || true)"
[ -n "$session_cookie" ] || fail "register did not set the session cookie"
for attribute in HttpOnly SameSite=Lax Max-Age=604800; do
  echo "$session_cookie" | grep -q "$attribute" ||
    fail "session cookie lacks $attribute: $session_cookie"
done
echo "ok  session cookie: $session_cookie"
expect 422 "$(status POST /register \
  --data-urlencode "email=$email" \
  --data-urlencode "password=correct horse battery staple" \
  --data-urlencode "password_confirmation=correct horse battery staple")" \
  "POST /register with a taken email"
expect 200 "$(status GET /login)" "GET /login"
expect 303 "$(status POST /login -D "$work/login.headers" \
  --data-urlencode "email=$email" \
  --data-urlencode "password=correct horse battery staple")" "POST /login"
grep -qi "^set-cookie: _session=" "$work/login.headers" ||
  fail "login did not set the session cookie"
expect 422 "$(status POST /login \
  --data-urlencode "email=$email" \
  --data-urlencode "password=wrong password")" "POST /login with a wrong password"
expect 422 "$(status POST /login \
  --data-urlencode "email=nobody-$$@example.com" \
  --data-urlencode "password=correct horse battery staple")" "POST /login with an unknown email"
expect 403 "$(cross_site POST /login \
  --data-urlencode "email=$email" \
  --data-urlencode "password=correct horse battery staple")" "cross-site POST /login"
expect 403 "$(cross_site POST /logout)" "cross-site POST /logout"
expect 303 "$(status POST /logout -D "$work/logout.headers")" "POST /logout"
grep -i "^set-cookie: _session=" "$work/logout.headers" | grep -q "Max-Age=0" ||
  fail "logout did not clear the session cookie"
echo "ok  logout clears the session cookie"

smoke_test_json_api
smoke_test_optional_and_relations

# -----------------------------------------------------------------------------
# Pagination (#22): /posts and /api/memos list one page at a time. Runs after
# the smoke tests above, which delete the post and memo they create, so the
# tables hold only the rows created here.
# -----------------------------------------------------------------------------

# count_matches <text>: how often text occurs in the last response body
count_matches() {
  { grep -oF -- "$1" "$work/body.html" || true; } | wc -l | tr -d ' '
}

# body_has and body_lacks are defined with the optional(T) checks above

# expect_count <want> <text> <what>
expect_count() {
  local got
  got="$(count_matches "$2")"
  [ "$got" = "$1" ] || {
    cat "$work/body.html" >&2
    fail "$3: expected $1 x $2, got $got"
  }
  echo "ok  $3: $got x $2"
}

smoke_test_pagination() {
  local per_page api_per_page i page
  per_page="$(grep -o 'pub const per_page = [0-9]*' src/app/web/post_handler.gleam | grep -o '[0-9]*$')"
  api_per_page="$(grep -o 'pub const per_page = [0-9]*' src/app/web/memo_handler.gleam | grep -o '[0-9]*$')"
  [ -n "$per_page" ] || fail "no per_page constant in post_handler.gleam"
  [ -n "$api_per_page" ] || fail "no per_page constant in memo_handler.gleam"

  step "Pagination of /posts ($((per_page + 1)) posts, $per_page per page)"
  expect 200 "$(status GET /posts)" "GET /posts before creating posts"
  expect_count 0 "<li>" "GET /posts before creating posts"
  for i in $(seq 1 $((per_page + 1))); do
    [ "$(status POST /posts --data-urlencode "title=Paged post $i" \
      --data-urlencode "body=Body $i")" = 303 ] || fail "POST /posts (paged post $i)"
  done

  expect 200 "$(status GET /posts)" "GET /posts"
  expect_count "$per_page" "<li>" "GET /posts"
  body_has "Page 1 of 2" "GET /posts"
  body_has 'href="/posts?page=2"' "GET /posts"
  body_has "Paged post $((per_page + 1))<" "GET /posts (newest first)"
  body_lacks 'rel="prev"' "GET /posts"

  expect 200 "$(status GET "/posts?page=2")" "GET /posts?page=2"
  expect_count 1 "<li>" "GET /posts?page=2"
  body_has "Page 2 of 2" "GET /posts?page=2"
  body_has "Paged post 1<" "GET /posts?page=2 (oldest last)"
  body_has 'href="/posts?page=1"' "GET /posts?page=2"
  body_lacks 'rel="next"' "GET /posts?page=2"

  expect 200 "$(status GET "/posts?page=3")" "GET /posts?page=3 (out of range)"
  expect_count 0 "<li>" "GET /posts?page=3"
  body_has 'href="/posts?page=2"' "GET /posts?page=3 (links back to the last page)"
  body_lacks 'rel="next"' "GET /posts?page=3"

  for page in 0 -1 abc; do
    expect 200 "$(status GET "/posts?page=$page")" "GET /posts?page=$page"
    body_has "Page 1 of 2" "GET /posts?page=$page (is page 1)"
  done

  step "Pagination of /api/memos (3 memos, per_page=2)"
  for i in 1 2 3; do
    [ "$(api POST /api/memos \
      "{\"title\":\"Paged memo $i\",\"body\":\"Body\",\"pinned\":false,\"rating\":$i}")" = 201 ] ||
      fail "POST /api/memos (paged memo $i)"
  done

  expect 200 "$(api GET /api/memos)" "GET /api/memos"
  body_has "\"page\":1,\"per_page\":$api_per_page,\"total\":3,\"total_pages\":1" "GET /api/memos"
  expect_count 3 '"title":"Paged memo' "GET /api/memos"

  expect 200 "$(api GET "/api/memos?per_page=2")" "GET /api/memos?per_page=2"
  body_has '"page":1,"per_page":2,"total":3,"total_pages":2' "GET /api/memos?per_page=2"
  expect_count 2 '"title":"Paged memo' "GET /api/memos?per_page=2"
  body_has '"title":"Paged memo 3"' "GET /api/memos?per_page=2 (newest first)"

  expect 200 "$(api GET "/api/memos?page=2&per_page=2")" "GET /api/memos?page=2&per_page=2"
  body_has '"page":2,"per_page":2,"total":3,"total_pages":2' "GET /api/memos?page=2&per_page=2"
  expect_count 1 '"title":"Paged memo' "GET /api/memos?page=2&per_page=2"
  body_has '"title":"Paged memo 1"' "GET /api/memos?page=2&per_page=2"

  expect 200 "$(api GET "/api/memos?page=3&per_page=2")" "GET /api/memos?page=3&per_page=2 (out of range)"
  body_has '"data":[]' "GET /api/memos?page=3&per_page=2"
  body_has '"page":3' "GET /api/memos?page=3&per_page=2"

  expect 200 "$(api GET "/api/memos?page=-4&per_page=1000")" "GET /api/memos?page=-4&per_page=1000"
  body_has "\"page\":1,\"per_page\":100,\"total\":3" "GET /api/memos?page=-4&per_page=1000 (clamped)"
}

smoke_test_pagination

step "OK ($db)"
