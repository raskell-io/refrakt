import gleam/string
import gleeunit/should
import refrakt_cli/migrate_cmd

pub fn postgres_module_splits_statements_in_a_transaction_test() {
  let module = migrate_cmd.migrate_module_postgres("blog")

  string.contains(module, "pog.transaction(db, fn(conn) {")
  |> should.be_true
  string.contains(module, "list.flat_map(migrate.split_statements)")
  |> should.be_true
  string.contains(module, "pog.execute(conn)")
  |> should.be_true
  string.contains(module, "migrate.run(migrations_dir")
  |> should.be_true
  string.contains(module, "run_from_directory")
  |> should.be_false
  string.contains(module, "\"src/blog/data/migrations\"")
  |> should.be_true
}

pub fn sqlite_module_wraps_scripts_in_begin_commit_test() {
  let module = migrate_cmd.migrate_module_sqlite("blog")

  string.contains(module, "exec(\"BEGIN\", conn)")
  |> should.be_true
  string.contains(module, "exec(\"COMMIT\", conn)")
  |> should.be_true
  string.contains(module, "exec(\"ROLLBACK\", conn)")
  |> should.be_true
  string.contains(module, "migrate.run(migrations_dir")
  |> should.be_true
  string.contains(module, "run_from_directory")
  |> should.be_false
}
