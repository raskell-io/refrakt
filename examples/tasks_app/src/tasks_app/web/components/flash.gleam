import gleam/option.{type Option, None, Some}
import lustre/attribute.{class}
import lustre/element.{type Element, text}
import lustre/element/html.{div, p}

pub fn render(message: Option(String)) -> Element(Nil) {
  case message {
    Some(msg) ->
      div([class("flash")], [
        p([], [text(msg)]),
      ])
    None -> text("")
  }
}
