//// Migration runner for Refrakt applications.
////
//// Reads SQL files from a migrations directory, tracks applied migrations
//// in a `_migrations` table, and runs pending ones in order. Each migration
//// runs in its own transaction together with its `_migrations` row, so a
//// failing migration leaves no partial schema changes and is not recorded.
////
//// ## Usage from CLI
////
//// ```
//// refrakt migrate
//// ```
////
//// The CLI generates `src/<app>/migrate.gleam`, which connects to the
//// database and calls `run` with two small callbacks.
////
//// ## Usage from code
////
//// ```gleam
//// import refrakt/migrate
////
//// migrate.run(
////   "src/my_app/data/migrations",
////   query: query_strings,
////   transaction: transaction,
//// )
//// ```
////

import gleam/int
import gleam/io
import gleam/list
import gleam/result
import gleam/string
import simplifile

/// A migration file with its number and name.
pub type Migration {
  Migration(number: Int, name: String, filename: String, sql: String)
}

const create_migrations_table =
  "CREATE TABLE IF NOT EXISTS _migrations (
  name TEXT PRIMARY KEY,
  applied_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
)"

/// Run all pending migrations in a directory.
/// Returns the number of migrations applied.
///
/// - `query` runs a `SELECT` and returns the first column of every row.
/// - `transaction` runs SQL scripts in order inside one transaction:
///   it commits when all of them succeed and rolls back otherwise. Each
///   script may hold several statements. On Postgres, split them with
///   `split_statements` first, since a Postgres query runs one statement.
///
/// Each migration file and the `INSERT` into `_migrations` that records it
/// go through one `transaction` call. Migrations stop at the first failure,
/// and the error names the failing file.
pub fn run(
  in migrations_dir: String,
  query query_strings: fn(String) -> Result(List(String), String),
  transaction transaction: fn(List(String)) -> Result(Nil, String),
) -> Result(Int, String) {
  apply(migrations_dir, query_strings, transaction, io.println)
}

/// Like `run`, but prints nothing. Test databases use it to apply the
/// migrations before every test without filling the test output.
pub fn run_quietly(
  in migrations_dir: String,
  query query_strings: fn(String) -> Result(List(String), String),
  transaction transaction: fn(List(String)) -> Result(Nil, String),
) -> Result(Int, String) {
  apply(migrations_dir, query_strings, transaction, fn(_) { Nil })
}

fn apply(
  migrations_dir: String,
  query_strings: fn(String) -> Result(List(String), String),
  transaction: fn(List(String)) -> Result(Nil, String),
  log: fn(String) -> Nil,
) -> Result(Int, String) {
  use _ <- result.try(
    transaction([create_migrations_table])
    |> result.map_error(fn(e) { "Could not create _migrations table: " <> e }),
  )
  use pending <- result.try(pending_migrations(query_strings, migrations_dir))
  use _ <- result.try(
    list.try_each(pending, fn(migration) {
      log("  " <> migration.filename <> " ...")
      use _ <- result.try(
        transaction([migration.sql, record_statement(migration)])
        |> result.map_error(fn(e) {
          "Migration "
          <> migration.filename
          <> " failed and was rolled back: "
          <> e
        }),
      )
      log("  " <> migration.filename <> " ✓")
      Ok(Nil)
    }),
  )
  Ok(list.length(pending))
}

/// Run all pending migrations in a directory, one SQL string per file,
/// without a transaction. Returns the number of migrations applied.
@deprecated("Use `run`, which applies each migration in a transaction. Delete src/<app>/migrate.gleam and run `refrakt migrate` to regenerate it.")
pub fn run_from_directory(
  db_execute: fn(String) -> Result(Nil, String),
  db_query_strings: fn(String) -> Result(List(String), String),
  migrations_dir: String,
) -> Result(Int, String) {
  use _ <- result.try(db_execute(create_migrations_table))
  use pending <- result.try(pending_migrations(db_query_strings, migrations_dir))
  use _ <- result.try(
    list.try_each(pending, fn(migration) {
      io.println("  " <> migration.filename <> " ...")
      use _ <- result.try(
        db_execute(migration.sql)
        |> result.map_error(fn(e) {
          "Migration " <> migration.filename <> " failed: " <> e
        }),
      )
      use _ <- result.try(db_execute(record_statement(migration)))
      io.println("  " <> migration.filename <> " ✓")
      Ok(Nil)
    }),
  )
  Ok(list.length(pending))
}

