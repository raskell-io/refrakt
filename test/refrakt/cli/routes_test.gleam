import gleeunit/should
import refrakt/cli/routes

pub fn extract_path_root_empty_list_test() {
  routes.extract_path("[]")
  |> should.equal("/")
}

pub fn extract_path_root_with_method_test() {
  routes.extract_path("[], http.Get")
  |> should.equal("/")
}

pub fn extract_path_root_with_spaces_test() {
  routes.extract_path("[  ], http.Get")
  |> should.equal("/")
}

pub fn extract_path_single_segment_test() {
  routes.extract_path("[\"posts\"], http.Get")
  |> should.equal("/posts")
}

pub fn extract_path_param_segment_test() {
  routes.extract_path("[\"posts\", id], http.Get")
  |> should.equal("/posts/:id")
}

pub fn extract_path_multiple_segments_test() {
  routes.extract_path("[\"posts\", id, \"edit\"], http.Get")
  |> should.equal("/posts/:id/edit")
}

pub fn parse_route_line_root_route_test() {
  routes.parse_route_line("[], http.Get -> home_handler.index(req, ctx)")
  |> should.equal(Ok("GET     /                       home_handler.index"))
}

pub fn parse_route_line_resource_route_test() {
  routes.parse_route_line(
    "[\"posts\"], http.Get -> post_handler.index(req, ctx)",
  )
  |> should.equal(Ok("GET     /posts                  post_handler.index"))
}

pub fn extract_routes_root_route_test() {
  let router_content =
    "
pub fn handle_request(req: Request, ctx: Context) -> Response {
  case wisp.path_segments(req), req.method {
    [], http.Get -> home_handler.index(req, ctx)
    [\"posts\"], http.Get -> post_handler.index(req, ctx)
    _, _ -> error_handler.not_found(req)
  }
}
"

  routes.extract_routes(router_content)
  |> should.equal([
    "GET     /                       home_handler.index",
    "GET     /posts                  post_handler.index",
  ])
}
