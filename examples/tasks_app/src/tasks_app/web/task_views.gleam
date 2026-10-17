import gleam/int
import gleam/list
import gleam/option
import lustre/attribute.{class, href, name, type_, value}
import lustre/element.{type Element, text}
import lustre/element/html.{
  a, button, div, form, h1, input, label, li, p, section, ul,
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
      // wisp.method_override reads the method from the _method query
      // parameter of a POST, so this form sends a DELETE.
      form(
        [
          attribute.action(
            "/tasks/" <> int.to_string(item.id) <> "?_method=DELETE",
          ),
          attribute.method("post"),
        ],
        [button([type_("submit"), class("btn")], [text("Delete")])],
      ),
    ]),
  ])
}

pub fn form_view(
  values: task_form.TaskForm,
  errors: List(#(String, String)),
) -> Element(Nil) {
  // Updates are sent as POST /<id>?_method=PUT: wisp.method_override
  // reads the method from the _method query parameter.
  let post_action = case values.id {
    option.Some(id) -> "/tasks/" <> int.to_string(id) <> "?_method=PUT"
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
