import lustre/attribute.{class}
import lustre/element.{text}
import lustre/element/html.{h1, p, section}
import tasks_app/context.{type Context}
import tasks_app/web/layouts/root_layout
import wisp.{type Request, type Response}

pub fn index(_req: Request, _ctx: Context) -> Response {
  section([class("hero")], [
    h1([], [text("Welcome to tasks_app")]),
    p([], [
      text("Built with Refrakt — a convention-first web framework for Gleam."),
    ]),
  ])
  |> root_layout.wrap("Home")
  |> wisp.html_response(200)
}
