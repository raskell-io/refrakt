import tasks_app/config.{type Config}

/// Get the SQLite database path for the current environment.
pub fn database_path(cfg: Config) -> String {
  case cfg.env {
    config.Test -> ":memory:"
    _ -> "tasks_app.db"
  }
}
