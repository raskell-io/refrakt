# Handlers

Handlers are functions that receive an HTTP request and return a
response. They live in `src/<app>/web/`.

## Handler signature

```gleam
pub fn index(req: Request, ctx: Context) -> Response
```

Every handler takes:
1. `req: Request` — the HTTP request (from Wisp)
2. `ctx: Context` — shared context (config, database connection)
3. Optional route parameters as `String` arguments

```gleam
// No params
pub fn index(req: Request, ctx: Context) -> Response

// With route param
pub fn show(req: Request, ctx: Context, id: String) -> Response
```

## Returning responses

Use Wisp's response helpers:

```gleam
import wisp

// HTML response
wisp.html_response(html_string, 200)

// Redirect
wisp.redirect("/posts")

// Status codes
wisp.ok()              // 200, empty body
wisp.created()         // 201
wisp.no_content()      // 204
wisp.not_found()       // 404
wisp.bad_request()     // 400
```

### HTML with a layout

The standard pattern: build a Lustre element, wrap in a layout,
return as HTML:

```gleam
pub fn index(req: Request, ctx: Context) -> Response {
  post_views.index_view(posts)       // Element(Nil)
  |> root_layout.wrap("Posts")       // String (full HTML document)
  |> wisp.html_response(200)         // Response
}
```

### JSON responses

```gleam
import gleam/json

pub fn api_index(req: Request, ctx: Context) -> Response {
  let body = json.array(posts, fn(p) {
    json.object([
      #("id", json.int(p.id)),
      #("title", json.string(p.title)),
    ])
  })
  |> json.to_string

  wisp.json_response(body, 200)
}
```

`refrakt gen resource posts ... --api` generates a complete JSON
handler in this style. Its `create` decodes and validates the body with
the generated params module, then answers 201 with the record and a
`Location` header, 422 with `{"errors": {field: message}}`, or 400 when
the body has the wrong shape:

```gleam
pub fn create(req: Request, ctx: Context) -> Response {
  use body <- wisp.require_json(req)

  case post_form.decode_json(body) {
    Error(error) -> invalid_body(error)
    Ok(params) ->
      case post_repo.create(ctx.db, params) {
        Ok(item) ->
          json_response(to_json(item), 201)
          |> response.set_header(
            "location",
            "/api/posts/" <> int.to_string(item.id),
          )
        Error(_) -> internal_error()
      }
  }
}
```

`update` answers 200 with the record, `delete` 204 with no body, and
`show`, `update` and `delete` answer 404 `{"error": "not found"}` for an
unknown id. See [CLI](cli.md#refrakt-gen-resource-name-fields) for the
full table.

## Reading request data

### Form data

```gleam
pub fn create(req: Request, ctx: Context) -> Response {
  use form_data <- wisp.require_form(req)
  // form_data.values: List(#(String, String))
  // form_data.files: List(UploadedFile)
}
```

### JSON body

```gleam
pub fn create(req: Request, ctx: Context) -> Response {
  use json <- wisp.require_json(req)
  // json: Dynamic — decode it with gleam/dynamic/decode
}
```

`wisp.require_json` answers 415 unless the content type is
`application/json` and 400 when the body is not valid JSON. An `--api`
resource's params module decodes the `Dynamic` for you:

```gleam
// web/forms/post_form.gleam (generated with --api)
pub fn decode_json(data: Dynamic) -> Result(PostParams, JsonError)

pub fn decoder() -> decode.Decoder(PostParams) {
  use title <- decode.optional_field("title", "", decode.string)
  use body <- decode.optional_field("body", "", decode.string)
  decode.success(PostParams(title:, body:))
}

pub fn validate_params(params: PostParams) -> List(#(String, String)) {
  []
  |> validate.required(params.title, "title", "Title is required")
  |> validate.required(params.body, "body", "Body is required")
}
```

`JsonError` is `MalformedBody(List(decode.DecodeError))` (answer 400)
or `InvalidParams(List(#(String, String)))` (answer 422).

### Query parameters

```gleam
import gleam/http/request

pub fn search(req: Request, ctx: Context) -> Response {
  let query = request.get_query(req)
  // query: Result(List(#(String, String)), Nil)
}
```

## Flash messages

Set a flash message on redirect:

```gleam
import refrakt/flash

pub fn create(req: Request, ctx: Context) -> Response {
  // ... create the post ...
  wisp.redirect("/posts")
  |> flash.set_flash(req, "info", "Post created")
}
```

Read a flash in a handler or view:

```gleam
let message = flash.get_flash(req, "info")
// Result(String, Nil)
```

## Cookies

```gleam
// Set a cookie (signed, expires in 1 hour)
wisp.set_cookie(response, req, "key", "value", wisp.Signed, 3600)

// Read a cookie
wisp.get_cookie(req, "key", wisp.Signed)
// Result(String, Nil)
```

## Error handling

The generated `error_handler.gleam` provides `not_found` and
`internal_error`. Use them in handlers when things go wrong:

```gleam
pub fn show(req: Request, ctx: Context, id: String) -> Response {
  case int.parse(id) {
    Error(_) -> error_handler.not_found(req)
    Ok(id) ->
      case post_repo.get(ctx.db, id) {
        Error(_) -> error_handler.not_found(req)
        Ok(post) -> // ... render the post
      }
  }
}
```

## Writing a handler from scratch

1. Create `src/<app>/web/dashboard_handler.gleam`
2. Write the handler function
3. Add the route to `router.gleam`
4. Add the import to `router.gleam`

```gleam
// src/my_app/web/dashboard_handler.gleam
import my_app/context.{type Context}
import my_app/web/layouts/root_layout
import lustre/element.{text}
import lustre/element/html.{h1, section}
import wisp.{type Request, type Response}

pub fn index(_req: Request, _ctx: Context) -> Response {
  section([], [h1([], [text("Dashboard")])])
  |> root_layout.wrap("Dashboard")
  |> wisp.html_response(200)
}
```

Or use the generator:

```bash
refrakt gen page dashboard
```
