import blog/config.{type Config}
import envoy
import gleam/erlang/process
import gleam/result
import pog

/// Connect to PostgreSQL. The connection URL comes from `DATABASE_URL`;
/// without it, development and test use a local server as the
/// `postgres` user.
pub fn connect(cfg: Config) -> Result(pog.Connection, Nil) {
  let default_url = case cfg.env {
    config.Test -> "postgres://postgres@localhost:5432/blog_test"
    _ -> "postgres://postgres@localhost:5432/blog_dev"
  }
  let db_url = envoy.get("DATABASE_URL") |> result.unwrap(default_url)

  let pool_name = process.new_name(prefix: "blog_db")
  use db_config <- result.try(pog.url_config(pool_name, db_url))
  case pog.start(db_config) {
    Ok(_started) -> Ok(pog.named_connection(pool_name))
    Error(_) -> Error(Nil)
  }
}
