import blog/domain/user.{type User, User}
import gleam/dynamic/decode
import gleam/result
import pog

fn user_decoder() -> decode.Decoder(User) {
  use id <- decode.field(0, decode.int)
  use email <- decode.field(1, decode.string)
  use hashed_password <- decode.field(2, decode.string)
  decode.success(User(id: id, email: email, hashed_password: hashed_password))
}

pub fn get_by_email(db: pog.Connection, email: String) -> Result(User, Nil) {
  pog.query("SELECT id, email, hashed_password FROM users WHERE email = $1")
  |> pog.parameter(pog.text(email))
  |> pog.returning(user_decoder())
  |> pog.execute(db)
  |> result.replace_error(Nil)
  |> result.try(fn(r) {
    case r.rows {
      [user] -> Ok(user)
      _ -> Error(Nil)
    }
  })
}

pub fn get_by_id(db: pog.Connection, id: Int) -> Result(User, Nil) {
  pog.query("SELECT id, email, hashed_password FROM users WHERE id = $1")
  |> pog.parameter(pog.int(id))
  |> pog.returning(user_decoder())
  |> pog.execute(db)
  |> result.replace_error(Nil)
  |> result.try(fn(r) {
    case r.rows {
      [user] -> Ok(user)
      _ -> Error(Nil)
    }
  })
}

pub fn create(
  db: pog.Connection,
  email: String,
  hashed_password: String,
) -> Result(User, Nil) {
  pog.query(
    "INSERT INTO users (email, hashed_password) VALUES ($1, $2) RETURNING id, email, hashed_password",
  )
  |> pog.parameter(pog.text(email))
  |> pog.parameter(pog.text(hashed_password))
  |> pog.returning(user_decoder())
  |> pog.execute(db)
  |> result.replace_error(Nil)
  |> result.try(fn(r) {
    case r.rows {
      [user] -> Ok(user)
      _ -> Error(Nil)
    }
  })
}
