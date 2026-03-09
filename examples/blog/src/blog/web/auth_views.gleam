import gleam/list
import lustre/attribute.{class, href, name, type_, value}
import lustre/element.{type Element, text}
import lustre/element/html.{a, button, div, form, h1, input, label, p, section}

pub fn login_view(
  email: String,
  errors: List(#(String, String)),
) -> Element(Nil) {
  section([class("auth-form")], [
    h1([], [text("Log In")]),
    form([attribute.action("/login"), attribute.method("post")], [
      div([class("field")], [
        label([], [text("Email")]),
        input([type_("email"), name("email"), value(email)]),
        field_error(errors, "email"),
      ]),
      div([class("field")], [
        label([], [text("Password")]),
        input([type_("password"), name("password")]),
        field_error(errors, "password"),
      ]),
      button([type_("submit"), class("btn")], [text("Log In")]),
    ]),
    p([], [
      text("Don't have an account? "),
      a([href("/register")], [text("Register")]),
    ]),
  ])
}

pub fn register_view(
  email: String,
  errors: List(#(String, String)),
) -> Element(Nil) {
  section([class("auth-form")], [
    h1([], [text("Register")]),
    form([attribute.action("/register"), attribute.method("post")], [
      div([class("field")], [
        label([], [text("Email")]),
        input([type_("email"), name("email"), value(email)]),
        field_error(errors, "email"),
      ]),
      div([class("field")], [
        label([], [text("Password")]),
        input([type_("password"), name("password")]),
        field_error(errors, "password"),
      ]),
      div([class("field")], [
        label([], [text("Confirm Password")]),
        input([type_("password"), name("password_confirmation")]),
        field_error(errors, "password_confirmation"),
      ]),
      button([type_("submit"), class("btn")], [text("Register")]),
    ]),
    p([], [
      text("Already have an account? "),
      a([href("/login")], [text("Log In")]),
    ]),
  ])
}

fn field_error(errors: List(#(String, String)), field: String) -> Element(Nil) {
  case list.find(errors, fn(e) { e.0 == field }) {
    Ok(#(_, message)) -> p([class("error")], [text(message)])
    Error(_) -> text("")
  }
}
