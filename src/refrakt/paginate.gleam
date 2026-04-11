/// Pagination helpers for list views.
///
/// ## Usage in a handler
///
/// ```gleam
/// import refrakt/paginate
///
/// pub fn index(req: Request, ctx: Context) -> Response {
///   let params = paginate.from_request(req)
///   let posts = post_repo.list_paginated(ctx.db, params)
///   let page = paginate.page(posts, params, total_count)
///
///   post_views.index_view(page)
///   |> root_layout.wrap("Posts")
///   |> wisp.html_response(200)
/// }
/// ```
///
/// ## Usage in a repo
///
/// ```gleam
/// pub fn list_paginated(db, params: paginate.Params) -> List(Post) {
///   let offset = paginate.offset(params)
///   pog.query("SELECT ... LIMIT $1 OFFSET $2")
///   |> pog.parameter(pog.int(params.per_page))
///   |> pog.parameter(pog.int(offset))
///   ...
/// }
/// ```
///
import gleam/int
import gleam/list
import gleam/option
import gleam/result
import gleam/string
import wisp.{type Request}

/// Pagination parameters.
pub type Params {
  Params(page: Int, per_page: Int)
}

/// A paginated result.
pub type Page(item) {
  Page(
    items: List(item),
    page: Int,
    per_page: Int,
    total: Int,
    total_pages: Int,
    has_previous: Bool,
    has_next: Bool,
  )
}

/// Default pagination: page 1, 20 items per page.
pub fn default_params() -> Params {
  Params(page: 1, per_page: 20)
}

/// Extract pagination params from query string (?page=2&per_page=10).
pub fn from_request(req: Request) -> Params {
  let query_params = parse_query(req.query)

  let page =
    find_param(query_params, "page")
    |> result.try(int.parse)
    |> result.unwrap(1)
    |> int.max(1)

  let per_page =
    find_param(query_params, "per_page")
    |> result.try(int.parse)
    |> result.unwrap(20)
    |> int.clamp(1, 100)

  Params(page:, per_page:)
}

/// Calculate the SQL OFFSET from pagination params.
pub fn offset(params: Params) -> Int {
  { params.page - 1 } * params.per_page
}

/// Build a Page from items, params, and total count.
pub fn page(items: List(item), params: Params, total: Int) -> Page(item) {
  let total_pages = case total {
    0 -> 1
    _ -> { total + params.per_page - 1 } / params.per_page
  }

  Page(
    items:,
    page: params.page,
    per_page: params.per_page,
    total:,
    total_pages:,
    has_previous: params.page > 1,
    has_next: params.page < total_pages,
  )
}

/// Generate a pagination query string for a given page number.
pub fn page_url(base_path: String, page_num: Int, per_page: Int) -> String {
  base_path
  <> "?page="
  <> int.to_string(page_num)
  <> "&per_page="
  <> int.to_string(per_page)
}

fn parse_query(query: option.Option(String)) -> List(#(String, String)) {
  case query {
    option.Some(q) ->
      q
      |> string.split("&")
      |> list.filter_map(fn(pair) {
        case string.split_once(pair, "=") {
          Ok(#(k, v)) -> Ok(#(k, v))
          Error(_) -> Error(Nil)
        }
      })
    option.None -> []
  }
}

fn find_param(
  params: List(#(String, String)),
  key: String,
) -> Result(String, Nil) {
  list.find(params, fn(p) { p.0 == key })
  |> result.map(fn(p) { p.1 })
}
