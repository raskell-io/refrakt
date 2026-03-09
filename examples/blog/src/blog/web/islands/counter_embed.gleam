/// Server-side helper to embed the counter island in a view.
///
import lustre/attribute.{id, src}
import lustre/element.{type Element, text}
import lustre/element/html.{div, script}

/// Render the mount point for the island.
pub fn render() -> Element(Nil) {
  div([id("counter")], [text("Loading...")])
}

/// Render the script tag that loads the island JS.
pub fn script_tag() -> Element(Nil) {
  script([src("/static/js/islands/counter.js")], "")
}
