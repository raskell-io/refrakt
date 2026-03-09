import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import refrakt/validate
import tasks_app/domain/task.{type Task}
import wisp

pub type TaskForm {
  TaskForm(id: Option(Int), title: String, completed: Bool)
}

pub type TaskParams {
  TaskParams(title: String, completed: Bool)
}

pub fn empty() -> TaskForm {
  TaskForm(id: None, title: "", completed: False)
}

pub fn from_task(item: Task) -> TaskForm {
  TaskForm(id: Some(item.id), title: item.title, completed: item.completed)
}

pub fn from_form_data(data: wisp.FormData) -> TaskForm {
  TaskForm(
    id: None,
    title: get_value(data, "title"),
    completed: list.any(data.values, fn(v) { v.0 == "completed" }),
  )
}

pub fn decode(
  data: wisp.FormData,
) -> Result(TaskParams, List(#(String, String))) {
  let title = get_value(data, "title")

  let errors =
    []
    |> validate.required(title, "title", "Title is required")

  case errors {
    [] ->
      Ok(TaskParams(
        title: title,
        completed: list.any(data.values, fn(v) { v.0 == "completed" }),
      ))
    _ -> Error(errors)
  }
}

fn get_value(data: wisp.FormData, key: String) -> String {
  list.find(data.values, fn(v) { v.0 == key })
  |> result.map(fn(v) { v.1 })
  |> result.unwrap("")
}
