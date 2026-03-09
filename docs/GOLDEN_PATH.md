# Golden Path — Phase 0

The golden path defines every command a developer runs and every file the
framework produces. If this document is not clean, the framework will not
feel coherent.

Everything below is designed against what actually exists today:
Wisp 2.2, Lustre 5.6, Mist 5, Pog 4.1, Sqlight 1.0, gleam_http 4.3.

---

## Framework name

**Refrakt**

Light enters, structure emerges. German spelling of "refract" — what a
prism does. Free on Hex, distinctive, no ecosystem collisions.

---

## Commands

The CLI is `refrakt`. It wraps `gleam` — it does not replace it.
`gleam build`, `gleam test`, `gleam run` still work.
Refrakt adds the conventions on top.

### `refrakt new <name>`

Create a new project.

```
$ refrakt new my_app
Creating my_app...

  my_app/
    gleam.toml
    .gitignore
    README.md
    src/
      my_app.gleam              ← entry point, starts server
      my_app/config.gleam       ← typed config, env-driven
      my_app/router.gleam       ← top-level router
      my_app/web/
        home_handler.gleam      ← default "/" handler
        error_handler.gleam     ← fallback error responses
      my_app/web/layouts/
        root_layout.gleam       ← base HTML shell
      my_app/web/components/
        flash.gleam             ← flash message component
      my_app/domain/            ← (empty, your business logic)
      my_app/data/              ← (empty, your persistence)
    priv/
      static/
        css/app.css
        js/app.js
        favicon.ico
    test/
      my_app_test.gleam
      my_app/web/
        home_handler_test.gleam

  Run your app:
    cd my_app
    gleam run
    → http://localhost:4000
```

Flags:
- `--db postgres` — adds Pog dependency, creates `src/my_app/data/repo.gleam`
- `--db sqlite` — adds Sqlight dependency, same
- `--no-db` — default, no database wiring
- `--no-css` — skip default stylesheet

### `refrakt gen page <name>`

Generate a handler + route + view for a static page.

```
$ refrakt gen page about

Created:
  src/my_app/web/about_handler.gleam
  test/my_app/web/about_handler_test.gleam

Updated:
  src/my_app/router.gleam       ← added GET /about route
```

### `refrakt gen resource <name> <field:type ...>`

Generate a full CRUD resource. This is the big one.

```
$ refrakt gen resource posts title:string body:text published:bool

Created:
  src/my_app/web/post_handler.gleam       ← index, show, new, create, edit, update, delete
  src/my_app/web/post_views.gleam         ← index_view, show_view, form_view
  src/my_app/web/forms/post_form.gleam    ← typed form decoder + validation
  src/my_app/domain/post.gleam            ← Post type + domain functions
  src/my_app/data/post_repo.gleam         ← CRUD queries
  src/my_app/data/migrations/001_create_posts.sql
  test/my_app/web/post_handler_test.gleam

Updated:
  src/my_app/router.gleam                 ← added /posts resource routes
```

Field types: `string`, `text`, `int`, `float`, `bool`, `date`, `datetime`,
`optional(string)`, `optional(int)`, etc.

### `refrakt gen auth`

Generate a starter authentication system. Not a library — actual code in
your project that you own and can modify.

```
$ refrakt gen auth

Created:
  src/my_app/web/auth_handler.gleam       ← register, login, logout
  src/my_app/web/auth_views.gleam         ← login form, register form
  src/my_app/web/forms/auth_form.gleam    ← credential validation
  src/my_app/web/middleware/auth.gleam    ← require_auth, load_user
  src/my_app/domain/user.gleam            ← User type
  src/my_app/domain/auth.gleam            ← password hashing, token logic
  src/my_app/data/user_repo.gleam         ← user queries
  src/my_app/data/migrations/001_create_users.sql
  test/my_app/web/auth_handler_test.gleam

Updated:
  src/my_app/router.gleam
```

### `refrakt gen live <name>`

