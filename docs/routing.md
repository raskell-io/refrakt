# Routing

Refrakt uses Gleam pattern matching for routing. All routes live in
one file: `src/<app>/router.gleam`.

## How it works

The router pattern matches on two things: the URL path segments and
the HTTP method.

```gleam
pub fn handle_request(req: Request, ctx: Context) -> Response {
  use req <- middleware(req)

  case wisp.path_segments(req), req.method {
    [], http.Get -> home_handler.index(req, ctx)
    ["posts"], http.Get -> post_handler.index(req, ctx)
    ["posts", id], http.Get -> post_handler.show(req, ctx, id)
    _, _ -> error_handler.not_found(req)
  }
}
```

`wisp.path_segments(req)` splits the URL path into a list of strings:
- `/` → `[]`
- `/posts` → `["posts"]`
- `/posts/42` → `["posts", "42"]`
- `/posts/42/edit` → `["posts", "42", "edit"]`

## Route parameters

Variables in the pattern become handler arguments:

```gleam
// /posts/42 → id = "42"
["posts", id], http.Get -> post_handler.show(req, ctx, id)

// /posts/42/edit → id = "42"
["posts", id, "edit"], http.Get -> post_handler.edit(req, ctx, id)
```

Route parameters are always strings. Parse them in the handler:

```gleam
pub fn show(req: Request, ctx: Context, id: String) -> Response {
  case int.parse(id) {
    Error(_) -> error_handler.not_found(req)
    Ok(id) -> // ... use the integer id
  }
}
```

## RESTful resource routes

`refrakt gen resource posts ...` adds these routes:

```gleam
["posts"], http.Get -> post_handler.index(req, ctx)
["posts", "new"], http.Get -> post_handler.new(req, ctx)
["posts"], http.Post -> post_handler.create(req, ctx)
["posts", id], http.Get -> post_handler.show(req, ctx, id)
["posts", id, "edit"], http.Get -> post_handler.edit(req, ctx, id)
["posts", id], http.Put -> post_handler.update(req, ctx, id)
["posts", id], http.Delete -> post_handler.delete(req, ctx, id)
```

Note: `["posts", "new"]` comes before `["posts", id]` so the literal
`"new"` matches first and doesn't get captured as an id.

## Method override

HTML forms only support GET and POST. To send PUT and DELETE, Refrakt
uses method override — a hidden form field `_method`:

```html
<form method="post" action="/posts/42">
  <input type="hidden" name="_method" value="put">
  <!-- form fields -->
</form>
```

The middleware calls `wisp.method_override(req)` which reads `_method`
and changes the request method accordingly. This is already set up
in every generated project.

## Adding routes manually

Edit `router.gleam` and add a new pattern before the `_, _` catch-all:

```gleam
case wisp.path_segments(req), req.method {
  [], http.Get -> home_handler.index(req, ctx)
  ["dashboard"], http.Get -> dashboard_handler.index(req, ctx)  // new
  _, _ -> error_handler.not_found(req)
}
```

Don't forget to add the import at the top of the file.

## Middleware

Middleware runs before the route match. The default middleware stack:

```gleam
fn middleware(req: Request, next: fn(Request) -> Response) -> Response {
  let req = wisp.method_override(req)     // PUT/DELETE via _method
  use <- wisp.log_request(req)            // log method + path
  use <- wisp.rescue_crashes              // catch panics, return 500
  use <- wisp.serve_static(req,           // serve priv/static/*
    under: "/static",
    from: priv_static(),
  )
  next(req)
}
```

Add custom middleware by inserting `use` calls:

```gleam
fn middleware(req: Request, next: fn(Request) -> Response) -> Response {
  let req = wisp.method_override(req)
  use <- wisp.log_request(req)
  use <- wisp.rescue_crashes
  use <- wisp.serve_static(req, under: "/static", from: priv_static())
  use <- my_custom_middleware(req)          // your middleware
  next(req)
}
```

## Viewing all routes

```bash
refrakt routes
```

Output:

```
GET     /                   home_handler.index
GET     /posts              post_handler.index
GET     /posts/new          post_handler.new
POST    /posts              post_handler.create
GET     /posts/:id          post_handler.show
GET     /posts/:id/edit     post_handler.edit
PUT     /posts/:id          post_handler.update
DELETE  /posts/:id          post_handler.delete
```