fn pending_migrations(
  query_strings: fn(String) -> Result(List(String), String),
  migrations_dir: String,
) -> Result(List(Migration), String) {
  use applied <- result.try(query_strings(
    "SELECT name FROM _migrations ORDER BY name",
  ))
  use files <- result.try(
    simplifile.read_directory(migrations_dir)
    |> result.replace_error(
      "Could not read migrations directory: " <> migrations_dir,
    ),
  )
  files
  |> list.filter(fn(f) { string.ends_with(f, ".sql") })
  |> list.filter_map(fn(filename) { parse_migration(migrations_dir, filename) })
  |> list.sort(fn(a, b) { int.compare(a.number, b.number) })
  |> list.filter(fn(m) { !list.contains(applied, m.filename) })
  |> Ok
}

fn record_statement(migration: Migration) -> String {
  let name = string.replace(migration.filename, "'", "''")
  "INSERT INTO _migrations (name) VALUES ('" <> name <> "')"
}

fn parse_migration(dir: String, filename: String) -> Result(Migration, Nil) {
  // Extract number from filename like "001_create_posts.sql"
  let parts = string.split(filename, "_")
  case parts {
    [num_str, ..rest] ->
      case int.parse(num_str) {
        Ok(num) -> {
          let name =
            rest
            |> string.join("_")
            |> string.replace(".sql", "")
          case simplifile.read(dir <> "/" <> filename) {
            Ok(sql) ->
              Ok(Migration(
                number: num,
                name: name,
                filename: filename,
                sql: sql,
              ))
            Error(_) -> Error(Nil)
          }
        }
        Error(_) -> Error(Nil)
      }
    _ -> Error(Nil)
  }
}

// -- Splitting statements -----------------------------------------------------

/// Split a SQL script into its statements, for databases that run one
/// statement per query (Postgres through `pog`).
///
/// Splits on `;` but not inside single-quoted strings (including `E'...'`
/// with backslash escapes), double-quoted identifiers, `--` and `/* */`
/// comments, dollar-quoted bodies (`$$ ... $$`, `$tag$ ... $tag$`), or
/// `BEGIN ATOMIC ... END` function bodies. Statements are trimmed and lose
/// their terminating `;`. Empty statements and statements holding only
/// comments are dropped.
///
/// ```gleam
/// split_statements("CREATE TABLE a (id INT); CREATE INDEX a_id ON a (id);")
/// // -> ["CREATE TABLE a (id INT)", "CREATE INDEX a_id ON a (id)"]
/// ```
pub fn split_statements(sql: String) -> List(String) {
  sql
  |> string.to_graphemes
  |> split_loop(new_splitter())
}

type Mode {
  Code
  SingleQuoted(backslash_escapes: Bool)
  DoubleQuoted
  LineComment
  BlockComment(depth: Int)
  DollarQuoted(tag: String)
}

type Splitter {
  Splitter(
    mode: Mode,
    // Graphemes of the current statement, in reverse
    current: List(String),
    // Whether the current statement holds anything besides comments
    has_code: Bool,
    // The identifier or keyword being read, and the one before it
    word: String,
    previous_word: String,
    // Nesting inside `BEGIN ATOMIC ... END`, where `;` does not split
    atomic_depth: Int,
    // Finished statements, in reverse
    statements: List(String),
  )
}

fn new_splitter() -> Splitter {
  Splitter(
    mode: Code,
    current: [],
    has_code: False,
    word: "",
    previous_word: "",
    atomic_depth: 0,
    statements: [],
  )
}

