import gleam/list
import gleam/string
import gleeunit/should
import refrakt/migrate
import simplifile

// -- split_statements ---------------------------------------------------------

pub fn split_single_statement_without_semicolon_test() {
  migrate.split_statements("CREATE TABLE a (id INT)")
  |> should.equal(["CREATE TABLE a (id INT)"])
}

pub fn split_multiple_statements_test() {
  "CREATE TABLE posts (id SERIAL PRIMARY KEY, title TEXT);
CREATE INDEX posts_title_index ON posts (title);
"
  |> migrate.split_statements
  |> should.equal([
    "CREATE TABLE posts (id SERIAL PRIMARY KEY, title TEXT)",
    "CREATE INDEX posts_title_index ON posts (title)",
  ])
}

pub fn split_drops_empty_statements_test() {
  "  ;\n;SELECT 1;;  ;\n"
  |> migrate.split_statements
  |> should.equal(["SELECT 1"])
}

pub fn split_empty_script_test() {
  migrate.split_statements("")
  |> should.equal([])
  migrate.split_statements("  \n\t ")
  |> should.equal([])
}

pub fn split_ignores_semicolon_in_string_test() {
  "INSERT INTO notes (body) VALUES ('a; b');SELECT 2"
  |> migrate.split_statements
  |> should.equal(["INSERT INTO notes (body) VALUES ('a; b')", "SELECT 2"])
}

pub fn split_handles_doubled_quotes_in_string_test() {
  "INSERT INTO notes (body) VALUES ('it''s; fine'); SELECT 2"
  |> migrate.split_statements
  |> should.equal([
    "INSERT INTO notes (body) VALUES ('it''s; fine')",
    "SELECT 2",
  ])
}

pub fn split_handles_backslash_escapes_in_e_string_test() {
  "SELECT E'it\\'s; fine'; SELECT 2"
  |> migrate.split_statements
  |> should.equal(["SELECT E'it\\'s; fine'", "SELECT 2"])
}

pub fn split_backslash_is_literal_in_plain_string_test() {
  // Standard strings do not treat \ as an escape: 'C:\' ends at the quote
  "SELECT 'C:\\'; SELECT 2"
  |> migrate.split_statements
  |> should.equal(["SELECT 'C:\\'", "SELECT 2"])
}

pub fn split_ignores_semicolon_in_quoted_identifier_test() {
  "CREATE TABLE \"odd;name\" (id INT); SELECT 2"
  |> migrate.split_statements
  |> should.equal(["CREATE TABLE \"odd;name\" (id INT)", "SELECT 2"])
}

pub fn split_ignores_semicolon_in_line_comment_test() {
  "SELECT 1; -- a comment; with semicolons\nSELECT 2;"
  |> migrate.split_statements
  |> should.equal(["SELECT 1", "-- a comment; with semicolons\nSELECT 2"])
}

pub fn split_handles_crlf_line_comment_test() {
  "SELECT 1 -- note; here\r\n; SELECT 2"
  |> migrate.split_statements
  |> should.equal(["SELECT 1 -- note; here", "SELECT 2"])
}

pub fn split_ignores_semicolon_in_block_comment_test() {
  "/* setup; part one */ CREATE TABLE a (id INT); SELECT 2"
  |> migrate.split_statements
  |> should.equal(["/* setup; part one */ CREATE TABLE a (id INT)", "SELECT 2"])
}

pub fn split_handles_nested_block_comments_test() {
  "/* outer /* inner; */ still comment; */ SELECT 1; SELECT 2"
  |> migrate.split_statements
  |> should.equal([
    "/* outer /* inner; */ still comment; */ SELECT 1",
    "SELECT 2",
  ])
}

pub fn split_drops_comment_only_statements_test() {
  "SELECT 1;\n-- trailing comment\n/* and another; */\n"
  |> migrate.split_statements
  |> should.equal(["SELECT 1"])
}

pub fn split_ignores_quotes_inside_comments_test() {
  "-- don't split here\nSELECT 1; /* \"unbalanced */ SELECT 2"
  |> migrate.split_statements
  |> should.equal([
    "-- don't split here\nSELECT 1",
    "/* \"unbalanced */ SELECT 2",
  ])
}

pub fn split_keeps_dollar_quoted_body_test() {
  let function =
    "CREATE FUNCTION touch() RETURNS trigger AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql"
  { function <> ";\nSELECT 2;" }
  |> migrate.split_statements
  |> should.equal([function, "SELECT 2"])
}

pub fn split_keeps_tagged_dollar_quoted_body_test() {
  let block =
    "DO $body$
BEGIN
  RAISE NOTICE '$$; not the end';
  PERFORM 1;
END
$body$"
  { block <> "; SELECT 2" }
  |> migrate.split_statements
  |> should.equal([block, "SELECT 2"])
}

pub fn split_nested_dollar_tags_test() {
  let function =
    "CREATE FUNCTION f() RETURNS void AS $outer$
BEGIN
  EXECUTE $inner$ SELECT 1; $inner$;
END;
$outer$ LANGUAGE plpgsql"
  { function <> "; SELECT 2" }
  |> migrate.split_statements
  |> should.equal([function, "SELECT 2"])
}

