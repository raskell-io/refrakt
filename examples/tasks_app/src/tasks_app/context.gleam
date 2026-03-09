import tasks_app/config

pub type Context {
  Context(config: config.Config, db_path: String)
}
