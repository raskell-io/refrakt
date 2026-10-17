# Routing

Refrakt uses Gleam pattern matching for routing. All routes live in
one file: `src/<app>/router.gleam`.

## How it works

The router pattern matches on two things: the URL path segments and
the HTTP method.

```gleam
pub fn handle_request(req: Request, ctx: Context) -> Response {
  use req <- middleware(req, ctx)

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
uses method override — a POST with a `_method` query parameter:

```html
<form method="post" action="/posts/42?_method=PUT">
  <!-- form fields -->
</form>

<form method="post" action="/posts/42?_method=DELETE">
  <button type="submit">Delete</button>
</form>
```

The middleware calls `wisp.method_override(req)`, which reads `_method`
from the query string of a POST request (not from the form body) and
changes the request method accordingly. This is already set up in every
generated project, and generated edit forms and delete buttons use it.

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
fn middleware(
  req: Request,
  ctx: Context,
  next: fn(Request) -> Response,
) -> Response {
  let req = wisp.method_override(req)     // PUT/DELETE via _method
  use <- wisp.log_request(req)            // log method + path
  use <- rescue_crashes(req, ctx)         // catch panics, return 500
  use req <- csrf.protect(req)            // 403 for cross-site posts
  use <- wisp.serve_static(req,           // serve priv/static/*
    under: "/static",
    from: priv_static(),
  )
  next(req)
}

fn rescue_crashes(
  req: Request,
  ctx: Context,
  next: fn() -> Response,
) -> Response {
  case ctx.config.env {
    config.Dev -> dev_error.rescue(req, next)
    config.Test | config.Prod -> wisp.rescue_crashes(next)
  }
}
```

When `APP_ENV` is `dev` (the default, and what `refrakt dev` sets), a
crash renders the detailed error page from `refrakt/dev_error`: the
error, a stack trace and the request headers. With `APP_ENV=test` or
`APP_ENV=prod` the crash is logged and the visitor gets a plain
`500 Internal server error`, so internals never leak in production.

### CSRF protection

`csrf.protect` (from `refrakt/csrf`) stops cross-site request forgery:
another site's page submitting a form to your app with your visitor's
cookies. GET, HEAD, OPTIONS and TRACE requests pass untouched (keep
them free of side effects). For POST, PUT, PATCH and DELETE it asks the
browser where the request came from:

1. `Sec-Fetch-Site`: `same-origin` passes; `cross-site` and
   `same-site` (a sibling subdomain) get `403 Forbidden`. All current
   browsers send it over HTTPS and to localhost.
2. Otherwise `Origin`, then `Referer`: they must name the host and port
   in the request's `Host` header, or the request gets 403.
3. A request with none of these headers did not come from a browser
   page (curl, a webhook, a mobile app) or from a very old browser. It
   goes ahead with its `cookie` header removed, so it can never act as
   a signed-in user.

Browsers set these headers themselves and pages cannot forge them, so
your forms need no hidden token field and handlers need no CSRF code.
It is the approach of Go's `http.CrossOriginProtection` and of Wisp's
`csrf_known_header_protection` (which `refrakt/csrf` extends with
`Sec-Fetch-Site` and a 403 instead of a 400). Session cookies are also
`SameSite=Lax`, a second layer: browsers leave them off other sites'
form posts.

Limits to know about:

- **Reverse proxies** must pass the original `Host` header (nginx:
  `proxy_set_header Host $host;`; Caddy and Fly.io do by default).
  Browsers on plain HTTP send no `Sec-Fetch-Site`, and the `Origin`
  check compares against `Host`.
- **Cross-origin APIs:** a JSON API meant to be called from other sites'
  JavaScript (with `refrakt/cors`) would get 403s. Match those paths
  before `csrf.protect` in the middleware, and authenticate them with a
  token header rather than cookies. Server-to-server and curl clients
  send no `Origin` and are not affected.
- **GET with side effects** is never checked: a link or an image on
  another site can trigger it. Use POST (or `_method`) for anything
  that changes state.

In tests, `wisp/simulate.browser_request` sends a matching `Origin`,
and `simulate.header(req, "origin", "https://evil.example")` simulates
a cross-site post. The generated `test/<app>/router_test.gleam` checks
both. For `refrakt/testing` requests use `testing.same_origin` and
`testing.cross_site`.

Add custom middleware by inserting `use` calls:

```gleam
fn middleware(
  req: Request,
  ctx: Context,
  next: fn(Request) -> Response,
) -> Response {
  let req = wisp.method_override(req)
  use <- wisp.log_request(req)
  use <- rescue_crashes(req, ctx)
  use req <- csrf.protect(req)
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
