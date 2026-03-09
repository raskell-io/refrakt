import blog/domain/post.{type Post}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import refrakt/validate
import wisp

pub type PostForm {
  PostForm(id: Option(Int), title: String, body: String, published: Bool)
}

pub type PostParams {
  PostParams(title: String, body: String, published: Bool)
}

pub fn empty() -> PostForm {
  PostForm(id: None, title: "", body: "", published: False)
}

pub fn from_post(item: Post) -> PostForm {
  PostForm(
    id: Some(item.id),
    title: item.title,
    body: item.body,
    published: item.published,
  )
}

pub fn from_form_data(data: wisp.FormData) -> PostForm {
  PostForm(
    id: None,
    title: get_value(data, "title"),
    body: get_value(data, "body"),
    published: list.any(data.values, fn(v) { v.0 == "published" }),
  )
}

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
    [] ->
      Ok(PostParams(
        title: title,
        body: body,
        published: list.any(data.values, fn(v) { v.0 == "published" }),
      ))
    _ -> Error(errors)
  }
}

fn get_value(data: wisp.FormData, key: String) -> String {
  list.find(data.values, fn(v) { v.0 == key })
  |> result.map(fn(v) { v.1 })
  |> result.unwrap("")
}
