import lustre/attribute.{class}
import lustre/element.{text}
import lustre/element/html.{h1, p, section}
import wisp.{type Request, type Response}

pub fn not_found(_req: Request) -> Response {
  section([class("error-page")], [
    h1([], [text("404")]),
    p([], [text("Page not found.")]),
  ])
  |> element.to_string
  |> wisp.html_response(404)
}

pub fn internal_error(_req: Request) -> Response {
  section([class("error-page")], [
    h1([], [text("500")]),
    p([], [text("Something went wrong.")]),
  ])
  |> element.to_string
  |> wisp.html_response(500)
}
