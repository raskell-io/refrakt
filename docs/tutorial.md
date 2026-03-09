# Build a Blog with Refrakt

This tutorial walks you through building a blog application from scratch.
By the end, you'll have posts with CRUD, user authentication, and an
about page — all running on Gleam.

**Prerequisites:**
- Gleam 1.14+ and Erlang/OTP 27+
- PostgreSQL running locally
- `refrakt` published on Hex (or use a path dependency for now)

**Time:** ~10 minutes

---

## 1. Create the project

```bash
refrakt new blog --db postgres
cd blog
```

This creates a complete project structure:

```
blog/
  src/
    blog.gleam                    ← entry point
    blog/
      config.gleam                ← reads PORT, SECRET_KEY_BASE, APP_ENV
      context.gleam               ← shared Context type
      router.gleam                ← all routes, pattern matched
      web/
        home_handler.gleam        ← GET /
        error_handler.gleam       ← 404, 500
        layouts/root_layout.gleam ← HTML shell
        components/flash.gleam    ← flash message component
      data/
        repo.gleam                ← database connection
  priv/static/                    ← CSS, JS
  test/
```

Verify it works:

```bash
gleam build
gleam test
```

## 2. Create the database

```bash
createdb blog_dev
```

The generated `repo.gleam` connects to `postgres://localhost:5432/blog_dev`
by default. No configuration needed for local development.

## 3. Generate a posts resource

```bash
refrakt gen resource posts title:string body:text published:bool
```

This creates 7 files and patches the router:

| File | Purpose |
|------|---------|
| `web/post_handler.gleam` | 7 handler functions (index, show, new, create, edit, update, delete) |
| `web/post_views.gleam` | Lustre HTML views (list, detail, form) |
| `web/forms/post_form.gleam` | Typed form decoder with validation |
| `domain/post.gleam` | `Post` type — pure Gleam, no framework imports |
| `data/post_repo.gleam` | Raw SQL queries via Pog with typed decoders |
| `data/migrations/001_create_posts.sql` | Database table definition |
| `test/.../post_handler_test.gleam` | Form decode tests |

Look at the router — it now has RESTful routes:

```bash
refrakt routes
```

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

## 4. Run the migration

```bash
psql blog_dev < src/blog/data/migrations/001_create_posts.sql
```

## 5. Start the server

```bash
gleam run
```

Visit http://localhost:4000/posts — you'll see the posts index.
Click "New Post" to create one.

## 6. Look at the generated code

Open `src/blog/router.gleam`:

```gleam
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
```

That's plain Gleam pattern matching. No DSL, no macros. You can read
every route in 10 seconds.

Open `src/blog/domain/post.gleam`:

```gleam
pub type Post {
  Post(id: Int, title: String, body: String, published: Bool)
}
```

No framework imports. This is your domain type. You own it.

Open `src/blog/web/forms/post_form.gleam`:

```gleam
pub fn decode(
  data: wisp.FormData,
) -> Result(PostParams, List(#(String, String))) {
  let title = get_value(data, "title")
  let body = get_value(data, "body")

  let errors =
    []
    |> validate.required(title, "title", "Title is required")
    |> validate.required(body, "body", "Body is required")

  case errors {
    [] -> Ok(PostParams(title: title, body: body, published: ...))
    _ -> Error(errors)
  }
}
```

Validation is composable functions. Errors are `List(#(String, String))`.
No framework magic.

## 7. Add authentication

```bash
refrakt gen auth
```

This generates a complete auth system:

| File | Purpose |
|------|---------|
| `web/auth_handler.gleam` | Login, register, logout handlers |
| `web/auth_views.gleam` | Login and register forms |
| `web/forms/auth_form.gleam` | Credential validation |
| `web/middleware/auth.gleam` | `require_auth` middleware |
| `domain/user.gleam` | User type |
| `domain/auth.gleam` | Password hashing |
| `data/user_repo.gleam` | User queries |
| `data/migrations/002_create_users.sql` | Users table |

Run the migration:

```bash
psql blog_dev < src/blog/data/migrations/002_create_users.sql
```

Check the routes:

```bash
refrakt routes
```

New auth routes appear:

```
GET     /login              auth_handler.login_page
POST    /login              auth_handler.login
GET     /register           auth_handler.register_page
POST    /register           auth_handler.register
POST    /logout             auth_handler.logout
```

## 8. Protect a route

Open `src/blog/web/post_handler.gleam` and add auth to the create action:

```gleam
import blog/web/middleware/auth

pub fn create(req: Request, ctx: Context) -> Response {
  use _user <- auth.require_auth(req, ctx)
  use form_data <- wisp.require_form(req)
  // ... rest of create logic
}
```

Now only logged-in users can create posts. The `require_auth` middleware
redirects to `/login` if there's no session.

## 9. Add a page

```bash
refrakt gen page about
```

This creates a handler and patches the router. Edit
`src/blog/web/about_handler.gleam` to add your content:

```gleam
pub fn index(_req: Request, _ctx: Context) -> Response {
  section([class("about")], [
    h1([], [text("About This Blog")]),
    p([], [text("Built with Refrakt and Gleam.")]),
  ])
  |> root_layout.wrap("About")
  |> wisp.html_response(200)
}
```

## 10. Run the tests

```bash
gleam test
```

The generated tests verify your form decoders work:
- Empty form has no ID
- Valid form data decodes successfully
- Missing required fields return errors
- Password hashing works correctly

---

## What you have now

A complete blog with:
- **7 post routes** — full CRUD with forms and validation
- **5 auth routes** — registration, login, logout
- **1 page route** — about page
- **Raw SQL** — readable, debuggable, no ORM
- **Typed forms** — validation with clear error messages
- **Lustre views** — type-safe HTML, no template language
- **Tests** — form decoders and auth logic covered

Every file is plain Gleam code you own and can modify.
There is no "framework code" vs "your code" distinction.

## Next steps

- Edit the CSS in `priv/static/css/app.css`
- Add more fields to posts (edit `domain/post.gleam` and the repo)
- Add comments as a second resource: `refrakt gen resource comments ...`
- Deploy with [Vela](https://github.com/raskell-io/vela) or `gleam export erlang-shipment`

---

## Project structure reference

```
blog/
  src/
    blog.gleam                          ← entry point
    blog/
      config.gleam                      ← typed config
      context.gleam                     ← shared Context type
      router.gleam                      ← all routes

      web/                              ← HTTP/UI layer
        home_handler.gleam
        post_handler.gleam              ← generated CRUD
        post_views.gleam                ← Lustre HTML views
        auth_handler.gleam              ← generated auth
        auth_views.gleam
        about_handler.gleam             ← generated page
        error_handler.gleam
        forms/
          post_form.gleam               ← typed decoder + validation
          auth_form.gleam
        layouts/
          root_layout.gleam             ← HTML shell
        components/
          flash.gleam
        middleware/
          auth.gleam                    ← require_auth

      domain/                           ← pure Gleam types
        post.gleam
        user.gleam
        auth.gleam

      data/                             ← database layer
        repo.gleam                      ← connection setup
        post_repo.gleam                 ← SQL queries
        user_repo.gleam
        migrations/
          001_create_posts.sql
          002_create_users.sql

  priv/static/
    css/app.css
    js/app.js

  test/
    blog_test.gleam
    blog/web/
      post_handler_test.gleam
      auth_handler_test.gleam
```
