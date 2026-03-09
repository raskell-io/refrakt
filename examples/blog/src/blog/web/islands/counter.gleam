/// Interactive island: counter
///
/// This is a Lustre client-side app. Compile to JavaScript with:
///   gleam build --target javascript
///
import gleam/int
import lustre
import lustre/element.{text}
import lustre/element/html.{button, div, p}
import lustre/event

pub type Model {
  Model(count: Int)
}

pub type Msg {
  Increment
  Decrement
}

pub fn init(_flags: Nil) -> Model {
  Model(count: 0)
}

pub fn update(model: Model, msg: Msg) -> Model {
  case msg {
    Increment -> Model(count: model.count + 1)
    Decrement -> Model(count: model.count - 1)
  }
}

pub fn view(model: Model) -> element.Element(Msg) {
  div([], [
    button([event.on_click(Decrement)], [text("-")]),
    p([], [text(int.to_string(model.count))]),
    button([event.on_click(Increment)], [text("+")]),
  ])
}

pub fn main() {
  let app = lustre.simple(init, update, view)
  let assert Ok(_) = lustre.start(app, "#counter", Nil)
}
