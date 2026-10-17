import gleam/list
import gleam/string
import gleeunit/should
import refrakt_cli/routes

/// Collapse the padded columns so tests don't depend on column widths.
fn columns(line: String) -> List(String) {
  line
  |> string.split(" ")
  |> list.filter(fn(part) { part != "" })
}

fn routes_of(router: String) -> List(List(String)) {
  routes.extract_routes(router)
  |> list.map(columns)
}

pub fn root_route_prints_slash_test() {
  routes_of("    [], http.Get -> home_handler.index(req, ctx)")
  |> should.equal([["GET", "/", "home_handler.index"]])
}

pub fn static_and_param_segments_test() {
  let router =
    "  case wisp.path_segments(req), req.method {
    [\"posts\"], http.Get -> post_handler.index(req, ctx)
    [\"posts\", \"new\"], http.Get -> post_handler.new(req, ctx)
    [\"posts\", id], http.Put -> post_handler.update(req, ctx, id)
    [\"posts\", id, \"edit\"], http.Get -> post_handler.edit(req, ctx, id)
    _, _ -> error_handler.not_found(req)
  }"

  routes_of(router)
  |> should.equal([
    ["GET", "/posts", "post_handler.index"],
    ["GET", "/posts/new", "post_handler.new"],
    ["PUT", "/posts/:id", "post_handler.update"],
    ["GET", "/posts/:id/edit", "post_handler.edit"],
  ])
}

pub fn rest_segment_test() {
  routes_of("    [\"files\", ..path], http.Get -> file_handler.show(req, ctx)")
  |> should.equal([["GET", "/files/*path", "file_handler.show"]])
}