Generate a Lustre server component with WebSocket wiring.
Phase 2+ only. Not in MVP.

### `refrakt gen migration <name>`

Generate a timestamped SQL migration file.

```
$ refrakt gen migration add_email_to_users

Created:
  src/my_app/data/migrations/002_add_email_to_users.sql
```

### `refrakt migrate`

Run pending migrations.

```
$ refrakt migrate
Running migrations...
  001_create_posts.sql ✓
  002_add_email_to_users.sql ✓
Done. 2 migrations applied.
```

### `refrakt dev`

Start the dev server. Wraps `gleam run` with:
- colored request logging
- crash recovery
- clear error pages in the browser

Phase 3 adds file watching + rebuild.

### `refrakt routes`

Print the route table.

```
$ refrakt routes
GET     /                   home_handler.index
GET     /about              about_handler.index
GET     /posts              post_handler.index
GET     /posts/new          post_handler.new
POST    /posts              post_handler.create
GET     /posts/:id          post_handler.show
GET     /posts/:id/edit     post_handler.edit
PUT     /posts/:id          post_handler.update
DELETE  /posts/:id          post_handler.delete
```

---

## Generated code — what it actually looks like

This is the most important section. If the generated code isn't beautiful,
nothing else matters.

### Entry point: `src/my_app.gleam`

```gleam
import gleam/erlang/process
import gleam/io
import mist
import my_app/config
import my_app/router
import wisp
import wisp/wisp_mist

pub fn main() {
  wisp.configure_logger()

  let cfg = config.load()
  let ctx = router.Context(config: cfg)

  let assert Ok(_) =
    wisp_mist.handler(router.handle_request(_, ctx), cfg.secret_key_base)
    |> mist.new
    |> mist.port(cfg.port)
    |> mist.start_http

  io.println("Listening on http://localhost:" <> cfg.port_string)
  process.sleep_forever()
}
```

### Config: `src/my_app/config.gleam`

```gleam
import gleam/erlang/os
import gleam/int
import gleam/result

pub type Config {
  Config(
    port: Int,
    port_string: String,
    secret_key_base: String,
    env: Env,
  )
}

pub type Env {
  Dev
  Test
  Prod
}

pub fn load() -> Config {
  let port =
    os.get_env("PORT")
    |> result.then(int.parse)
    |> result.unwrap(4000)

  let secret_key_base =
    os.get_env("SECRET_KEY_BASE")
    |> result.unwrap("dev-secret-key-base-that-is-at-least-64-bytes-long-for-security!!")

  let env = case os.get_env("APP_ENV") {
    Ok("prod") -> Prod
    Ok("test") -> Test
    _ -> Dev
  }

  Config(
    port: port,
    port_string: int.to_string(port),
    secret_key_base: secret_key_base,
    env: env,
  )
}
```

### Router: `src/my_app/router.gleam`

```gleam
import gleam/http
import my_app/config
import my_app/web/error_handler
import my_app/web/home_handler
import wisp.{type Request, type Response}

pub type Context {
  Context(config: config.Config)
}

pub fn handle_request(req: Request, ctx: Context) -> Response {
  use req <- middleware(req)

  case wisp.path_segments(req) {
    [] -> home_handler.index(req, ctx)
    _ -> error_handler.not_found(req)
  }
}

fn middleware(req: Request, next: fn(Request) -> Response) -> Response {
  let req = wisp.method_override(req)
  use <- wisp.log_request(req)
  use <- wisp.rescue_crashes
  use <- wisp.serve_static(req, under: "/static", from: priv_static())
  next(req)
}

fn priv_static() -> String {
  let assert Ok(priv) = wisp.priv_directory("my_app")
  priv <> "/static"
}
```

After `refrakt gen resource posts title:string body:text published:bool`,
the router becomes:

