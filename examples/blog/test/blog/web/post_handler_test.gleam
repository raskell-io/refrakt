import blog/web/forms/post_form
import gleeunit/should
import wisp

pub fn empty_form_has_no_id_test() {
  let form = post_form.empty()
  form.id
  |> should.be_none
}

pub fn decode_valid_form_test() {
  let data =
    wisp.FormData(
      values: [
        #("title", "test value"),
        #("body", "test value"),
        #("published", "on"),
      ],
      files: [],
    )

  post_form.decode(data)
  |> should.be_ok
}

pub fn decode_missing_title_returns_error_test() {
  let data = wisp.FormData(values: [], files: [])

  post_form.decode(data)
  |> should.be_error
}
