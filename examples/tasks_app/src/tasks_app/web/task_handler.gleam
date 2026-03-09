import gleam/int
import refrakt/flash
import tasks_app/context.{type Context}
import tasks_app/data/task_repo
import tasks_app/web/error_handler
import tasks_app/web/forms/task_form
import tasks_app/web/layouts/root_layout
import tasks_app/web/task_views
import wisp.{type Request, type Response}

pub fn index(_req: Request, ctx: Context) -> Response {
  let items = task_repo.list(ctx.db_path)
  task_views.index_view(items)
  |> root_layout.wrap("Tasks")
  |> wisp.html_response(200)
}

pub fn show(req: Request, ctx: Context, id: String) -> Response {
  case int.parse(id) {
    Error(_) -> error_handler.not_found(req)
    Ok(id) ->
      case task_repo.get(ctx.db_path, id) {
        Error(_) -> error_handler.not_found(req)
        Ok(item) ->
          task_views.show_view(item)
          |> root_layout.wrap("Task")
          |> wisp.html_response(200)
      }
  }
}

pub fn new(_req: Request, _ctx: Context) -> Response {
  task_views.form_view(task_form.empty(), [])
  |> root_layout.wrap("New Task")
  |> wisp.html_response(200)
}

pub fn create(req: Request, ctx: Context) -> Response {
  use form_data <- wisp.require_form(req)

  case task_form.decode(form_data) {
    Error(errors) ->
      task_views.form_view(task_form.from_form_data(form_data), errors)
      |> root_layout.wrap("New Task")
      |> wisp.html_response(422)

    Ok(params) ->
      case task_repo.create(ctx.db_path, params) {
        Ok(item) ->
          wisp.redirect("/tasks/" <> int.to_string(item.id))
          |> flash.set_flash(req, "info", "Task created")

        Error(_) -> error_handler.internal_error(req)
      }
  }
}

pub fn edit(req: Request, ctx: Context, id: String) -> Response {
  case int.parse(id) {
    Error(_) -> error_handler.not_found(req)
    Ok(id) ->
      case task_repo.get(ctx.db_path, id) {
        Error(_) -> error_handler.not_found(req)
        Ok(item) ->
          task_views.form_view(task_form.from_task(item), [])
          |> root_layout.wrap("Edit Task")
          |> wisp.html_response(200)
      }
  }
}

pub fn update(req: Request, ctx: Context, id: String) -> Response {
  use form_data <- wisp.require_form(req)

  case int.parse(id) {
    Error(_) -> error_handler.not_found(req)
    Ok(id) ->
      case task_form.decode(form_data) {
        Error(errors) ->
          task_views.form_view(task_form.from_form_data(form_data), errors)
          |> root_layout.wrap("Edit Task")
          |> wisp.html_response(422)

        Ok(params) ->
          case task_repo.update(ctx.db_path, id, params) {
            Ok(_) ->
              wisp.redirect("/tasks/" <> int.to_string(id))
              |> flash.set_flash(req, "info", "Task updated")

            Error(_) -> error_handler.internal_error(req)
          }
      }
  }
}

pub fn delete(req: Request, ctx: Context, id: String) -> Response {
  case int.parse(id) {
    Error(_) -> error_handler.not_found(req)
    Ok(id) -> {
      let _ = task_repo.delete(ctx.db_path, id)
      wisp.redirect("/tasks")
      |> flash.set_flash(req, "info", "Task deleted")
    }
  }
}
