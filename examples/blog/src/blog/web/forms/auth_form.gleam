import gleam/list
import gleam/result
import refrakt/validate
import wisp

pub type LoginParams {
  LoginParams(email: String, password: String)
}

pub type RegisterParams {
  RegisterParams(email: String, password: String, password_confirmation: String)
}

pub fn decode_login(
  data: wisp.FormData,
) -> Result(LoginParams, List(#(String, String))) {
  let email = get_value(data, "email")
  let password = get_value(data, "password")

  let errors =
    []
    |> validate.required(email, "email", "Email is required")
    |> validate.required(password, "password", "Password is required")

  case errors {
    [] -> Ok(LoginParams(email: email, password: password))
    _ -> Error(errors)
  }
}

pub fn decode_register(
  data: wisp.FormData,
) -> Result(RegisterParams, List(#(String, String))) {
  let email = get_value(data, "email")
  let password = get_value(data, "password")
  let password_confirmation = get_value(data, "password_confirmation")

  let errors =
    []
    |> validate.required(email, "email", "Email is required")
    |> validate.required(password, "password", "Password is required")
    |> validate.min_length(
      password,
      "password",
      8,
      "Password must be at least 8 characters",
    )
    |> check_confirmation(password, password_confirmation)

  case errors {
    [] ->
      Ok(RegisterParams(
        email: email,
        password: password,
        password_confirmation: password_confirmation,
      ))
    _ -> Error(errors)
  }
}

fn check_confirmation(
  errors: List(#(String, String)),
  password: String,
  confirmation: String,
) -> List(#(String, String)) {
  case password == confirmation {
    True -> errors
    False -> [#("password_confirmation", "Passwords do not match"), ..errors]
  }
}

fn get_value(data: wisp.FormData, key: String) -> String {
  list.find(data.values, fn(v) { v.0 == key })
  |> result.map(fn(v) { v.1 })
  |> result.unwrap("")
}
