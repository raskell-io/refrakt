/// Development error page.
///
/// Shows a rich HTML error page when a request crashes in dev mode.
/// Includes the error message, stack trace, request details, and
/// matched route information.
///
/// ## Usage
///
/// Replace `wisp.rescue_crashes` in your middleware:
///
/// ```gleam
/// import refrakt/dev_error
///
/// fn middleware(req, next) {
///   let req = wisp.method_override(req)
///   use <- wisp.log_request(req)
///   use <- dev_error.rescue(req)
///   use <- wisp.serve_static(req, under: "/static", from: priv_static())
///   next(req)
/// }
/// ```
///
import exception
import gleam/http
import gleam/list
import gleam/option
import gleam/string
import wisp.{type Request, type Response}

/// Rescue crashes and show a detailed error page in development.
/// In production (when the handler doesn't crash), this is transparent.
pub fn rescue(req: Request, handler: fn() -> Response) -> Response {
  case exception.rescue(handler) {
    Ok(response) -> response
    Error(error) -> {
      let error_str = string.inspect(error)
      let trace = format_stacktrace(error)
      render_error_page(req, error_str, trace)
    }
  }
}

fn render_error_page(
  req: Request,
  error: String,
  stacktrace: String,
) -> Response {
  let method = http.method_to_string(req.method) |> string.uppercase
  let path = req.path
  let query = case req.query {
    option.Some(q) -> "?" <> q
    option.None -> ""
  }

  let headers_html =
    req.headers
    |> list.map(fn(h) {
      let #(name, value) = h
      "<tr><td class=\"header-name\">"
      <> escape_html(name)
      <> "</td><td>"
      <> escape_html(value)
      <> "</td></tr>"
    })
    |> string.join("\n")

  let html = "<!doctype html>
<html>
<head>
  <meta charset=\"utf-8\">
  <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">
  <title>500 — Server Error</title>
  <style>" <> error_page_css() <> "</style>
</head>
<body>
  <div class=\"container\">
    <header>
      <span class=\"badge\">500</span>
      <span class=\"method\">" <> method <> "</span>
      <span class=\"path\">" <> escape_html(path <> query) <> "</span>
    </header>

    <section class=\"error-section\">
      <h2>Error</h2>
      <pre class=\"error-message\">" <> escape_html(error) <> "</pre>
    </section>

    <section class=\"trace-section\">
      <h2>Stack Trace</h2>
      <pre class=\"stacktrace\">" <> escape_html(stacktrace) <> "</pre>
    </section>

    <section class=\"request-section\">
      <h2>Request</h2>
      <table>
        <tr><td class=\"header-name\">Method</td><td>" <> method <> "</td></tr>
        <tr><td class=\"header-name\">Path</td><td>" <> escape_html(path) <> "</td></tr>
      </table>
    </section>

    <section class=\"headers-section\">
      <h2>Headers</h2>
      <table>
        " <> headers_html <> "
      </table>
    </section>

    <footer>
      <p>Refrakt dev error page — this is only shown in development.</p>
      <p>Replace <code>dev_error.rescue</code> with <code>wisp.rescue_crashes</code> in production.</p>
    </footer>
  </div>
</body>
</html>"

  wisp.html_response(html, 500)
}

fn error_page_css() -> String {
  "
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      font-family: system-ui, -apple-system, sans-serif;
      background: #1a1a2e;
      color: #e0e0e0;
      line-height: 1.6;
    }
    .container {
      max-width: 960px;
      margin: 0 auto;
      padding: 2rem 1.5rem;
    }
    header {
      display: flex;
      align-items: center;
      gap: 0.75rem;
      margin-bottom: 2rem;
      padding-bottom: 1rem;
      border-bottom: 1px solid #333;
    }
    .badge {
      background: #dc2626;
      color: white;
      padding: 0.25rem 0.75rem;
      border-radius: 4px;
      font-weight: 700;
      font-size: 1.25rem;
    }
    .method {
      background: #334155;
      padding: 0.25rem 0.5rem;
      border-radius: 4px;
      font-family: ui-monospace, monospace;
      font-weight: 600;
    }
    .path {
      font-family: ui-monospace, monospace;
      color: #94a3b8;
      font-size: 1.1rem;
    }
    h2 {
      font-size: 0.875rem;
      text-transform: uppercase;
      letter-spacing: 0.05em;
      color: #64748b;
      margin-bottom: 0.5rem;
    }
    section {
      margin-bottom: 1.5rem;
    }
    .error-message {
      background: #2d1b1b;
      border: 1px solid #dc2626;
      border-radius: 6px;
      padding: 1rem;
      font-family: ui-monospace, monospace;
      font-size: 0.9rem;
      overflow-x: auto;
      white-space: pre-wrap;
      word-break: break-word;
      color: #fca5a5;
    }
    .stacktrace {
      background: #1e293b;
      border: 1px solid #334155;
      border-radius: 6px;
      padding: 1rem;
      font-family: ui-monospace, monospace;
      font-size: 0.8rem;
      overflow-x: auto;
      white-space: pre-wrap;
      color: #cbd5e1;
      line-height: 1.8;
    }
    table {
      width: 100%;
      border-collapse: collapse;
      background: #1e293b;
      border: 1px solid #334155;
      border-radius: 6px;
      overflow: hidden;
    }
    td {
      padding: 0.5rem 0.75rem;
      border-bottom: 1px solid #334155;
      font-size: 0.85rem;
    }
    .header-name {
      font-weight: 600;
      color: #94a3b8;
      width: 200px;
      font-family: ui-monospace, monospace;
    }
    footer {
      margin-top: 3rem;
      padding-top: 1rem;
      border-top: 1px solid #333;
      color: #475569;
      font-size: 0.8rem;
    }
    footer code {
      background: #334155;
      padding: 0.1rem 0.4rem;
      border-radius: 3px;
      font-size: 0.8rem;
    }
  "
}

fn escape_html(s: String) -> String {
  s
  |> string.replace("&", "&amp;")
  |> string.replace("<", "&lt;")
  |> string.replace(">", "&gt;")
  |> string.replace("\"", "&quot;")
}

@external(erlang, "refrakt_dev_error_ffi", "format_stacktrace")
fn format_stacktrace(error: exception.Exception) -> String
