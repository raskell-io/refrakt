import blog/context.{type Context}
import blog/data/post_repo
import blog/web/error_handler
import blog/web/forms/post_form
import blog/web/layouts/root_layout
import blog/web/post_views
import gleam/int
import refrakt/flash
import wisp.{type Request, type Response}

pub fn index(_req: Request, ctx: Context) -> Response {
  let items = post_repo.list(ctx.db)
  post_views.index_view(items)
  |> root_layout.wrap("Posts")
  |> wisp.html_response(200)
}

pub fn show(req: Request, ctx: Context, id: String) -> Response {
  case int.parse(id) {
    Error(_) -> error_handler.not_found(req)
    Ok(id) ->
      case post_repo.get(ctx.db, id) {
        Error(_) -> error_handler.not_found(req)
        Ok(item) ->
          post_views.show_view(item)
          |> root_layout.wrap("Post")
          |> wisp.html_response(200)
      }
  }
}

pub fn new(_req: Request, _ctx: Context) -> Response {
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
        Ok(item) ->
          wisp.redirect("/posts/" <> int.to_string(item.id))
          |> flash.set_flash(req, "info", "Post created")

        Error(_) -> error_handler.internal_error(req)
      }
  }
}

pub fn edit(req: Request, ctx: Context, id: String) -> Response {
  case int.parse(id) {
    Error(_) -> error_handler.not_found(req)
    Ok(id) ->
      case post_repo.get(ctx.db, id) {
        Error(_) -> error_handler.not_found(req)
        Ok(item) ->
          post_views.form_view(post_form.from_post(item), [])
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
              |> flash.set_flash(req, "info", "Post updated")

            Error(_) -> error_handler.internal_error(req)
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
      |> flash.set_flash(req, "info", "Post deleted")
    }
  }
}
