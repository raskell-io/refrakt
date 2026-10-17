import gleam/http
import refrakt/dev_error
import tasks_app/config
import tasks_app/context.{type Context}
import tasks_app/web/error_handler
import tasks_app/web/home_handler
import tasks_app/web/task_handler
import wisp.{type Request, type Response}

pub fn handle_request(req: Request, ctx: Context) -> Response {
  use req <- middleware(req, ctx)

  case wisp.path_segments(req), req.method {
    [], http.Get -> home_handler.index(req, ctx)

    ["tasks"], http.Get -> task_handler.index(req, ctx)
    ["tasks", "new"], http.Get -> task_handler.new(req, ctx)
    ["tasks"], http.Post -> task_handler.create(req, ctx)
    ["tasks", id], http.Get -> task_handler.show(req, ctx, id)
    ["tasks", id, "edit"], http.Get -> task_handler.edit(req, ctx, id)
    ["tasks", id], http.Put -> task_handler.update(req, ctx, id)
    ["tasks", id], http.Delete -> task_handler.delete(req, ctx, id)
    _, _ -> error_handler.not_found(req)
  }
}

fn middleware(
  req: Request,
  ctx: Context,
  next: fn(Request) -> Response,
) -> Response {
  let req = wisp.method_override(req)
  use <- wisp.log_request(req)
  use <- rescue_crashes(req, ctx)
  use <- wisp.serve_static(req, under: "/static", from: priv_static())
  next(req)
}

/// In development a crash shows the detailed error page (error, stack
/// trace, request). Everywhere else it is logged and the visitor gets a
/// plain 500, so internals never leak in production.
fn rescue_crashes(
  req: Request,
  ctx: Context,
  next: fn() -> Response,
) -> Response {
  case ctx.config.env {
    config.Dev -> dev_error.rescue(req, next)
    config.Test | config.Prod -> wisp.rescue_crashes(next)
  }
}

fn priv_static() -> String {
  let assert Ok(priv) = wisp.priv_directory("tasks_app")
  priv <> "/static"
}
