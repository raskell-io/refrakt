//// Pagination helpers for list views and JSON APIs.
////
//// Pages are numbered from 1 and fetched with `LIMIT` and `OFFSET`. That
//// works with any `ORDER BY`, lets visitors jump to any page and gives a
//// total count; for very large tables or infinite scrolling, paginate by
//// key (`WHERE id < $last_id`) instead.
////
//// ## Usage in a repo
////
//// ```gleam
//// pub fn list(db: pog.Connection, params: paginate.Params) -> paginate.Page(Post) {
////   let posts =
////     pog.query("SELECT ... ORDER BY id DESC LIMIT $1 OFFSET $2")
////     |> pog.parameter(pog.int(params.per_page))
////     |> pog.parameter(pog.int(paginate.offset(params)))
////     ...
////   let total = // SELECT COUNT(*) FROM posts
////   paginate.page(posts, params, total)
//// }
//// ```
////
//// ## Usage in a handler
////
//// ```gleam
//// const per_page = 20
////
//// pub fn index(req: Request, ctx: Context) -> Response {
////   let params = paginate.Params(page: paginate.page_number(req), per_page:)
////
////   post_repo.list(ctx.db, params)
////   |> post_views.index_view
////   |> root_layout.wrap("Posts")
////   |> wisp.html_response(200)
//// }
//// ```
////
//// ## Usage in a view
////
//// ```gleam
//// case paginate.next_page(page) {
////   Ok(next) -> a([href(paginate.page_path("/posts", next))], [text("Next")])
////   Error(_) -> text("")
//// }
//// ```
////

import gleam/int
import gleam/list
import gleam/result
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

/// The largest `per_page` that `from_request` and `from_request_with`
/// accept from a query string.
pub const max_per_page = 100

/// Default pagination: page 1, 20 items per page.
pub fn default_params() -> Params {
  Params(page: 1, per_page: 20)
}

/// Extract pagination params from the query string
/// (`?page=2&per_page=10`), with 20 items per page by default.
pub fn from_request(req: Request) -> Params {
  from_request_with(req, per_page: 20)
}

/// Extract pagination params from the query string (`?page=2&per_page=10`),
/// with `per_page` items per page when the query has no valid `per_page`.
/// A `per_page` from the query is kept between 1 and `max_per_page`.
pub fn from_request_with(req: Request, per_page default: Int) -> Params {
  let per_page =
    wisp.get_query(req)
    |> list.key_find("per_page")
    |> result.try(int.parse)
    |> result.map(int.clamp(_, 1, max_per_page))
    |> result.unwrap(int.max(default, 1))

  Params(page: page_number(req), per_page:)
}

/// The page number from the `page` query parameter. A missing, invalid,
/// zero or negative page number is page 1.
pub fn page_number(req: Request) -> Int {
  wisp.get_query(req)
  |> list.key_find("page")
  |> result.try(int.parse)
  |> result.unwrap(1)
  |> int.max(1)
}

/// Calculate the SQL OFFSET from pagination params.
pub fn offset(params: Params) -> Int {
  { int.max(params.page, 1) - 1 } * int.max(params.per_page, 1)
}

/// Build a Page from items, params, and total count.
pub fn page(items: List(item), params: Params, total: Int) -> Page(item) {
  let per_page = int.max(params.per_page, 1)
  let total_pages = case total {
    0 -> 1
    _ -> { total + per_page - 1 } / per_page
  }

  Page(
    items:,
    page: params.page,
    per_page:,
    total:,
    total_pages:,
    has_previous: params.page > 1,
    has_next: params.page < total_pages,
  )
}

/// The number of the page before this one. Past the last page, it is the
/// last page, so a visitor who followed a stale link can get back.
pub fn previous_page(page: Page(item)) -> Result(Int, Nil) {
  case page.page > 1 {
    True -> Ok(int.min(page.page - 1, page.total_pages))
    False -> Error(Nil)
  }
}

/// The number of the page after this one, if there is one.
pub fn next_page(page: Page(item)) -> Result(Int, Nil) {
  case page.has_next {
    True -> Ok(page.page + 1)
    False -> Error(Nil)
  }
}

/// The path of a page: `page_path("/posts", 2)` is `"/posts?page=2"`.
pub fn page_path(base_path: String, page_num: Int) -> String {
  base_path <> "?page=" <> int.to_string(page_num)
}

/// Generate a pagination query string for a given page number.
pub fn page_url(base_path: String, page_num: Int, per_page: Int) -> String {
  base_path
  <> "?page="
  <> int.to_string(page_num)
  <> "&per_page="
  <> int.to_string(per_page)
}
