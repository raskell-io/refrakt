import blog/domain/post.{type Post, Post}
import blog/web/forms/post_form.{type PostParams}
import gleam/dynamic/decode
import gleam/result
import pog

fn post_decoder() -> decode.Decoder(Post) {
  use id <- decode.field(0, decode.int)
  use title <- decode.field(1, decode.string)
  use body <- decode.field(2, decode.string)
  use published <- decode.field(3, decode.bool)
  decode.success(Post(id: id, title: title, body: body, published: published))
}

pub fn list(db: pog.Connection) -> List(Post) {
  pog.query("SELECT id, title, body, published FROM posts ORDER BY id DESC")
  |> pog.returning(post_decoder())
  |> pog.execute(db)
  |> result.map(fn(r) { r.rows })
  |> result.unwrap([])
}

pub fn get(db: pog.Connection, id: Int) -> Result(Post, Nil) {
  pog.query("SELECT id, title, body, published FROM posts WHERE id = $1")
  |> pog.parameter(pog.int(id))
  |> pog.returning(post_decoder())
  |> pog.execute(db)
  |> result.replace_error(Nil)
  |> result.try(fn(r) {
    case r.rows {
      [item] -> Ok(item)
      _ -> Error(Nil)
    }
  })
}

pub fn create(db: pog.Connection, params: PostParams) -> Result(Post, Nil) {
  pog.query(
    "INSERT INTO posts (title, body, published) VALUES ($1, $2, $3) RETURNING id, title, body, published",
  )
  |> pog.parameter(pog.text(params.title))
  |> pog.parameter(pog.text(params.body))
  |> pog.parameter(pog.bool(params.published))
  |> pog.returning(post_decoder())
  |> pog.execute(db)
  |> result.replace_error(Nil)
  |> result.try(fn(r) {
    case r.rows {
      [item] -> Ok(item)
      _ -> Error(Nil)
    }
  })
}

pub fn update(
  db: pog.Connection,
  id: Int,
  params: PostParams,
) -> Result(Post, Nil) {
  pog.query(
    "UPDATE posts SET title = $1, body = $2, published = $3 WHERE id = $4 RETURNING id, title, body, published",
  )
  |> pog.parameter(pog.text(params.title))
  |> pog.parameter(pog.text(params.body))
  |> pog.parameter(pog.bool(params.published))
  |> pog.parameter(pog.int(id))
  |> pog.returning(post_decoder())
  |> pog.execute(db)
  |> result.replace_error(Nil)
  |> result.try(fn(r) {
    case r.rows {
      [item] -> Ok(item)
      _ -> Error(Nil)
    }
  })
}

pub fn delete(db: pog.Connection, id: Int) -> Result(Nil, Nil) {
  pog.query("DELETE FROM posts WHERE id = $1")
  |> pog.parameter(pog.int(id))
  |> pog.execute(db)
  |> result.replace(Nil)
  |> result.replace_error(Nil)
}
