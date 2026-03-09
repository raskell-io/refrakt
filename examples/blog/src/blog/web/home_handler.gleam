import blog/context.{type Context}
import blog/web/layouts/root_layout
import lustre/attribute.{class}
import lustre/element.{text}
import lustre/element/html.{h1, p, section}
import wisp.{type Request, type Response}

pub fn index(_req: Request, _ctx: Context) -> Response {
  section([class("hero")], [
    h1([], [text("Welcome to blog")]),
    p([], [
      text("Built with Refrakt — a convention-first web framework for Gleam."),
    ]),
  ])
  |> root_layout.wrap("Home")
  |> wisp.html_response(200)
}
