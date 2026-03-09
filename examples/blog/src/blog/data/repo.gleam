import blog/config.{type Config}
import gleam/erlang/process
import gleam/result
import pog

pub fn connect(cfg: Config) -> Result(pog.Connection, Nil) {
  let db_url = case cfg.env {
    config.Test -> "postgres://localhost:5432/blog_test"
    _ -> "postgres://localhost:5432/blog_dev"
  }

  let pool_name = process.new_name(prefix: "blog_db")
  use db_config <- result.try(pog.url_config(pool_name, db_url))
  case pog.start(db_config) {
    Ok(_started) -> Ok(pog.named_connection(pool_name))
    Error(_) -> Error(Nil)
  }
}
