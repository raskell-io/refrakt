import gleam/dynamic/decode
import gleam/result
import sqlight
import tasks_app/domain/task.{type Task, Task}
import tasks_app/web/forms/task_form.{type TaskParams}

fn task_decoder() -> decode.Decoder(Task) {
  use id <- decode.field(0, decode.int)
  use title <- decode.field(1, decode.string)
  use completed <- decode.field(2, sqlight.decode_bool())
  decode.success(Task(id: id, title: title, completed: completed))
}

pub fn list(db_path: String) -> List(Task) {
  use conn <- sqlight.with_connection(db_path)
  case
    sqlight.query(
      "SELECT id, title, completed FROM tasks ORDER BY id DESC",
      on: conn,
      with: [],
      expecting: task_decoder(),
    )
  {
    Ok(rows) -> rows
    Error(_) -> []
  }
}

pub fn get(db_path: String, id: Int) -> Result(Task, Nil) {
  use conn <- sqlight.with_connection(db_path)
  sqlight.query(
    "SELECT id, title, completed FROM tasks WHERE id = ?",
    on: conn,
    with: [sqlight.int(id)],
    expecting: task_decoder(),
  )
  |> result.replace_error(Nil)
  |> result.try(fn(rows) {
    case rows {
      [item] -> Ok(item)
      _ -> Error(Nil)
    }
  })
}

pub fn create(db_path: String, params: TaskParams) -> Result(Task, Nil) {
  use conn <- sqlight.with_connection(db_path)
  sqlight.query(
    "INSERT INTO tasks (title, completed) VALUES (?, ?) RETURNING id, title, completed",
    on: conn,
    with: [
      sqlight.text(params.title),
      sqlight.bool(params.completed),
    ],
    expecting: task_decoder(),
  )
  |> result.replace_error(Nil)
  |> result.try(fn(rows) {
    case rows {
      [item] -> Ok(item)
      _ -> Error(Nil)
    }
  })
}

pub fn update(db_path: String, id: Int, params: TaskParams) -> Result(Task, Nil) {
  use conn <- sqlight.with_connection(db_path)
  sqlight.query(
    "UPDATE tasks SET title = ?, completed = ? WHERE id = ? RETURNING id, title, completed",
    on: conn,
    with: [
      sqlight.text(params.title),
      sqlight.bool(params.completed),
      sqlight.int(id),
    ],
    expecting: task_decoder(),
  )
  |> result.replace_error(Nil)
  |> result.try(fn(rows) {
    case rows {
      [item] -> Ok(item)
      _ -> Error(Nil)
    }
  })
}

pub fn delete(db_path: String, id: Int) -> Result(Nil, Nil) {
  use conn <- sqlight.with_connection(db_path)
  sqlight.query(
    "DELETE FROM tasks WHERE id = ?",
    on: conn,
    with: [sqlight.int(id)],
    expecting: decode.success(Nil),
  )
  |> result.replace(Nil)
  |> result.replace_error(Nil)
}
