# Lustre Integration — Phase 2

## Status

Refrakt already uses Lustre for server-side HTML rendering. Every view
is a Lustre `Element(Nil)` rendered via `element.to_document_string`.

Phase 2 adds **interactive islands** — Lustre client-side apps embedded
in server-rendered pages, and optionally Lustre server components
(real-time UI over WebSocket).

## Architecture

### Three modes (progressive)

**Mode 1: Server-rendered only (current)**
- Views are Lustre HTML functions
- `Element(Nil)` → `String` via `element.to_document_string`
- No client JavaScript beyond `app.js`
- This is the default `refrakt new` experience

**Mode 2: Interactive islands**
- Server renders the page shell
- Specific areas mount a Lustre client-side app
- `refrakt gen island <name>` creates a Lustre `application` module
- The island JS is bundled separately and loaded on the page
- Communication: the island reads data from HTML attributes or
  a JSON script tag placed by the server

**Mode 3: Server components (future)**
- Lustre app runs on the server, patches DOM over WebSocket
- Requires Mist WebSocket wiring
- `refrakt gen live <name>` creates the component + transport
- This is the LiveView-equivalent

## gen island (Mode 2)

```
refrakt gen island counter
```

Creates:
```
src/<app>/web/islands/counter.gleam    ← Lustre client app (init, update, view)
src/<app>/web/islands/counter_embed.gleam ← Server helper to embed the island
```

The island module:
```gleam
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

pub fn view(model: Model) -> Element(Msg) {
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
```

The embed helper:
```gleam
import lustre/element.{type Element}
import lustre/element/html.{div, script}
import lustre/attribute.{id, src}

pub fn render() -> Element(Nil) {
  div([id("counter")], [
    // Placeholder content (shown before JS loads)
    text("Loading..."),
  ])
}

pub fn script_tag() -> Element(Nil) {
  script([src("/static/js/islands/counter.js")], "")
}
```

Usage in a server-rendered view:
```gleam
import my_app/web/islands/counter_embed

pub fn show_view(post: Post) -> Element(Nil) {
  section([], [
    h1([], [text(post.title)]),
    div([], [text(post.body)]),
    // Embed an interactive counter island
    counter_embed.render(),
    counter_embed.script_tag(),
  ])
}
```

### Build pipeline for islands

Islands need to be compiled to JavaScript:

```bash
gleam build --target javascript
```

The output JS is placed in `priv/static/js/islands/`. This requires:
1. A separate `gleam.toml` target or build step for the JS bundle
2. Or: a simple esbuild/rollup step in the dev workflow

For MVP, the developer manually runs:
```bash
cd islands/
gleam build --target javascript
cp build/dev/javascript/*/main.mjs ../priv/static/js/islands/counter.js
```

A future `refrakt build` command could automate this.

## gen live (Mode 3 — future)

```
refrakt gen live dashboard
```

Creates:
```
src/<app>/web/live/dashboard.gleam     ← Lustre server component
src/<app>/web/live/dashboard_socket.gleam ← WebSocket transport
```

The server component runs a full Lustre app on the server. DOM patches
are sent to the client over WebSocket via Mist. The client runtime
(~10kb JS) applies patches.

This requires:
- Mist WebSocket support (already available)
- Lustre server component transport (available but manual)
- Client runtime JS (provided by Lustre)

## Recommended implementation order

1. Document the island pattern (this file) ✓
2. Add `refrakt gen island` command
3. Add `islands/` directory convention to `refrakt new`
4. Write an example with one interactive island
5. Later: add `refrakt gen live` for server components
6. Later: automate JS build in `refrakt build`

## Non-goals

- Refrakt does not build its own client runtime
- Refrakt does not replace Lustre's architecture
- Refrakt does not add a custom WebSocket protocol
- Server components use Lustre's existing transport format
