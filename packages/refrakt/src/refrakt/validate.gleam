//// Form validation helpers.
////
//// All validators are composable functions that accumulate errors as
//// `List(#(String, String))` where each tuple is `#(field_name, message)`.
////
//// ## Example
////
//// ```gleam
//// let errors =
////   []
////   |> validate.required(title, "title", "Title is required")
////   |> validate.min_length(title, "title", 3, "Title must be at least 3 characters")
////   |> validate.required(body, "body", "Body is required")
//// ```
////

import gleam/float
import gleam/int
import gleam/list
import gleam/string

/// Check that a string value is not empty (after trimming whitespace).
pub fn required(
  errors: List(#(String, String)),
  value: String,
  field: String,
  message: String,
) -> List(#(String, String)) {
  case string.is_empty(string.trim(value)) {
    True -> [#(field, message), ..errors]
    False -> errors
  }
}

/// Check that a string value has at least `min` characters.
/// Skips the check if the field already has an error (avoids duplicate messages).
pub fn min_length(
  errors: List(#(String, String)),
  value: String,
  field: String,
  min: Int,
  message: String,
) -> List(#(String, String)) {
  case has_error(errors, field) {
    True -> errors
    False ->
      case string.length(string.trim(value)) < min {
        True -> [#(field, message), ..errors]
        False -> errors
      }
  }
}

/// Check that a string value has at most `max` characters.
/// Skips the check if the field already has an error.
pub fn max_length(
  errors: List(#(String, String)),
  value: String,
  field: String,
  max: Int,
  message: String,
) -> List(#(String, String)) {
  case has_error(errors, field) {
    True -> errors
    False ->
      case string.length(string.trim(value)) > max {
        True -> [#(field, message), ..errors]
        False -> errors
      }
  }
}

/// Check that a string looks like an email address.
///
/// This is a pragmatic check, not a RFC 5322 parser: the trimmed value must
/// contain exactly one `@`, a non-empty local part without spaces, and a
/// domain with at least two non-empty dot-separated labels. So
/// `"jane@example.com"` passes, while `"jane"`, `"jane@"`, `"@example.com"`,
/// `"jane@example"` and `"jane@example..com"` fail.
///
/// Use it after `required` so that an empty field reports the "required"
/// message instead of the email message.
pub fn email(
  errors: List(#(String, String)),
  value: String,
  field: String,
  message: String,
) -> List(#(String, String)) {
  case is_email(value) {
    True -> errors
    False -> [#(field, message), ..errors]
  }
}

/// Check that a string parses as an integer between `min` and `max`,
/// inclusive on both ends. A value that does not parse as an integer fails
/// the check with the same message.
/// Skips the check if the field already has an error.
pub fn int_between(
  errors: List(#(String, String)),
  value: String,
  field: String,
  min: Int,
  max: Int,
  message: String,
) -> List(#(String, String)) {
  case has_error(errors, field) {
    True -> errors
    False ->
      case int.parse(string.trim(value)) {
        Error(_) -> [#(field, message), ..errors]
        Ok(number) ->
          case number >= min && number <= max {
            True -> errors
            False -> [#(field, message), ..errors]
          }
      }
  }
}

/// Check that a string parses as a float between `min` and `max`, inclusive
/// on both ends. A value that does not parse as a number fails the check with
/// the same message.
/// Skips the check if the field already has an error.
pub fn float_between(
  errors: List(#(String, String)),
  value: String,
  field: String,
  min: Float,
  max: Float,
  message: String,
) -> List(#(String, String)) {
  case has_error(errors, field) {
    True -> errors
    False ->
      case float.parse(string.trim(value)) {
        Error(_) -> [#(field, message), ..errors]
        Ok(number) ->
          case number >=. min && number <=. max {
            True -> errors
            False -> [#(field, message), ..errors]
          }
      }
  }
}

/// Check that `value` equals `confirmation`, for password and password-repeat
/// fields. The two values are compared as given: no trimming, because
/// passwords may legitimately start or end with a space.
/// Skips the check if the field already has an error.
pub fn confirmation(
  errors: List(#(String, String)),
  value: String,
  confirmation: String,
  field: String,
  message: String,
) -> List(#(String, String)) {
  case has_error(errors, field) {
    True -> errors
    False ->
      case value == confirmation {
        True -> errors
        False -> [#(field, message), ..errors]
      }
  }
}

/// Check that a string value matches one of the allowed values.
pub fn inclusion(
  errors: List(#(String, String)),
  value: String,
  field: String,
  allowed: List(String),
  message: String,
) -> List(#(String, String)) {
  case list.contains(allowed, value) {
    True -> errors
    False -> [#(field, message), ..errors]
  }
}

/// Check that a string value matches a format predicate.
pub fn format(
  errors: List(#(String, String)),
  value: String,
  field: String,
  predicate: fn(String) -> Bool,
  message: String,
) -> List(#(String, String)) {
  case predicate(value) {
    True -> errors
    False -> [#(field, message), ..errors]
  }
}

fn has_error(errors: List(#(String, String)), field: String) -> Bool {
  list.any(errors, fn(e) { e.0 == field })
}

fn is_email(value: String) -> Bool {
  case string.split(string.trim(value), "@") {
    [local, domain] ->
      case string.is_empty(local) || string.contains(local, " ") {
        True -> False
        False -> is_domain(domain)
      }
    _ -> False
  }
}

fn is_domain(domain: String) -> Bool {
  let labels = string.split(domain, ".")
  case list.length(labels) > 1 {
    False -> False
    True -> list.all(labels, fn(label) { !string.is_empty(label) })
  }
}