fn split_loop(chars: List(String), s: Splitter) -> List(String) {
  case s.mode, chars {
    _, [] -> list.reverse(finish_statement(end_word(s)).statements)

    Code, [";", ..rest] -> {
      let s = end_word(s)
      case s.atomic_depth > 0 {
        True -> split_loop(rest, push(s, ";"))
        False -> split_loop(rest, finish_statement(s))
      }
    }
    Code, ["-", "-", ..rest] ->
      split_loop(rest, Splitter(..push(end_word(s), "--"), mode: LineComment))
    Code, ["/", "*", ..rest] ->
      split_loop(
        rest,
        Splitter(..push(end_word(s), "/*"), mode: BlockComment(1)),
      )
    Code, ["'", ..rest] -> {
      let escapes = string.uppercase(s.word) == "E"
      let s = push(end_word(s), "'")
      split_loop(
        rest,
        Splitter(..s, mode: SingleQuoted(escapes), has_code: True),
      )
    }
    Code, ["\"", ..rest] -> {
      let s = push(end_word(s), "\"")
      split_loop(rest, Splitter(..s, mode: DoubleQuoted, has_code: True))
    }
    Code, ["$", ..rest] if s.word == "" ->
      case dollar_tag(rest, "$") {
        Ok(#(tag, rest)) -> {
          let s =
            Splitter(..push(s, tag), mode: DollarQuoted(tag), has_code: True)
          split_loop(rest, s)
        }
        Error(Nil) -> split_loop(rest, Splitter(..push(s, "$"), has_code: True))
      }
    Code, [char, ..rest] ->
      case is_word_char(char) {
        True ->
          split_loop(
            rest,
            Splitter(..push(s, char), word: s.word <> char, has_code: True),
          )
        False -> {
          let s = push(end_word(s), char)
          let has_code = s.has_code || string.trim(char) != ""
          split_loop(rest, Splitter(..s, has_code: has_code))
        }
      }

    SingleQuoted(True), ["\\", escaped, ..rest] ->
      split_loop(rest, push(push(s, "\\"), escaped))
    SingleQuoted(_), ["'", "'", ..rest] -> split_loop(rest, push(s, "''"))
    SingleQuoted(_), ["'", ..rest] ->
      split_loop(rest, Splitter(..push(s, "'"), mode: Code))

    DoubleQuoted, ["\"", ..rest] ->
      split_loop(rest, Splitter(..push(s, "\""), mode: Code))

    LineComment, ["\n", ..rest] | LineComment, ["\r\n", ..rest] ->
      split_loop(rest, Splitter(..push(s, "\n"), mode: Code))

    BlockComment(depth), ["/", "*", ..rest] ->
      split_loop(rest, Splitter(..push(s, "/*"), mode: BlockComment(depth + 1)))
    BlockComment(1), ["*", "/", ..rest] ->
      split_loop(rest, Splitter(..push(s, "*/"), mode: Code))
    BlockComment(depth), ["*", "/", ..rest] ->
      split_loop(rest, Splitter(..push(s, "*/"), mode: BlockComment(depth - 1)))

    DollarQuoted(tag), ["$", ..] ->
      case starts_with(chars, tag) {
        Ok(rest) -> split_loop(rest, Splitter(..push(s, tag), mode: Code))
        Error(Nil) -> split_loop(list.drop(chars, 1), push(s, "$"))
      }

    _, [char, ..rest] -> split_loop(rest, push(s, char))
  }
}

fn push(s: Splitter, text: String) -> Splitter {
  Splitter(..s, current: [text, ..s.current])
}

/// Finish the identifier or keyword being read, tracking
/// `BEGIN ATOMIC ... END` bodies (and `CASE ... END` inside them).
fn end_word(s: Splitter) -> Splitter {
  case s.word {
    "" -> s
    word -> {
      let word = string.uppercase(word)
      let depth = case word, s.atomic_depth {
        "ATOMIC", depth if s.previous_word == "BEGIN" -> depth + 1
        "CASE", depth if depth > 0 -> depth + 1
        "END", depth if depth > 0 -> depth - 1
        _, depth -> depth
      }
      Splitter(..s, word: "", previous_word: word, atomic_depth: depth)
    }
  }
}

fn finish_statement(s: Splitter) -> Splitter {
  let statements = case s.has_code {
    True -> [
      s.current |> list.reverse |> string.concat |> string.trim,
      ..s.statements
    ]
    False -> s.statements
  }
  Splitter(..new_splitter(), statements: statements)
}

/// After a `$`, read the rest of a dollar-quote tag: `$` or `name$`.
/// Returns the whole tag (`$$` or `$name$`) and the remaining input.
fn dollar_tag(
  chars: List(String),
  tag: String,
) -> Result(#(String, List(String)), Nil) {
  case chars {
    ["$", ..rest] -> Ok(#(tag <> "$", rest))
    [char, ..rest] ->
      case is_word_char(char) && !is_digit_start(tag, char) {
        True -> dollar_tag(rest, tag <> char)
        False -> Error(Nil)
      }
    [] -> Error(Nil)
  }
}

/// Dollar-quote tags cannot start with a digit (`$1` is a parameter).
fn is_digit_start(tag: String, char: String) -> Bool {
  tag == "$" && string.contains("0123456789", char)
}

fn starts_with(
  chars: List(String),
  prefix: String,
) -> Result(List(String), Nil) {
  let prefix = string.to_graphemes(prefix)
  let length = list.length(prefix)
  case list.take(chars, length) == prefix {
    True -> Ok(list.drop(chars, length))
    False -> Error(Nil)
  }
}

fn is_word_char(char: String) -> Bool {
  case string.to_utf_codepoints(char) {
    [codepoint, ..] -> {
      let code = string.utf_codepoint_to_int(codepoint)
      { code >= 0x61 && code <= 0x7A }
      || { code >= 0x41 && code <= 0x5A }
      || { code >= 0x30 && code <= 0x39 }
      || code == 0x5F
      || code == 0x24
      || code > 0x7F
    }
    [] -> False
  }
}
