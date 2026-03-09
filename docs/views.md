# Views & Templates

Refrakt uses Lustre's HTML functions for templating. Views are plain
Gleam functions that return `Element(Nil)`. No template language, no
string interpolation, no macros.

## How views work

A view function takes data and returns a Lustre element:

```gleam
import lustre/attribute.{class}
import lustre/element.{type Element, text}
import lustre/element/html.{h1, p, section}

pub fn show_view(post: Post) -> Element(Nil) {
  section([class("post")], [
    h1([], [text(post.title)]),
    p([], [text(post.body)]),
  ])
}
```

Every HTML tag is a function: `div`, `h1`, `p`, `a`, `form`, `input`,
`button`, etc. They take two arguments:
1. A list of attributes
2. A list of child elements

## Attributes

```gleam
import lustre/attribute.{class, href, id, name, type_, value}

// Single attribute
h1([class("title")], [text("Hello")])

// Multiple attributes
a([href("/posts"), class("btn")], [text("View Posts")])

// Boolean attributes
input([type_("checkbox"), attribute.checked(True)])
```

Note: `type_` has a trailing underscore because `type` is a reserved
word in Gleam.

## Rendering to HTML

Views produce `Element(Nil)`. To turn them into an HTML string, use
the layout:

```gleam
post_views.show_view(post)           // Element(Nil)
|> root_layout.wrap("My Post")       // String
|> wisp.html_response(200)           // Response
```

`root_layout.wrap` calls `element.to_document_string` internally,
which produces a complete HTML document with `<!doctype html>`.

## Layouts

The root layout wraps content in the HTML shell:

```gleam
// src/<app>/web/layouts/root_layout.gleam
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
    ]),
  ])
  |> element.to_document_string
}
```

You can modify this layout freely — add navigation, footer, scripts,
additional CSS, etc.

### Multiple layouts

Create additional layout files for different sections of your app:

```gleam
// src/<app>/web/layouts/admin_layout.gleam
pub fn wrap(inner: Element(Nil), page_title: String) -> String {
  // different HTML shell for admin pages
}
```

## Components

Reusable UI pieces live in `src/<app>/web/components/`:

```gleam
// src/<app>/web/components/flash.gleam
pub fn render(message: Option(String)) -> Element(Nil) {
  case message {
    Some(msg) -> div([class("flash")], [p([], [text(msg)])])
    None -> text("")
  }
}
```

Use components in views:

```gleam
import my_app/web/components/flash

pub fn index_view(posts: List(Post), flash_msg: Option(String)) -> Element(Nil) {
  section([], [
    flash.render(flash_msg),
    h1([], [text("Posts")]),
    // ...
  ])
}
```

## Lists and iteration

Use `list.map` to render lists:

```gleam
import gleam/list

pub fn index_view(posts: List(Post)) -> Element(Nil) {
  ul(
    [],
    list.map(posts, fn(post) {
      li([], [
        a([href("/posts/" <> int.to_string(post.id))], [
          text(post.title),
        ]),
      ])
    }),
  )
}
```

## Conditional rendering

Use `case` expressions:

```gleam
pub fn badge(published: Bool) -> Element(Nil) {
  case published {
    True -> span([class("badge published")], [text("Published")])
    False -> span([class("badge draft")], [text("Draft")])
  }
}
```

To render nothing, use `text("")`:

```gleam
case show_sidebar {
  True -> sidebar_view()
  False -> text("")
}
```

## Generated views

`refrakt gen resource posts title:string body:text published:bool`
creates three view functions:

- `index_view(posts)` — list all items with links
- `show_view(post)` — show a single item with edit link
- `form_view(values, errors)` — form with fields and validation errors

The form view renders appropriate input types based on field types:
- `string` → `<input type="text">`
- `text` → `<textarea>`
- `bool` → `<input type="checkbox">`
- `int` / `float` → `<input type="number">`

## Static assets

CSS and JavaScript live in `priv/static/`. Reference them in layouts:

```gleam
link([rel("stylesheet"), href("/static/css/app.css")])
script([src("/static/js/app.js")], "")
```

The default middleware serves files from `priv/static/` at the
`/static/` URL prefix.
