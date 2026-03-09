# Conventions

Naming, structure, and code patterns for generated code.

---

## File Naming

| Concept | File | Location |
|---------|------|----------|
| Handler | `post_handler.gleam` | `web/` |
| Views | `post_views.gleam` | `web/` |
| Form decoder | `post_form.gleam` | `web/forms/` |
| Domain type | `post.gleam` | `domain/` |
| Repo | `post_repo.gleam` | `data/` |
| Migration | `001_create_posts.sql` | `data/migrations/` |
| Layout | `root_layout.gleam` | `web/layouts/` |
| Component | `flash.gleam` | `web/components/` |
| Middleware | `auth.gleam` | `web/middleware/` |
| Test | `post_handler_test.gleam` | `test/<app>/web/` |

### Pluralization

- Resource names in CLI commands are **plural**: `refrakt gen resource posts`
- Generated files use **singular**: `post_handler.gleam`, `post.gleam`
- Routes use **plural**: `/posts`, `/posts/:id`
- Types use **singular**: `Post`, `PostForm`, `PostParams`

---

## Handler Signatures

```gleam
// No params
pub fn index(req: Request, ctx: Context) -> Response

// With route param (always String from path segment)
pub fn show(req: Request, ctx: Context, id: String) -> Response
```

Handlers always take `Request` first, `Context` second, then route params.

---

## View Signatures

```gleam
// List view
pub fn index_view(posts: List(Post)) -> Element(Nil)

// Single item view
pub fn show_view(post: Post) -> Element(Nil)

// Form view (takes form state + errors)
pub fn form_view(values: PostForm, errors: List(#(String, String))) -> Element(Nil)
```

Views return `Element(Nil)`. They never import wisp or return Response.

---

## Form Pattern

Every form has two types:

```gleam
// Display state — used to re-render the form with values
pub type PostForm {
  PostForm(id: Option(Int), title: String, body: String, published: Bool)
}

// Validated input — the clean data for domain/repo
pub type PostParams {
  PostParams(title: String, body: String, published: Bool)
}
```

And three constructors:

```gleam
pub fn empty() -> PostForm          // Blank form
pub fn from_post(post: Post) -> PostForm    // Edit form
pub fn from_form_data(data: FormData) -> PostForm  // Re-render after error
```

And a decoder:

```gleam
pub fn decode(data: FormData) -> Result(PostParams, List(#(String, String)))
```

---

## Repo Signatures

```gleam
pub fn list(db: Connection) -> List(Post)
pub fn get(db: Connection, id: Int) -> Result(Post, Nil)
pub fn create(db: Connection, params: PostParams) -> Result(Post, Nil)
pub fn update(db: Connection, id: Int, params: PostParams) -> Result(Post, Nil)
pub fn delete(db: Connection, id: Int) -> Result(Nil, Nil)
```

Repos take a database connection first, then params. Return domain types.

---

## Route Pattern

Routes in `router.gleam` follow RESTful conventions:

```gleam
case wisp.path_segments(req), req.method {
  ["posts"], http.Get -> post_handler.index(req, ctx)
  ["posts", "new"], http.Get -> post_handler.new(req, ctx)
  ["posts"], http.Post -> post_handler.create(req, ctx)
  ["posts", id], http.Get -> post_handler.show(req, ctx, id)
  ["posts", id, "edit"], http.Get -> post_handler.edit(req, ctx, id)
  ["posts", id], http.Put -> post_handler.update(req, ctx, id)
  ["posts", id], http.Delete -> post_handler.delete(req, ctx, id)
}
```

`/new` comes before `/:id` to avoid ambiguity.

---

## Layout Pattern

```gleam
pub fn wrap(content inner: Element(Nil), title page_title: String) -> String {
  html([], [
    head([], [ ... ]),
    body([], [ main([], [inner]) ]),
  ])
  |> element.to_document_string
}
```

Layouts are functions, not inheritance. A handler calls:

```gleam
post_views.index_view(posts)
|> root_layout.wrap("Posts")
|> wisp.html_response(200)
```

---

## Flash Messages

Set on redirect:
```gleam
wisp.redirect("/posts")
|> refrakt.set_flash(req, "info", "Post created")
```

Read in layout/component:
```gleam
let flash = refrakt.get_flash(req, "info")
```

---

## Field Types (CLI)

| CLI Type | Gleam Type | SQL Type (Postgres) | SQL Type (SQLite) |
|----------|-----------|--------------------|--------------------|
| `string` | `String` | `TEXT` | `TEXT` |
| `text` | `String` | `TEXT` | `TEXT` |
| `int` | `Int` | `INTEGER` | `INTEGER` |
| `float` | `Float` | `DOUBLE PRECISION` | `REAL` |
| `bool` | `Bool` | `BOOLEAN` | `INTEGER` |
| `date` | `String` | `DATE` | `TEXT` |
| `datetime` | `String` | `TIMESTAMPTZ` | `TEXT` |
| `optional(T)` | `Option(T)` | `T` (nullable) | `T` (nullable) |
