import blog/context.{type Context}
import blog/data/user_repo
import blog/domain/user.{type User}
import gleam/int
import gleam/result
import wisp.{type Request, type Response}

/// Extract the current user from the session cookie.
pub fn get_current_user(req: Request, ctx: Context) -> Result(User, Nil) {
  use user_id_str <- result.try(wisp.get_cookie(req, "_user_id", wisp.Signed))
  use user_id <- result.try(
    int.parse(user_id_str)
    |> result.replace_error(Nil),
  )
  user_repo.get_by_id(ctx.db, user_id)
}

/// Middleware that requires authentication.
/// Redirects to /login if no valid session.
pub fn require_auth(
  req: Request,
  ctx: Context,
  next: fn(User) -> Response,
) -> Response {
  case get_current_user(req, ctx) {
    Ok(user) -> next(user)
    Error(_) -> wisp.redirect("/login")
  }
}
