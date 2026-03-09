import gleam/erlang/process
import gleam/io
import mist
import tasks_app/config
import tasks_app/context
import tasks_app/data/repo
import tasks_app/router
import wisp
import wisp/wisp_mist

pub fn main() {
  wisp.configure_logger()

  let cfg = config.load()
  let db_path = repo.database_path(cfg)
  let ctx = context.Context(config: cfg, db_path: db_path)

  let assert Ok(_) =
    wisp_mist.handler(router.handle_request(_, ctx), cfg.secret_key_base)
    |> mist.new
    |> mist.port(cfg.port)
    |> mist.start

  io.println("Listening on http://localhost:" <> cfg.port_string)
  process.sleep_forever()
}
