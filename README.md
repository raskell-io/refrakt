# Refrakt

A convention-first web framework for Gleam. Productive like Phoenix, explicit like Gleam, composable with Wisp and Lustre.

---

Light enters a prism, structure emerges. Refrakt takes the Gleam ecosystem — Wisp, Lustre, Mist — and gives you one obvious way to build serious web apps. No macros. No magic. Just conventions, generators, and plain Gleam code you own.

## What It Does

```bash
# Create a new project
refrakt new my_app --db postgres

# Generate a full CRUD resource
cd my_app
refrakt gen resource posts title:string body:text published:bool

# Run it
gleam run
# → http://localhost:4000/posts
```

That one `gen resource` command creates a handler, views, form with validation, domain type, database repo, migration, test — and wires the routes into your router. Every generated file is plain Gleam you can read, modify, and own.

## How It Works

Refrakt is two things:

**A CLI** (`refrakt`) that generates code. It reads your `gleam.toml`, produces `.gleam` and `.sql` files from templates, and patches your router. It does not run at runtime.

**A library** (`refrakt`) that provides small helpers: form validation, flash messages, migration runner, test utilities, dev error pages. Everything else lives in your project as generated code.

```
my_app/
  src/
    my_app.gleam                  ← entry point (Wisp + Mist)
    my_app/
      config.gleam                ← typed config, env-driven
      router.gleam                ← all routes, pattern matched

      web/                        ← HTTP/UI layer
        post_handler.gleam        ← index, show, new, create, edit, update, delete
        post_views.gleam          ← Lustre HTML functions
        forms/post_form.gleam     ← typed decoder + validation
        layouts/root_layout.gleam

      domain/                     ← business logic (zero framework imports)
        post.gleam                ← pub type Post { Post(...) }

      data/                       ← persistence
        post_repo.gleam           ← raw SQL, typed decoders
        migrations/
          001_create_posts.sql
```

## Principles

**Conventions over assembly** — One default project layout. One routing shape. One way to structure handlers, views, forms, and repos. You spend time building features, not debating file organization.

**Generated code is your code** — There is no "framework code" vs "your code" distinction. Every file the CLI creates looks like something a skilled Gleam developer would write by hand. Modify anything.

**No magic** — Routing is pattern matching. Views are functions. Validation is functions. If you can read Gleam, you can read a Refrakt app without consulting docs.

**Build on the ecosystem** — Wisp handles HTTP. Lustre handles HTML. Mist runs the server. Pog or Sqlight talk to the database. Refrakt adds conventions and generators on top — it doesn't reinvent the stack.

## Commands

| Command | Description |
|---------|-------------|
| `refrakt new <name>` | Create a new project (`--db postgres`, `--db sqlite`) |
| `refrakt gen page <name>` | Generate a page (handler + route) |
| `refrakt gen resource <name> <fields...>` | Generate full CRUD (handler, views, form, domain, repo, migration) |
| `refrakt gen auth` | Generate starter authentication |
| `refrakt gen migration <name>` | Generate a SQL migration file |
| `refrakt migrate` | Run pending migrations |
| `refrakt dev` | Start the dev server |
| `refrakt routes` | Print the route table |

## Generated Router

```gleam
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
```

Plain Gleam pattern matching. A new developer reads this file and understands every route in 30 seconds.

## Status

Phase 0 — designing the golden path. Not yet usable.

Coming:
- [ ] CLI scaffolding (`refrakt new`)
- [ ] Resource generator (`refrakt gen resource`)
- [ ] Validation helpers
- [ ] Flash messages
- [ ] Migration runner
- [ ] Test helpers
- [ ] Page generator
- [ ] Auth generator
- [ ] Dev server
- [ ] Lustre integration (Phase 2)
- [ ] Real-time / WebSocket (Phase 4)

## Building from Source

```bash
# Requires Gleam 1.14+, Erlang/OTP 27+
gleam build
gleam test
```

## License

MIT
