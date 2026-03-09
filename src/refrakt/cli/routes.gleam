/// `refrakt routes` — print the route table from router.gleam.
///
import gleam/io
import gleam/list
import gleam/string
import refrakt/cli/project
import simplifile

pub fn run() {
  let app = project.app_name()
  let router_path = "src/" <> app <> "/router.gleam"

  case simplifile.read(router_path) {
    Error(_) -> {
      io.println("Could not read " <> router_path)
    }
    Ok(content) -> {
      let routes = extract_routes(content)
      case routes {
        [] -> io.println("No routes found.")
        _ -> list.each(routes, fn(route) { io.println(route) })
      }
    }
  }
}

fn extract_routes(content: String) -> List(String) {
  content
  |> string.split("\n")
  |> list.filter_map(fn(line) {
    let trimmed = string.trim(line)
    case parse_route_line(trimmed) {
      Ok(route) -> Ok(route)
      Error(_) -> Error(Nil)
    }
  })
}

fn parse_route_line(line: String) -> Result(String, Nil) {
  // Match patterns like: [], http.Get -> home_handler.index(req, ctx)
  // or: ["posts"], http.Get -> post_handler.index(req, ctx)
  case string.split_once(line, " -> ") {
    Error(_) -> Error(Nil)
    Ok(#(pattern, handler)) -> {
      case string.contains(pattern, "http.") {
        False -> Error(Nil)
        True -> {
          let method = extract_method(pattern)
          let path = extract_path(pattern)
          let handler_name = extract_handler_name(handler)
          Ok(pad_right(method, 8) <> pad_right(path, 24) <> handler_name)
        }
      }
    }
  }
}

fn extract_method(pattern: String) -> String {
  case string.contains(pattern, "http.Get") {
    True -> "GET"
    False ->
      case string.contains(pattern, "http.Post") {
        True -> "POST"
        False ->
          case string.contains(pattern, "http.Put") {
            True -> "PUT"
            False ->
              case string.contains(pattern, "http.Delete") {
                True -> "DELETE"
                False ->
                  case string.contains(pattern, "http.Patch") {
                    True -> "PATCH"
                    False -> "???"
                  }
              }
          }
      }
  }
}

fn extract_path(pattern: String) -> String {
  // Parse the list pattern to build the path
  case string.split_once(pattern, "],") {
    Error(_) -> "/"
    Ok(#(list_part, _)) -> {
      let trimmed = string.trim(list_part)
      case trimmed {
        "[]" -> "/"
        _ -> {
          // Remove leading [ and parse segments
          let inner =
            trimmed
            |> string.drop_start(1)
          let segments =
            inner
            |> string.split(",")
            |> list.map(fn(s) {
              let s = string.trim(s)
              case string.starts_with(s, "\"") {
                True ->
                  s
                  |> string.replace("\"", "")
                False -> ":" <> s
              }
            })
          "/" <> string.join(segments, "/")
        }
      }
    }
  }
}

fn extract_handler_name(handler: String) -> String {
  // Take everything before the first "("
  case string.split_once(handler, "(") {
    Ok(#(name, _)) -> string.trim(name)
    Error(_) -> string.trim(handler)
  }
}

fn pad_right(s: String, width: Int) -> String {
  let padding = width - string.length(s)
  case padding > 0 {
    True -> s <> string.repeat(" ", padding)
    False -> s
  }
}
