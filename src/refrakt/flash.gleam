/// Flash message helpers built on signed cookies.
///
/// Flash messages are short-lived messages shown once after a redirect.
/// They are stored as signed cookies and cleared after reading.
///
/// ## Example
///
/// ```gleam
/// // In a handler, after creating a post:
/// wisp.redirect("/posts")
/// |> flash.set_flash(req, "info", "Post created")
///
/// // In a layout or component:
/// let message = flash.get_flash(req, "info")
/// ```
///
import wisp.{type Request, type Response}

/// Set a flash message on a response. Uses signed cookies with a short TTL.
pub fn set_flash(
  response: Response,
  req: Request,
  key: String,
  message: String,
) -> Response {
  let cookie_name = "_flash_" <> key
  wisp.set_cookie(response, req, cookie_name, message, wisp.Signed, 60)
}

/// Read a flash message from a request. Returns the message if present.
pub fn get_flash(req: Request, key: String) -> Result(String, Nil) {
  let cookie_name = "_flash_" <> key
  wisp.get_cookie(req, cookie_name, wisp.Signed)
}
