import gleam/int
import gleam/list
import gleam/option
import lustre/attribute.{class, href, name, type_, value}
import lustre/element.{type Element, text}
import lustre/element/html.{
  a, button, div, form, h1, input, label, li, p, section, textarea, ul,
}
import tasks_app/domain/task.{type Task}
import tasks_app/web/forms/task_form

pub fn index_view(items: List(Task)) -> Element(Nil) {
  section([class("tasks")], [
    div([class("header")], [
      h1([], [text("Tasks")]),
      a([href("/tasks/new"), class("btn")], [text("New Task")]),
    ]),
    ul(
      [class("post-list")],
      list.map(items, fn(item) {
        li([], [
          a([href("/tasks/" <> int.to_string(item.id))], [
            text(item.title),
          ]),
        ])
      }),
    ),
  ])
}

pub fn show_view(item: Task) -> Element(Nil) {
  section([class("task")], [
    h1([], [text(item.title)]),
    div([class("actions")], [
      a(
        [
          href("/tasks/" <> int.to_string(item.id) <> "/edit"),
          class("btn"),
        ],
        [text("Edit")],
      ),
    ]),
  ])
}

pub fn form_view(
  values: task_form.TaskForm,
  errors: List(#(String, String)),
) -> Element(Nil) {
  let post_action = case values.id {
    option.Some(id) -> "/tasks/" <> int.to_string(id)
    option.None -> "/tasks"
  }

  section([class("task-form")], [
    h1([], [
      text(case values.id {
        option.Some(_) -> "Edit Task"
        option.None -> "New Task"
      }),
    ]),
    form([attribute.action(post_action), attribute.method("post")], [
      case values.id {
        option.Some(_) ->
          input([type_("hidden"), name("_method"), value("put")])
        option.None -> text("")
      },
      div([class("field")], [
        label([], [text("Title")]),
        input([type_("text"), name("title"), value(values.title)]),
        field_error(errors, "title"),
      ]),
      div([class("field")], [
        label([], [
          input([
            type_("checkbox"),
            name("completed"),
            attribute.checked(values.completed),
          ]),
          text(" Completed"),
        ]),
      ]),
      button([type_("submit"), class("btn")], [text("Save")]),
    ]),
  ])
}

fn field_error(errors: List(#(String, String)), field: String) -> Element(Nil) {
  case list.find(errors, fn(e) { e.0 == field }) {
    Ok(#(_, message)) -> p([class("error")], [text(message)])
    Error(_) -> text("")
  }
}