```gleam
import gleam/http
import my_app/config
import my_app/web/error_handler
import my_app/web/home_handler
import my_app/web/post_handler
import wisp.{type Request, type Response}

pub type Context {
  Context(config: config.Config, db: pog.Connection)
}

pub fn handle_request(req: Request, ctx: Context) -> Response {
  use req <- middleware(req)

  case wisp.path_segments(req), req.method {
    [], http.Get -> home_handler.index(req, ctx)

    ["posts"], http.Get -> post_handler.index(req, ctx)
    ["posts", "new"], http.Get -> post_handler.new(req, ctx)
    ["posts"], http.Post -> post_handler.create(req, ctx)
    ["posts", id], http.Get -> post_handler.show(req, ctx, id)
    ["posts", id, "edit"], http.Get -> post_handler.edit(req, ctx, id)
    ["posts", id], http.Put -> post_handler.update(req, ctx, id)
    ["posts", id], http.Delete -> post_handler.delete(req, ctx, id)

    _, _ -> error_handler.not_found(req)
  }
}

// middleware unchanged
```

This is plain Gleam pattern matching. No DSL, no macros, no magic.
A new developer reads this file and understands the entire routing model
in 30 seconds.

### Handler: `src/my_app/web/post_handler.gleam`

```gleam
import gleam/http
import gleam/int
import my_app/data/post_repo
import my_app/domain/post.{type Post}
import my_app/router.{type Context}
import my_app/web/error_handler
import my_app/web/forms/post_form
import my_app/web/layouts/root_layout
import my_app/web/post_views
import wisp.{type Request, type Response}

pub fn index(req: Request, ctx: Context) -> Response {
  let posts = post_repo.list(ctx.db)
  post_views.index_view(posts)
  |> root_layout.wrap("Posts")
  |> wisp.html_response(200)
}

pub fn show(req: Request, ctx: Context, id: String) -> Response {
  case int.parse(id) {
    Error(_) -> error_handler.not_found(req)
    Ok(id) ->
      case post_repo.get(ctx.db, id) {
        Error(_) -> error_handler.not_found(req)
        Ok(post) ->
          post_views.show_view(post)
          |> root_layout.wrap(post.title)
          |> wisp.html_response(200)
      }
  }
}

pub fn new(req: Request, ctx: Context) -> Response {
  post_views.form_view(post_form.empty(), [])
  |> root_layout.wrap("New Post")
  |> wisp.html_response(200)
}

pub fn create(req: Request, ctx: Context) -> Response {
  use form_data <- wisp.require_form(req)

  case post_form.decode(form_data) {
    Error(errors) ->
      post_views.form_view(post_form.from_form_data(form_data), errors)
      |> root_layout.wrap("New Post")
      |> wisp.html_response(422)

    Ok(params) ->
      case post_repo.create(ctx.db, params) {
        Ok(post) ->
          wisp.redirect("/posts/" <> int.to_string(post.id))
          |> wisp.set_cookie(req, "flash", "Post created", wisp.Signed, 60)

        Error(_) ->
          error_handler.internal_error(req)
      }
  }
}

pub fn edit(req: Request, ctx: Context, id: String) -> Response {
  case int.parse(id) {
    Error(_) -> error_handler.not_found(req)
    Ok(id) ->
      case post_repo.get(ctx.db, id) {
        Error(_) -> error_handler.not_found(req)
        Ok(post) ->
          post_views.form_view(post_form.from_post(post), [])
          |> root_layout.wrap("Edit Post")
          |> wisp.html_response(200)
      }
  }
}

pub fn update(req: Request, ctx: Context, id: String) -> Response {
  use form_data <- wisp.require_form(req)

  case int.parse(id) {
    Error(_) -> error_handler.not_found(req)
    Ok(id) ->
      case post_form.decode(form_data) {
        Error(errors) ->
          post_views.form_view(post_form.from_form_data(form_data), errors)
          |> root_layout.wrap("Edit Post")
          |> wisp.html_response(422)

        Ok(params) ->
          case post_repo.update(ctx.db, id, params) {
            Ok(_) ->
              wisp.redirect("/posts/" <> int.to_string(id))
              |> wisp.set_cookie(req, "flash", "Post updated", wisp.Signed, 60)

            Error(_) ->
              error_handler.internal_error(req)
          }
      }
  }
}

pub fn delete(req: Request, ctx: Context, id: String) -> Response {
  case int.parse(id) {
    Error(_) -> error_handler.not_found(req)
    Ok(id) -> {
      let _ = post_repo.delete(ctx.db, id)
      wisp.redirect("/posts")
      |> wisp.set_cookie(req, "flash", "Post deleted", wisp.Signed, 60)
    }
  }
}
```