pub fn split_does_not_treat_parameters_as_dollar_quotes_test() {
  "PREPARE p AS SELECT $1; SELECT 2"
  |> migrate.split_statements
  |> should.equal(["PREPARE p AS SELECT $1", "SELECT 2"])
}

pub fn split_does_not_treat_dollar_in_identifier_as_quote_test() {
  "SELECT a$b$c FROM t; SELECT 2"
  |> migrate.split_statements
  |> should.equal(["SELECT a$b$c FROM t", "SELECT 2"])
}

pub fn split_keeps_begin_atomic_body_test() {
  let function =
    "CREATE FUNCTION add(a integer, b integer) RETURNS integer
LANGUAGE SQL
BEGIN ATOMIC
  SELECT CASE WHEN a IS NULL THEN 0 ELSE a END + b;
  SELECT a + b;
END"
  { function <> ";\nCREATE INDEX i ON t (c);" }
  |> migrate.split_statements
  |> should.equal([function, "CREATE INDEX i ON t (c)"])
}

pub fn split_plain_begin_is_not_a_body_test() {
  "BEGIN; SELECT 1; COMMIT"
  |> migrate.split_statements
  |> should.equal(["BEGIN", "SELECT 1", "COMMIT"])
}

pub fn split_keywords_are_case_insensitive_test() {
  "create function f() returns int language sql begin atomic select 1; end; select 2"
  |> migrate.split_statements
  |> should.equal([
    "create function f() returns int language sql begin atomic select 1; end",
    "select 2",
  ])
}

pub fn split_handles_non_ascii_text_test() {
  "INSERT INTO t (s) VALUES ('größe; ü'); SELECT 'ok'"
  |> migrate.split_statements
  |> should.equal(["INSERT INTO t (s) VALUES ('größe; ü')", "SELECT 'ok'"])
}

// -- run -----------------------------------------------------------------------

const test_dir = "build/test_migrations"

fn setup(files: List(#(String, String))) -> Nil {
  let _ = simplifile.delete(test_dir)
  let assert Ok(_) = simplifile.create_directory_all(test_dir)
  list.each(files, fn(file) {
    let assert Ok(_) = simplifile.write(test_dir <> "/" <> file.0, file.1)
  })
}

pub fn run_applies_each_migration_with_its_record_in_one_transaction_test() {
  setup([
    #("002_second.sql", "SELECT 2"),
    #("001_first.sql", "SELECT 1"),
    #("notes.txt", "ignored"),
  ])
  let log = start_log()
  let result =
    migrate.run(
      test_dir,
      query: fn(_) { Ok(["001_first.sql"]) },
      transaction: fn(scripts) {
        append_log(log, scripts)
        Ok(Nil)
      },
    )

  result |> should.equal(Ok(1))
  read_log(log)
  |> should.equal([
    [
      "CREATE TABLE IF NOT EXISTS _migrations (\n  name TEXT PRIMARY KEY,\n  applied_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP\n)",
    ],
    ["SELECT 2", "INSERT INTO _migrations (name) VALUES ('002_second.sql')"],
  ])
}

pub fn run_stops_at_first_failure_and_names_the_file_test() {
  setup([
    #("001_good.sql", "SELECT 1"),
    #("002_bad.sql", "SELEC 2"),
    #("003_never.sql", "SELECT 3"),
  ])
  let log = start_log()
  let result =
    migrate.run(test_dir, query: fn(_) { Ok([]) }, transaction: fn(scripts) {
      append_log(log, scripts)
      case list.any(scripts, string.starts_with(_, "SELEC ")) {
        True -> Error("syntax error at or near \"SELEC\"")
        False -> Ok(Nil)
      }
    })

  result
  |> should.equal(Error(
    "Migration 002_bad.sql failed and was rolled back: syntax error at or near \"SELEC\"",
  ))
  // The third migration never ran
  read_log(log)
  |> list.flatten
  |> list.contains("SELECT 3")
  |> should.be_false
}

pub fn run_reports_missing_directory_test() {
  migrate.run(
    "build/does_not_exist",
    query: fn(_) { Ok([]) },
    transaction: fn(_) { Ok(Nil) },
  )
  |> should.equal(Error(
    "Could not read migrations directory: build/does_not_exist",
  ))
}

pub fn run_escapes_quotes_in_recorded_name_test() {
  setup([#("001_it's.sql", "SELECT 1")])
  let log = start_log()
  let _ =
    migrate.run(test_dir, query: fn(_) { Ok([]) }, transaction: fn(scripts) {
      append_log(log, scripts)
      Ok(Nil)
    })
  read_log(log)
  |> list.flatten
  |> list.contains("INSERT INTO _migrations (name) VALUES ('001_it''s.sql')")
  |> should.be_true
}

// A tiny mutable log, so the callbacks can record what they were given

type Log

@external(erlang, "refrakt_migrate_test_ffi", "start_log")
fn start_log() -> Log

@external(erlang, "refrakt_migrate_test_ffi", "append_log")
fn append_log(log: Log, entry: List(String)) -> Nil

@external(erlang, "refrakt_migrate_test_ffi", "read_log")
fn read_log(log: Log) -> List(List(String))
