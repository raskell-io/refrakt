import lustre/attribute.{charset, class, content, href, name, rel}
import lustre/element.{type Element}
import lustre/element/html.{body, head, html, link, main, meta, title}
import refrakt/live_reload

pub fn wrap(inner: Element(Nil), page_title: String) -> String {
  html([], [
    head([], [
      meta([charset("utf-8")]),
      meta([name("viewport"), content("width=device-width, initial-scale=1")]),
      title([], page_title),
      link([rel("stylesheet"), href("/static/css/app.css")]),
    ]),
    body([], [
      main([class("container")], [inner]),
      // Reloads the page after `refrakt dev` rebuilds; renders nothing
      // unless APP_ENV=dev under `refrakt dev`.
      live_reload.script(),
    ]),
  ])
  |> element.to_document_string
}
