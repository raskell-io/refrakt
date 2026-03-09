import blog/context.{type Context}
import blog/web/about_handler
import blog/web/auth_handler
import blog/web/error_handler
import blog/web/home_handler
import blog/web/post_handler
import gleam/http
import wisp.{type Request, type Response}

pub fn handle_request(req: Request, ctx: Context) -> Response {
  use req <- middleware(req)

  case wisp.path_segments(req), req.method {
    [], http.Get -> home_handler.index(req, ctx)

    ["posts"], http.Get -> post_handler.index(req, ctx)
    ["posts", "new"], http.Get -> post_handler.new(req, ctx)
    ["posts"], http.Post -> post_handler.create(req, ctx)
    ["posts", id], http.Get -> post_handler.show(req, ctx, id)
    ["posts", id, "edit"], http.Get -> post_handler.edit(req, ctx, id)
    ["posts", id], http.Put -> post_handler.update(req, ctx, id)
    ["posts", id], http.Delete -> post_handler.delete(req, ctx, id)

    ["login"], http.Get -> auth_handler.login_page(req, ctx)
    ["login"], http.Post -> auth_handler.login(req, ctx)
    ["register"], http.Get -> auth_handler.register_page(req, ctx)
    ["register"], http.Post -> auth_handler.register(req, ctx)
    ["logout"], http.Post -> auth_handler.logout(req, ctx)
    ["about"], http.Get -> about_handler.index(req, ctx)
    _, _ -> error_handler.not_found(req)
  }
}

fn middleware(req: Request, next: fn(Request) -> Response) -> Response {
  let req = wisp.method_override(req)
  use <- wisp.log_request(req)
  use <- wisp.rescue_crashes
  use <- wisp.serve_static(req, under: "/static", from: priv_static())
  next(req)
}

fn priv_static() -> String {
  let assert Ok(priv) = wisp.priv_directory("blog")
  priv <> "/static"
}
