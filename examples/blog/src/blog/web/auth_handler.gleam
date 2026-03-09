import blog/context.{type Context}
import blog/data/user_repo
import blog/domain/auth
import blog/web/auth_views
import blog/web/error_handler
import blog/web/forms/auth_form
import blog/web/layouts/root_layout
import gleam/int
import refrakt/flash
import wisp.{type Request, type Response}

pub fn login_page(_req: Request, _ctx: Context) -> Response {
  auth_views.login_view("", [])
  |> root_layout.wrap("Log In")
  |> wisp.html_response(200)
}

pub fn login(req: Request, ctx: Context) -> Response {
  use form_data <- wisp.require_form(req)

  case auth_form.decode_login(form_data) {
    Error(errors) ->
      auth_views.login_view("", errors)
      |> root_layout.wrap("Log In")
      |> wisp.html_response(422)

    Ok(params) ->
      case user_repo.get_by_email(ctx.db, params.email) {
        Error(_) ->
          auth_views.login_view(params.email, [
            #("email", "Invalid email or password"),
          ])
          |> root_layout.wrap("Log In")
          |> wisp.html_response(422)

        Ok(user) ->
          case auth.verify_password(params.password, user.hashed_password) {
            False ->
              auth_views.login_view(params.email, [
                #("email", "Invalid email or password"),
              ])
              |> root_layout.wrap("Log In")
              |> wisp.html_response(422)

            True ->
              wisp.redirect("/")
              |> wisp.set_cookie(
                req,
                "_user_id",
                int.to_string(user.id),
                wisp.Signed,
                60 * 60 * 24 * 7,
              )
              |> flash.set_flash(req, "info", "Logged in")
          }
      }
  }
}

pub fn register_page(_req: Request, _ctx: Context) -> Response {
  auth_views.register_view("", [])
  |> root_layout.wrap("Register")
  |> wisp.html_response(200)
}

pub fn register(req: Request, ctx: Context) -> Response {
  use form_data <- wisp.require_form(req)

  case auth_form.decode_register(form_data) {
    Error(errors) ->
      auth_views.register_view("", errors)
      |> root_layout.wrap("Register")
      |> wisp.html_response(422)

    Ok(params) -> {
      let hashed = auth.hash_password(params.password)
      case user_repo.create(ctx.db, params.email, hashed) {
        Ok(user) ->
          wisp.redirect("/")
          |> wisp.set_cookie(
            req,
            "_user_id",
            int.to_string(user.id),
            wisp.Signed,
            60 * 60 * 24 * 7,
          )
          |> flash.set_flash(req, "info", "Account created")

        Error(_) ->
          auth_views.register_view(params.email, [
            #("email", "Could not create account"),
          ])
          |> root_layout.wrap("Register")
          |> wisp.html_response(422)
      }
    }
  }
}

pub fn logout(req: Request, _ctx: Context) -> Response {
  wisp.redirect("/")
  |> wisp.set_cookie(req, "_user_id", "", wisp.Signed, 0)
  |> flash.set_flash(req, "info", "Logged out")
}