### Views: `src/my_app/web/post_views.gleam`

Views use Lustre's HTML functions for type-safe templating.
No string interpolation, no template files, no DSL.

```gleam
import gleam/int
import gleam/list
import lustre/attribute.{class, href, type_, value, name, action, method}
import lustre/element.{type Element, text}
import lustre/element/html.{
  a, button, div, form, h1, h2, input, label, li, p, section, textarea, ul,
}
import my_app/domain/post.{type Post}

pub fn index_view(posts: List(Post)) -> Element(Nil) {
  section([class("posts")], [
    div([class("header")], [
      h1([], [text("Posts")]),
      a([href("/posts/new"), class("btn")], [text("New Post")]),
    ]),
    ul(
      [class("post-list")],
      list.map(posts, fn(post) {
        li([], [
          a([href("/posts/" <> int.to_string(post.id))], [
            text(post.title),
          ]),
        ])
      }),
    ),
  ])
}

pub fn show_view(post: Post) -> Element(Nil) {
  section([class("post")], [
    h1([], [text(post.title)]),
    div([class("post-body")], [text(post.body)]),
    div([class("actions")], [
      a([href("/posts/" <> int.to_string(post.id) <> "/edit"), class("btn")], [
        text("Edit"),
      ]),
    ]),
  ])
}

pub fn form_view(
  values: post_form.PostForm,
  errors: List(#(String, String)),
) -> Element(Nil) {
  let post_action = case values.id {
    Some(id) -> "/posts/" <> int.to_string(id)
    None -> "/posts"
  }

  let post_method = case values.id {
    Some(_) -> "put"
    None -> "post"
  }

  section([class("post-form")], [
    h1([], [text(case values.id {
      Some(_) -> "Edit Post"
      None -> "New Post"
    })]),
    form([action(post_action), method("post")], [
      case post_method {
        "put" -> input([type_("hidden"), name("_method"), value("put")])
        _ -> text("")
      },
      div([class("field")], [
        label([], [text("Title")]),
        input([type_("text"), name("title"), value(values.title)]),
        field_error(errors, "title"),
      ]),
      div([class("field")], [
        label([], [text("Body")]),
        textarea([name("body")], values.body),
        field_error(errors, "body"),
      ]),
      div([class("field")], [
        label([], [
          input([
            type_("checkbox"),
            name("published"),
            ..case values.published {
              True -> [attribute.checked()]
              False -> []
            }
          ]),
          text(" Published"),
        ]),
      ]),
      button([type_("submit"), class("btn")], [text("Save")]),
    ]),
  ])
}

fn field_error(errors: List(#(String, String)), field: String) -> Element(Nil) {
  case list.find(errors, fn(e) { e.0 == field }) {
    Ok(#(_, message)) -> p([class("error")], [text(message)])
    Error(_) -> text("")
  }
}
```

### Form decoder: `src/my_app/web/forms/post_form.gleam`

This is where validation lives. Plain functions, typed results.

