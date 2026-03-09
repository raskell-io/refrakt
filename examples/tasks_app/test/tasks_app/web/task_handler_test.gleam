import gleeunit/should
import tasks_app/web/forms/task_form
import wisp

pub fn empty_form_has_no_id_test() {
  let form = task_form.empty()
  form.id
  |> should.be_none
}

pub fn decode_valid_form_test() {
  let data =
    wisp.FormData(
      values: [
        #("title", "test value"),
        #("completed", "on"),
      ],
      files: [],
    )

  task_form.decode(data)
  |> should.be_ok
}

pub fn decode_missing_title_returns_error_test() {
  let data = wisp.FormData(values: [], files: [])

  task_form.decode(data)
  |> should.be_error
}
