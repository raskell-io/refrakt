/// Email sending abstraction.
///
/// Provides a simple interface for sending emails. In development,
/// emails are logged to the console. In production, plug in an
/// SMTP or API-based adapter.
///
/// ## Usage
///
/// ```gleam
/// import refrakt/mailer
///
/// let email = mailer.new()
///   |> mailer.to("user@example.com")
///   |> mailer.from("noreply@myapp.com")
///   |> mailer.subject("Welcome!")
///   |> mailer.text_body("Thanks for signing up.")
///   |> mailer.html_body("<h1>Welcome!</h1>")
///
/// mailer.deliver(email, mailer.log_adapter())
/// ```
///
import gleam/io
import gleam/string

/// An email message.
pub type Email {
  Email(
    to: String,
    from: String,
    subject: String,
    text_body: String,
    html_body: String,
    reply_to: String,
  )
}

/// Email delivery adapter.
pub type Adapter =
  fn(Email) -> Result(Nil, String)

/// Create a new empty email.
pub fn new() -> Email {
  Email(
    to: "",
    from: "",
    subject: "",
    text_body: "",
    html_body: "",
    reply_to: "",
  )
}

/// Set the recipient.
pub fn to(email: Email, address: String) -> Email {
  Email(..email, to: address)
}

/// Set the sender.
pub fn from(email: Email, address: String) -> Email {
  Email(..email, from: address)
}

/// Set the subject line.
pub fn subject(email: Email, subject: String) -> Email {
  Email(..email, subject: subject)
}

/// Set the plain text body.
pub fn text_body(email: Email, body: String) -> Email {
  Email(..email, text_body: body)
}

/// Set the HTML body.
pub fn html_body(email: Email, body: String) -> Email {
  Email(..email, html_body: body)
}

/// Set the reply-to address.
pub fn reply_to(email: Email, address: String) -> Email {
  Email(..email, reply_to: address)
}

/// Deliver an email using the given adapter.
pub fn deliver(email: Email, adapter: Adapter) -> Result(Nil, String) {
  adapter(email)
}

/// Log adapter — prints emails to console. Use in development.
pub fn log_adapter() -> Adapter {
  fn(email: Email) -> Result(Nil, String) {
    io.println(string.join(
      [
        "",
        "=== EMAIL ===",
        "To:      " <> email.to,
        "From:    " <> email.from,
        "Subject: " <> email.subject,
        "---",
        email.text_body,
        "=============",
        "",
      ],
      "\n",
    ))
    Ok(Nil)
  }
}