```gleam
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import my_app/domain/post.{type Post}
import wisp

pub type PostForm {
  PostForm(id: Option(Int), title: String, body: String, published: Bool)
}

pub type PostParams {
  PostParams(title: String, body: String, published: Bool)
}

pub fn empty() -> PostForm {
  PostForm(id: None, title: "", body: "", published: False)
}

pub fn from_post(post: Post) -> PostForm {
  PostForm(
    id: Some(post.id),
    title: post.title,
    body: post.body,
    published: post.published,
  )
}

pub fn from_form_data(data: wisp.FormData) -> PostForm {
  PostForm(
    id: None,
    title: get_value(data, "title"),
    body: get_value(data, "body"),
    published: list.any(data.values, fn(v) { v.0 == "published" }),
  )
}

pub fn decode(
  data: wisp.FormData,
) -> Result(PostParams, List(#(String, String))) {
  let title = get_value(data, "title")
  let body = get_value(data, "body")
  let published = list.any(data.values, fn(v) { v.0 == "published" })

  let errors =
    []
    |> validate_required(title, "title", "Title is required")
    |> validate_min_length(title, "title", 3, "Title must be at least 3 characters")
    |> validate_required(body, "body", "Body is required")

  case errors {
    [] -> Ok(PostParams(title: title, body: body, published: published))
    _ -> Error(errors)
  }
}

fn get_value(data: wisp.FormData, key: String) -> String {
  list.find(data.values, fn(v) { v.0 == key })
  |> result.map(fn(v) { v.1 })
  |> result.unwrap("")
}

fn validate_required(
  errors: List(#(String, String)),
  value: String,
  field: String,
  message: String,
) -> List(#(String, String)) {
  case string.is_empty(string.trim(value)) {
    True -> [#(field, message), ..errors]
    False -> errors
  }
}

fn validate_min_length(
  errors: List(#(String, String)),
  value: String,
  field: String,
  min: Int,
  message: String,
) -> List(#(String, String)) {
  case string.length(string.trim(value)) < min {
    True ->
      case list.any(errors, fn(e) { e.0 == field }) {
        True -> errors
        False -> [#(field, message), ..errors]
      }
    False -> errors
  }
}
```

### Domain type: `src/my_app/domain/post.gleam`

```gleam
pub type Post {
  Post(id: Int, title: String, body: String, published: Bool)
}
```

Clean. No framework imports. This is your code.

### Repo: `src/my_app/data/post_repo.gleam`

For Postgres (via Pog):

```gleam
import gleam/dynamic/decode
import gleam/result
import my_app/domain/post.{type Post, Post}
import my_app/web/forms/post_form.{type PostParams}
import pog

fn post_decoder() -> decode.Decoder(Post) {
  use id <- decode.field(0, decode.int)
  use title <- decode.field(1, decode.string)
  use body <- decode.field(2, decode.string)
  use published <- decode.field(3, decode.bool)
  decode.success(Post(id: id, title: title, body: body, published: published))
}

pub fn list(db: pog.Connection) -> List(Post) {
  pog.query("SELECT id, title, body, published FROM posts ORDER BY id DESC")
  |> pog.returning(post_decoder())
  |> pog.execute(db)
  |> result.map(fn(r) { r.rows })
  |> result.unwrap([])
}

pub fn get(db: pog.Connection, id: Int) -> Result(Post, Nil) {
  pog.query("SELECT id, title, body, published FROM posts WHERE id = $1")
  |> pog.parameter(pog.int(id))
  |> pog.returning(post_decoder())
  |> pog.execute(db)
  |> result.then(fn(r) {
    case r.rows {
      [post] -> Ok(post)
      _ -> Error(Nil)
    }
  })
  |> result.replace_error(Nil)
}

pub fn create(db: pog.Connection, params: PostParams) -> Result(Post, Nil) {
  pog.query(
    "INSERT INTO posts (title, body, published)
     VALUES ($1, $2, $3)
     RETURNING id, title, body, published",
  )
  |> pog.parameter(pog.text(params.title))
  |> pog.parameter(pog.text(params.body))
  |> pog.parameter(pog.bool(params.published))
  |> pog.returning(post_decoder())
  |> pog.execute(db)
  |> result.then(fn(r) {
    case r.rows {
      [post] -> Ok(post)
      _ -> Error(Nil)
    }
  })
  |> result.replace_error(Nil)
}

pub fn update(
  db: pog.Connection,
  id: Int,
  params: PostParams,
) -> Result(Post, Nil) {
  pog.query(
    "UPDATE posts SET title = $1, body = $2, published = $3
     WHERE id = $4
     RETURNING id, title, body, published",
  )
  |> pog.parameter(pog.text(params.title))
  |> pog.parameter(pog.text(params.body))
  |> pog.parameter(pog.bool(params.published))
  |> pog.parameter(pog.int(id))
  |> pog.returning(post_decoder())
  |> pog.execute(db)
  |> result.then(fn(r) {
    case r.rows {
      [post] -> Ok(post)
      _ -> Error(Nil)
    }
  })
  |> result.replace_error(Nil)
}

pub fn delete(db: pog.Connection, id: Int) -> Result(Nil, Nil) {
  pog.query("DELETE FROM posts WHERE id = $1")
  |> pog.parameter(pog.int(id))
  |> pog.execute(db)
  |> result.replace(Nil)
  |> result.replace_error(Nil)
}
```

