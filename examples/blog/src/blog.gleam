import blog/config
import blog/context
import blog/data/repo
import blog/router
import gleam/erlang/process
import gleam/io
import mist
import wisp
import wisp/wisp_mist

pub fn main() {
  wisp.configure_logger()

  let cfg = config.load()
  let assert Ok(db) = repo.connect(cfg)
  let ctx = context.Context(config: cfg, db: db)

  let assert Ok(_) =
    wisp_mist.handler(router.handle_request(_, ctx), cfg.secret_key_base)
    |> mist.new
    |> mist.port(cfg.port)
    |> mist.start

  io.println("Listening on http://localhost:" <> cfg.port_string)
  process.sleep_forever()
}
