import gleam/http
import gleeunit/should
import refrakt/paginate
import wisp/simulate

pub fn page_number_defaults_to_1_test() {
  simulate.request(http.Get, "/posts")
  |> paginate.page_number
  |> should.equal(1)
}

pub fn page_number_reads_the_query_test() {
  simulate.request(http.Get, "/posts?page=3")
  |> paginate.page_number
  |> should.equal(3)
}

pub fn invalid_zero_and_negative_page_numbers_are_page_1_test() {
  simulate.request(http.Get, "/posts?page=abc")
  |> paginate.page_number
  |> should.equal(1)
  simulate.request(http.Get, "/posts?page=0")
  |> paginate.page_number
  |> should.equal(1)
  simulate.request(http.Get, "/posts?page=-2")
  |> paginate.page_number
  |> should.equal(1)
}

pub fn from_request_with_uses_the_default_per_page_test() {
  simulate.request(http.Get, "/posts?page=2")
  |> paginate.from_request_with(per_page: 5)
  |> should.equal(paginate.Params(page: 2, per_page: 5))
}

pub fn from_request_with_clamps_per_page_from_the_query_test() {
  simulate.request(http.Get, "/posts?per_page=1000")
  |> paginate.from_request_with(per_page: 5)
  |> should.equal(paginate.Params(page: 1, per_page: paginate.max_per_page))
  simulate.request(http.Get, "/posts?per_page=0")
  |> paginate.from_request_with(per_page: 5)
  |> should.equal(paginate.Params(page: 1, per_page: 1))
  simulate.request(http.Get, "/posts?per_page=x")
  |> paginate.from_request_with(per_page: 5)
  |> should.equal(paginate.Params(page: 1, per_page: 5))
}

pub fn from_request_defaults_to_20_per_page_test() {
  simulate.request(http.Get, "/posts")
  |> paginate.from_request
  |> should.equal(paginate.Params(page: 1, per_page: 20))
}

pub fn offset_test() {
  paginate.offset(paginate.Params(page: 1, per_page: 20)) |> should.equal(0)
  paginate.offset(paginate.Params(page: 3, per_page: 20)) |> should.equal(40)
}

pub fn page_counts_pages_test() {
  let page = paginate.page([1, 2], paginate.Params(page: 2, per_page: 2), 5)

  page.total_pages |> should.equal(3)
  page.has_previous |> should.be_true
  page.has_next |> should.be_true
  paginate.previous_page(page) |> should.equal(Ok(1))
  paginate.next_page(page) |> should.equal(Ok(3))
}

pub fn an_empty_list_has_one_page_test() {
  let page = paginate.page([], paginate.Params(page: 1, per_page: 20), 0)

  page.total_pages |> should.equal(1)
  paginate.previous_page(page) |> should.equal(Error(Nil))
  paginate.next_page(page) |> should.equal(Error(Nil))
}

pub fn previous_page_past_the_end_is_the_last_page_test() {
  let page = paginate.page([], paginate.Params(page: 9, per_page: 2), 3)

  paginate.previous_page(page) |> should.equal(Ok(2))
  paginate.next_page(page) |> should.equal(Error(Nil))
}

pub fn page_path_test() {
  paginate.page_path("/posts", 2) |> should.equal("/posts?page=2")
}