### Layout: `src/my_app/web/layouts/root_layout.gleam`

```gleam
import lustre/attribute.{charset, class, content, href, name, rel}
import lustre/element.{type Element, text}
import lustre/element/html.{
  body, head, html, link, main, meta, title,
}

pub fn wrap(content inner: Element(Nil), title page_title: String) -> String {
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

### Error handler: `src/my_app/web/error_handler.gleam`

```gleam
import lustre/attribute.{class}
import lustre/element.{text}
import lustre/element/html.{h1, p, section}
import my_app/web/layouts/root_layout
import wisp.{type Request, type Response}

pub fn not_found(_req: Request) -> Response {
  section([class("error-page")], [
    h1([], [text("404")]),
    p([], [text("Page not found.")]),
  ])
  |> root_layout.wrap("Not Found")
  |> wisp.html_response(404)
}

pub fn internal_error(_req: Request) -> Response {
  section([class("error-page")], [
    h1([], [text("500")]),
    p([], [text("Something went wrong.")]),
  ])
  |> root_layout.wrap("Error")
  |> wisp.html_response(500)
}
```

### Migration: `src/my_app/data/migrations/001_create_posts.sql`

```sql
CREATE TABLE posts (
  id SERIAL PRIMARY KEY,
  title TEXT NOT NULL,
  body TEXT NOT NULL,
  published BOOLEAN NOT NULL DEFAULT FALSE,
  inserted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

### Test: `test/my_app/web/post_handler_test.gleam`

```gleam
import gleeunit/should
import my_app/web/forms/post_form

pub fn decode_valid_form_test() {
  let data = wisp.FormData(
    values: [
      #("title", "Hello World"),
      #("body", "This is my first post"),
      #("published", "on"),
    ],
    files: [],
  )

  post_form.decode(data)
  |> should.be_ok
  |> fn(params) {
    should.equal(params.title, "Hello World")
    should.equal(params.body, "This is my first post")
    should.equal(params.published, True)
  }
}

pub fn decode_missing_title_test() {
  let data = wisp.FormData(
    values: [#("body", "Some body")],
    files: [],
  )

  post_form.decode(data)
  |> should.be_error
}
```

---

## Project layout — summary

```
my_app/
  gleam.toml
  src/
    my_app.gleam                        ← entry point
    my_app/
      config.gleam                      ← typed config
      router.gleam                      ← all routes, pattern matched

      web/                              ← HTTP/UI layer
        home_handler.gleam
        error_handler.gleam
        post_handler.gleam              ← generated
        post_views.gleam                ← generated
        forms/
          post_form.gleam               ← generated
        layouts/
          root_layout.gleam
        components/
          flash.gleam
        middleware/                     ← auth, rate-limit, etc.

      domain/                           ← business logic (no framework imports)
        post.gleam                      ← generated

      data/                             ← persistence
        repo.gleam                      ← DB connection setup
        post_repo.gleam                 ← generated
        migrations/
          001_create_posts.sql          ← generated

  priv/
    static/
      css/app.css
      js/app.js

  test/
    my_app_test.gleam
    my_app/web/
      home_handler_test.gleam
      post_handler_test.gleam           ← generated
```

---

## Architectural rules

1. `web/` handles HTTP concerns. Handlers receive requests, return responses.
   Views produce `Element(Nil)`. Forms decode and validate input.

2. `domain/` is pure Gleam. No wisp imports, no database imports.
   These types and functions are your business logic.

3. `data/` talks to the database. Repo modules take a connection and
   return domain types. Raw SQL, no ORM.

4. Dependencies flow inward: `web/ → domain/`, `data/ → domain/`.
   Never `domain/ → web/` or `domain/ → data/`.

5. The router is the source of truth for all routes. One file.
   Pattern matching, not registration.

6. Layouts are functions that wrap `Element(Nil) → String`.
   No inheritance, no `yield` blocks.

7. Generated code follows the exact same patterns as hand-written code.
   There is no "framework code" vs "your code" distinction.

---

## What the framework actually provides (as a library)

The `refrakt` package itself is small. It provides:

1. **Validation helpers** — `required`, `min_length`, `max_length`, `format`,
   `inclusion`, `numericality`. Composable, return `List(#(String, String))`.

2. **Flash messages** — `set_flash(response, req, key, message)`,
   `get_flash(req, key)`. Built on signed cookies.

3. **Router helpers** — `resource_routes(name)` returns the list of
   path/method pairs for `refrakt routes` to print.

4. **Migration runner** — reads `*.sql` files from the migrations directory,
   tracks applied migrations in a `_migrations` table, runs pending ones
   in order.

5. **Test helpers** — `test_request(method, path)`, `test_request_with_form`,
   `test_request_with_json` for building test requests without a running
   server.

6. **Dev error page** — rich HTML error page shown in dev mode with the
   error message, stack trace, and request details.

Everything else is generated into the user's project as plain Gleam code.

---

## What the CLI provides (as a separate tool)

The `refrakt` CLI is a code generator. It:

1. Reads `gleam.toml` to find the project name.
2. Uses string templates to generate `.gleam` and `.sql` files.
3. Patches `router.gleam` to add new routes (by finding the catch-all
   pattern and inserting before it).
4. Patches `gleam.toml` to add dependencies when needed.

It does not run at runtime. It does not do metaprogramming.
It is a development tool that produces plain Gleam code.

The CLI can be written in Gleam (targeting Erlang) or Rust.
Gleam-in-Gleam is preferred for dogfooding and community trust.

---

## Dependencies for a generated project

```toml
[dependencies]
gleam_stdlib = ">= 0.44.0 and < 2.0.0"
gleam_erlang = ">= 0.34.0 and < 2.0.0"
gleam_http = ">= 4.3.0 and < 5.0.0"
mist = ">= 5.0.0 and < 6.0.0"
wisp = ">= 2.2.0 and < 3.0.0"
lustre = ">= 5.6.0 and < 6.0.0"
# if --db postgres:
pog = ">= 4.1.0 and < 5.0.0"
# if --db sqlite:
sqlight = ">= 1.0.0 and < 2.0.0"

[dev-dependencies]
gleeunit = ">= 1.0.0 and < 2.0.0"
```

---

## Non-goals for Phase 0 / MVP

- WebSocket / real-time (Phase 2+)
- Lustre server components (Phase 2+)
- File watching / hot reload (Phase 3)
- Asset pipeline / bundling
- Email / background jobs
- Multi-database support
- API-only mode (JSON) — easy to add later, not the default path
- JavaScript target — BEAM only for now
