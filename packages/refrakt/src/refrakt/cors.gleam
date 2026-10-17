/// CORS middleware for Refrakt applications.
///
/// ## Usage
///
/// ```gleam
/// import refrakt/cors
///
/// fn middleware(req, next) {
///   use <- cors.allow(
///     req,
///     origins: ["http://localhost:3000", "https://myapp.com"],
///     methods: ["GET", "POST", "PUT", "DELETE"],
///   )
///   next(req)
/// }
/// ```
///
import gleam/http
import gleam/list
import gleam/string
import wisp.{type Request, type Response}

/// CORS configuration.
pub type CorsConfig {
  CorsConfig(
    origins: List(String),
    methods: List(String),
    headers: List(String),
    max_age: Int,
    credentials: Bool,
  )
}

/// Default CORS config — allows common methods and headers.
pub fn default_config() -> CorsConfig {
  CorsConfig(
    origins: ["*"],
    methods: ["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
    headers: ["content-type", "authorization", "accept"],
    max_age: 86_400,
    credentials: False,
  )
}

/// CORS middleware with full configuration.
pub fn middleware(
  req: Request,
  config: CorsConfig,
  next: fn() -> Response,
) -> Response {
  // Handle preflight
  case req.method {
    http.Options -> preflight_response(req, config)
    _ -> {
      let resp = next()
      add_cors_headers(req, resp, config)
    }
  }
}

/// Simple CORS middleware — allow specific origins and methods.
pub fn allow(
  req: Request,
  origins origins: List(String),
  methods methods: List(String),
  handler next: fn() -> Response,
) -> Response {
  let config =
    CorsConfig(
      origins:,
      methods:,
      headers: ["content-type", "authorization", "accept"],
      max_age: 86_400,
      credentials: False,
    )
  middleware(req, config, next)
}

fn preflight_response(req: Request, config: CorsConfig) -> Response {
  wisp.no_content()
  |> add_cors_headers(req, _, config)
}

fn add_cors_headers(
  req: Request,
  resp: Response,
  config: CorsConfig,
) -> Response {
  let origin = get_origin(req)
  let allowed_origin = case config.origins {
    ["*"] -> "*"
    origins ->
      case list.contains(origins, origin) {
        True -> origin
        False -> ""
      }
  }

  case allowed_origin {
    "" -> resp
    _ ->
      resp
      |> wisp.set_header("access-control-allow-origin", allowed_origin)
      |> wisp.set_header(
        "access-control-allow-methods",
        string.join(config.methods, ", "),
      )
      |> wisp.set_header(
        "access-control-allow-headers",
        string.join(config.headers, ", "),
      )
      |> wisp.set_header(
        "access-control-max-age",
        int_to_string(config.max_age),
      )
      |> fn(r) {
        case config.credentials {
          True -> wisp.set_header(r, "access-control-allow-credentials", "true")
          False -> r
        }
      }
  }
}

fn get_origin(req: Request) -> String {
  case list.find(req.headers, fn(h) { h.0 == "origin" }) {
    Ok(#(_, origin)) -> origin
    Error(_) -> ""
  }
}

fn int_to_string(n: Int) -> String {
  case n {
    _ if n < 0 -> "-" <> int_to_string(-n)
    0 -> "0"
    _ -> do_int_to_string(n, "")
  }
}

fn do_int_to_string(n: Int, acc: String) -> String {
  case n {
    0 -> acc
    _ -> {
      let digit = case n % 10 {
        0 -> "0"
        1 -> "1"
        2 -> "2"
        3 -> "3"
        4 -> "4"
        5 -> "5"
        6 -> "6"
        7 -> "7"
        8 -> "8"
        _ -> "9"
      }
      do_int_to_string(n / 10, digit <> acc)
    }
  }
}
