import blog/context.{type Context}
import blog/web/layouts/root_layout
import lustre/attribute.{class}
import lustre/element.{text}
import lustre/element/html.{h1, section}
import wisp.{type Request, type Response}

pub fn index(_req: Request, _ctx: Context) -> Response {
  section([class("about")], [
    h1([], [text("About")]),
  ])
  |> root_layout.wrap("About")
  |> wisp.html_response(200)
}
