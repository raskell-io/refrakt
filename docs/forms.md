# Forms & Validation

Refrakt generates typed form decoders with validation for every
resource. Forms use two types: one for display state and one for
validated input.

## The two-type pattern

Every form has:

**`PostForm`** — display state, used to re-render the form with values
after a validation error:

```gleam
pub type PostForm {
  PostForm(id: Option(Int), title: String, body: String, published: Bool)
}
```

**`PostParams`** — validated input, the clean data passed to repos:

```gleam
pub type PostParams {
  PostParams(title: String, body: String, published: Bool)
}
```

## Three constructors

```gleam
// Blank form (for "new" page)
post_form.empty() -> PostForm

// Pre-filled from existing record (for "edit" page)
post_form.from_post(post) -> PostForm

// Re-populate from submitted form data (after validation error)
post_form.from_form_data(data) -> PostForm
```

## The decode function

```gleam
pub fn decode(
  data: wisp.FormData,
) -> Result(PostParams, List(#(String, String)))
```

Returns `Ok(PostParams)` if validation passes, or
`Error(List(#(field_name, error_message)))` if it fails.

## Using forms in handlers

### New (show blank form)

```gleam
pub fn new(_req: Request, _ctx: Context) -> Response {
  post_views.form_view(post_form.empty(), [])
  |> root_layout.wrap("New Post")
  |> wisp.html_response(200)
}
```

### Create (validate and save)

```gleam
pub fn create(req: Request, ctx: Context) -> Response {
  use form_data <- wisp.require_form(req)

  case post_form.decode(form_data) {
    // Validation failed — re-render with errors
    Error(errors) ->
      post_views.form_view(post_form.from_form_data(form_data), errors)
      |> root_layout.wrap("New Post")
      |> wisp.html_response(422)

    // Validation passed — save to database
    Ok(params) ->
      case post_repo.create(ctx.db, params) {
        Ok(post) -> wisp.redirect("/posts/" <> int.to_string(post.id))
        Error(_) -> error_handler.internal_error(req)
      }
  }
}
```

### Edit (pre-fill from record)

```gleam
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
```

## CSRF protection

Forms need no hidden token field. The router middleware's
`csrf.protect` rejects POST, PUT, PATCH and DELETE requests that a
browser sent from another site with `403 Forbidden`, using the
`Sec-Fetch-Site`, `Origin` and `Referer` headers browsers add
themselves. Keep GET handlers free of side effects, since they are not
checked. See [Routing](routing.md#csrf-protection).

## Validation helpers

The `refrakt/validate` module provides composable validators:

```gleam
import refrakt/validate

let errors =
  []
  |> validate.required(title, "title", "Title is required")
  |> validate.min_length(title, "title", 3, "Title must be at least 3 characters")
  |> validate.max_length(title, "title", 200, "Title is too long")
  |> validate.required(body, "body", "Body is required")
```

### Available validators

| Function | Description |
|----------|-------------|
| `required(errors, value, field, message)` | String is not empty after trimming |
| `min_length(errors, value, field, min, message)` | String has at least `min` characters |
| `max_length(errors, value, field, max, message)` | String has at most `max` characters |
| `inclusion(errors, value, field, allowed, message)` | Value is in the allowed list |
| `email(errors, value, field, message)` | Value looks like an email address |
| `int_between(errors, value, field, min, max, message)` | Value parses as an integer in `min`..`max`, inclusive |
| `float_between(errors, value, field, min, max, message)` | Value parses as a float in `min`..`max`, inclusive |
| `confirmation(errors, value, confirmation, field, message)` | `value` equals `confirmation` |
| `format(errors, value, field, predicate, message)` | Custom predicate returns `True` |

All validators:
- Take the error list as the first argument (for piping)
- Return the updated error list

`min_length`, `max_length`, `int_between`, `float_between` and `confirmation`
also skip the check when the field already has an error, so a field reports
one message at a time. `required`, `inclusion`, `email` and `format` always
add their message when the value does not pass, so put `required` first:

```gleam
let errors =
  []
  |> validate.required(email, "email", "Email is required")
  |> validate.email(email, "email", "Must be a valid email")
  |> validate.required(password, "password", "Password is required")
  |> validate.min_length(password, "password", 8, "Password must be 8 characters or more")
  |> validate.confirmation(password, password_repeat, "password", "Passwords do not match")
  |> validate.int_between(age, "age", 13, 120, "Age must be between 13 and 120")
```

`email` is a pragmatic check, not a RFC 5322 parser: the trimmed value needs
one `@`, a non-empty local part without spaces, and a domain with at least two
non-empty dot-separated labels. `confirmation` compares the two values as
given, without trimming, because passwords may contain spaces.

### Custom validation

Add your own validators in the form module:

```gleam
fn validate_email(errors, email, field, message) {
  case string.contains(email, "@") {
    True -> errors
    False -> [#(field, message), ..errors]
  }
}

// Use it:
let errors =
  []
  |> validate.required(email, "email", "Email is required")
  |> validate_email(email, "email", "Must be a valid email")
```

## Displaying errors in views

The generated form view includes a `field_error` helper:

```gleam
fn field_error(errors: List(#(String, String)), field: String) -> Element(Nil) {
  case list.find(errors, fn(e) { e.0 == field }) {
    Ok(#(_, message)) -> p([class("error")], [text(message)])
    Error(_) -> text("")
  }
}
```

Used in form fields:

```gleam
div([class("field")], [
  label([], [text("Title")]),
  input([type_("text"), name("title"), value(values.title)]),
  field_error(errors, "title"),
])
```

## Field type handling

| CLI Type | Form Type | HTML Input | Decode |
|----------|-----------|------------|--------|
| `string` | `String` | `<input type="text">` | Direct string |
| `text` | `String` | `<textarea>` | Direct string |
| `int` | `Int` | `<input type="number">` | `int.parse` |
| `float` | `Float` | `<input type="number" step="any">` | `parse_float` (accepts `4` and `4.0`) |
| `bool` | `Bool` | `<input type="checkbox">` | Check if field present |
| `date` | `String` | `<input type="text">` | Direct string |
| `datetime` | `String` | `<input type="text">` | Direct string |
| `optional(T)` | `Option(T)` | As for `T`, empty for `None` | Blank is `None`, else parsed as `T` |
| `optional(bool)` | `Option(Bool)` | `<select>`: blank, Yes, No | `""` is `None`, `"true"`/`"false"` |

### Optional fields

An `optional(T)` field is `Option(T)` in the form and the params. The
generated form module gets two small helpers:

```gleam
// Blank is None; anything else is parsed
price: optional(price, parse_float),

// In decode: a non-blank number that does not parse is an error
let errors =
  []
  |> validate.required(name, "name", "Name is required")
  |> must_parse(price, parse_float, "price", "Price must be a number")
```

Optional fields are not `required`. See
[Field Types](field-types.md#optionalt) for `optional(bool)`, which is
a select because a checkbox cannot say "not set".

