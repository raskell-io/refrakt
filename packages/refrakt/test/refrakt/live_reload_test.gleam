import gleam/string
import gleeunit/should
import lustre/element
import refrakt/live_reload

fn render(app_env: Result(String, Nil), port: Result(String, Nil)) -> String {
  live_reload.script_for(app_env:, port:)
  |> element.to_string
}

pub fn script_is_rendered_in_dev_with_a_port_test() {
  let html = render(Ok("dev"), Ok("35729"))

  html |> string.starts_with("<script") |> should.be_true
  html |> string.contains("\":35729/events\"") |> should.be_true
  html |> string.contains("location.reload()") |> should.be_true
}

pub fn script_is_not_rendered_in_prod_test() {
  render(Ok("prod"), Ok("35729")) |> should.equal("")
}

pub fn script_is_not_rendered_in_test_test() {
  render(Ok("test"), Ok("35729")) |> should.equal("")
}

pub fn script_is_not_rendered_without_app_env_test() {
  render(Error(Nil), Ok("35729")) |> should.equal("")
}

pub fn script_is_not_rendered_without_refrakt_dev_test() {
  render(Ok("dev"), Error(Nil)) |> should.equal("")
}

pub fn script_rejects_a_port_that_is_not_a_number_test() {
  render(Ok("dev"), Ok("1;alert(1)")) |> should.equal("")
  render(Ok("dev"), Ok("0")) |> should.equal("")
  render(Ok("dev"), Ok("70000")) |> should.equal("")
}
