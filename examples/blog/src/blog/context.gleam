import blog/config
import pog

pub type Context {
  Context(config: config.Config, db: pog.Connection)
}
