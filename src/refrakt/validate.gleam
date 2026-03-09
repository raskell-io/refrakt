/// Form validation helpers.
///
/// All validators are composable functions that accumulate errors as
/// `List(#(String, String))` where each tuple is `#(field_name, message)`.
///
/// ## Example
///
/// ```gleam
/// let errors =
///   []
///   |> validate.required(title, "title", "Title is required")
///   |> validate.min_length(title, "title", 3, "Title must be at least 3 characters")
///   |> validate.required(body, "body", "Body is required")
/// ```
///
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
  case list.any(errors, fn(e) { e.0 == field }) {
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
  case list.any(errors, fn(e) { e.0 == field }) {
    True -> errors
    False ->
      case string.length(string.trim(value)) > max {
        True -> [#(field, message), ..errors]
        False -> errors
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
