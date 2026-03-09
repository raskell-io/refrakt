# Gleam Coding Standards

> Gleam 1.14+, BEAM target

These standards apply to all Gleam code in Refrakt — both the framework
packages and the code generators produce.

---

## Error Handling

### Use `Result` for Recoverable Errors

```gleam
// GOOD: Explicit Result
pub fn get(db: pog.Connection, id: Int) -> Result(Post, Nil) {
  // ...
}

// BAD: let assert in library code
pub fn get(db: pog.Connection, id: Int) -> Post {
  let assert Ok(post) = // ...
}
```

### `let assert` Only in Entry Points and Tests

`let assert Ok(...)` is acceptable in:
- `main()` for server startup
- Test functions
- Nowhere else

### Return Specific Error Types

```gleam
// GOOD: Callers know what went wrong
pub type FormError {
  FieldError(field: String, message: String)
}

pub fn decode(data: FormData) -> Result(Params, List(FormError))

// BAD: Opaque error
pub fn decode(data: FormData) -> Result(Params, Nil)
```

---

## Type Design

### Custom Types for Domain Concepts

```gleam
// GOOD: Distinct types
pub type Post {
  Post(id: Int, title: String, body: String, published: Bool)
}

pub type PostParams {
  PostParams(title: String, body: String, published: Bool)
}
```

### Enums Over Booleans

```gleam
// GOOD
pub type Env {
  Dev
  Test
  Prod
}

// BAD
fn is_production(env: String) -> Bool
```

### Use `Option` for Nullable Fields

```gleam
pub type PostForm {
  PostForm(id: Option(Int), title: String, body: String)
}
```

---

## Functions

### Use Labelled Arguments for Clarity

```gleam
// GOOD: Clear at the call site
pub fn wrap(content inner: Element(Nil), title page_title: String) -> String

// Usage: root_layout.wrap(content: view, title: "Posts")
```

### Use `use` for Callbacks (Wisp Pattern)

```gleam
// GOOD: Wisp middleware style
pub fn handle_request(req: Request, ctx: Context) -> Response {
  use req <- middleware(req)
  // ...
}

// GOOD: Body reading
pub fn create(req: Request, ctx: Context) -> Response {
  use form_data <- wisp.require_form(req)
  // ...
}
```

### Keep Functions Small

A handler function should do one thing:
1. Parse input
2. Call domain/data logic
3. Render response

If a handler is getting long, extract a domain function.

---

## Module Organization

### One Public Type Per Domain Module

```gleam
// src/my_app/domain/post.gleam
pub type Post {
  Post(id: Int, title: String, body: String, published: Bool)
}

// Domain functions operate on the type
pub fn is_published(post: Post) -> Bool {
  post.published
}
```

### Import Style

```gleam
// Stdlib first, then external packages, then internal modules
import gleam/int
import gleam/list
import gleam/result

import lustre/element.{type Element, text}
import wisp.{type Request, type Response}

import my_app/domain/post.{type Post}
import my_app/router.{type Context}
```

---

## Views / HTML

### Views Return `Element(Nil)`

```gleam
pub fn index_view(posts: List(Post)) -> Element(Nil) {
  section([class("posts")], [
    h1([], [text("Posts")]),
    // ...
  ])
}
```

### Extract Reusable Components

```gleam
// GOOD: Reusable across views
fn field_error(errors: List(#(String, String)), field: String) -> Element(Nil) {
  case list.find(errors, fn(e) { e.0 == field }) {
    Ok(#(_, message)) -> p([class("error")], [text(message)])
    Error(_) -> text("")
  }
}
```

---

## Testing

### Test Naming

```gleam
pub fn decode_valid_form_test() { }
pub fn decode_missing_title_returns_error_test() { }
pub fn index_returns_200_test() { }
```

### Test Structure: Arrange / Act / Assert

```gleam
pub fn decode_valid_form_test() {
  // Arrange
  let data = wisp.FormData(
    values: [#("title", "Hello"), #("body", "World")],
    files: [],
  )

  // Act
  let result = post_form.decode(data)

  // Assert
  result |> should.be_ok
}
```

---

## Formatting

### Run Before Committing

```bash
gleam format
gleam build
gleam test
```

### Let the Formatter Win

Never fight `gleam format`. If the output looks odd, restructure the code
rather than trying to work around the formatter.
