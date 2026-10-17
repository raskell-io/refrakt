//// Cross-site request forgery (CSRF) protection.
////
//// A CSRF attack is a page on another site submitting a form to your app,
//// riding on the visitor's session cookie. `protect` stops it by asking
//// the browser where an unsafe request (POST, PUT, PATCH, DELETE) came
//// from, and answering `403 Forbidden` when it came from another site:
////
//// 1. `Sec-Fetch-Site`, sent by all current browsers over HTTPS and to
////    localhost. `same-origin` and `none` (typed or bookmarked by the
////    user) pass; `same-site` and `cross-site` are rejected.
//// 2. Otherwise `Origin`, compared with the `Host` header.
//// 3. Otherwise `Referer`, compared with the `Host` header.
//// 4. A request with none of these did not come from a browser page
////    (curl, another server, a mobile app) or came from a very old
////    browser. It is let through with its `cookie` header removed, so it
////    cannot act as the signed-in user.
////
//// Browsers set these headers themselves and pages cannot forge them, so
//// no token has to be threaded through your forms. This is the approach
//// of Go's `http.CrossOriginProtection` and Wisp's
//// `csrf_known_header_protection`, with `Sec-Fetch-Site` support and a
//// 403 status. Keep GET and HEAD handlers free of side effects: they
//// are never checked.
////
//// Behind a reverse proxy, forward the original `Host` header (nginx:
//// `proxy_set_header Host $host;`). Browsers on plain HTTP do not send
//// `Sec-Fetch-Site`, and the `Origin` check needs the host the browser
//// saw.
////
//// ## Example
////
//// ```gleam
//// fn middleware(req: Request, next: fn(Request) -> Response) -> Response {
////   let req = wisp.method_override(req)
////   use <- wisp.log_request(req)
////   use req <- csrf.protect(req)
////   next(req)
//// }
//// ```
////

import gleam/http.{type Method}
import gleam/http/request.{type Request}
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import gleam/uri
import wisp.{type Response}

/// What `check` decided about a request.
pub type Verdict {
  /// A safe method, or an unsafe one sent by a page on this site.
  Allowed
  /// An unsafe request without any browser provenance headers. It may go
  /// ahead, but without cookies.
  AllowedWithoutCookies
  /// An unsafe request sent by a page on another site.
  Rejected(reason: String)
}

/// Reject cross-site unsafe requests with `403 Forbidden`, and strip the
/// cookies from unsafe requests that carry no provenance headers.
pub fn protect(
  req: Request(body),
  next: fn(Request(body)) -> Response,
) -> Response {
  case check(req) {
    Allowed -> next(req)
    AllowedWithoutCookies -> next(without_cookies(req))
    Rejected(reason) -> {
      wisp.log_warning("CSRF check failed: " <> reason)
      wisp.response(403)
      |> wisp.string_body("Forbidden: cross-site request")
    }
  }
}

/// Decide whether a request may go ahead. `protect` acts on this verdict;
/// use `check` directly to build your own response.
pub fn check(req: Request(body)) -> Verdict {
  case is_safe(req.method) {
    True -> Allowed
    False ->
      case request.get_header(req, "sec-fetch-site") {
        Ok("same-origin") | Ok("none") -> Allowed
        Ok(site) -> Rejected("Sec-Fetch-Site is " <> site)
        Error(_) ->
          case request.get_header(req, "origin") {
            Ok(origin) -> check_source(req, "Origin", origin)
            Error(_) ->
              case request.get_header(req, "referer") {
                Ok(referer) -> check_source(req, "Referer", referer)
                Error(_) -> AllowedWithoutCookies
              }
          }
      }
  }
}

fn is_safe(method: Method) -> Bool {
  case method {
    http.Get | http.Head | http.Options | http.Trace -> True
    _ -> False
  }
}

/// Compare the host and port of an `Origin` or `Referer` URL with the
/// `Host` header.
fn check_source(req: Request(body), header: String, url: String) -> Verdict {
  case request.get_header(req, "host") {
    Error(_) -> Rejected("no Host header to compare " <> header <> " with")
    Ok(host) ->
      case authority(url) {
        Ok(source) ->
          case source == string.lowercase(host) {
            True -> Allowed
            False ->
              Rejected(header <> " " <> url <> " does not match " <> host)
          }
        Error(_) -> Rejected(header <> " " <> url <> " is not a URL")
      }
  }
}

/// The `host[:port]` part of a URL, lowercased, written the way a browser
/// writes the `Host` header.
fn authority(url: String) -> Result(String, Nil) {
  use parsed <- result.try(uri.parse(url))
  case parsed.host {
    None | Some("") -> Error(Nil)
    Some(host) -> {
      // IPv6 literals are bracketed in the Host header
      let host = case
        string.contains(host, ":") && !string.starts_with(host, "[")
      {
        True -> "[" <> host <> "]"
        False -> host
      }
      let port = case parsed.port {
        Some(port) -> ":" <> int.to_string(port)
        None -> ""
      }
      Ok(string.lowercase(host) <> port)
    }
  }
}

fn without_cookies(req: Request(body)) -> Request(body) {
  request.Request(
    ..req,
    headers: list.filter(req.headers, fn(header) { header.0 != "cookie" }),
  )
}
