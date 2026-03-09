import envoy
import gleam/int
import gleam/result

pub type Config {
  Config(port: Int, port_string: String, secret_key_base: String, env: Env)
}

pub type Env {
  Dev
  Test
  Prod
}

pub fn load() -> Config {
  let port =
    envoy.get("PORT")
    |> result.try(int.parse)
    |> result.unwrap(4000)

  let secret_key_base =
    envoy.get("SECRET_KEY_BASE")
    |> result.unwrap(
      "dev-secret-key-base-that-is-at-least-64-bytes-long-for-security!!",
    )

  let env = case envoy.get("APP_ENV") {
    Ok("prod") -> Prod
    Ok("test") -> Test
    _ -> Dev
  }

  Config(
    port: port,
    port_string: int.to_string(port),
    secret_key_base: secret_key_base,
    env: env,
  )
}
