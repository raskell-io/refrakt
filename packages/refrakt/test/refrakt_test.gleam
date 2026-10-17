import gleeunit
import gleeunit/should
import refrakt/validate

pub fn main() {
  gleeunit.main()
}

// -- Validation tests ---------------------------------------------------------

pub fn required_empty_string_returns_error_test() {
  []
  |> validate.required("", "title", "Title is required")
  |> should.equal([#("title", "Title is required")])
}

pub fn required_whitespace_only_returns_error_test() {
  []
  |> validate.required("   ", "title", "Title is required")
  |> should.equal([#("title", "Title is required")])
}

pub fn required_present_value_passes_test() {
  []
  |> validate.required("Hello", "title", "Title is required")
  |> should.equal([])
}

pub fn min_length_too_short_returns_error_test() {
  []
  |> validate.min_length("Hi", "title", 3, "Too short")
  |> should.equal([#("title", "Too short")])
}

pub fn min_length_exact_passes_test() {
  []
  |> validate.min_length("Hey", "title", 3, "Too short")
  |> should.equal([])
}

pub fn min_length_skips_when_field_already_has_error_test() {
  [#("title", "Title is required")]
  |> validate.min_length("", "title", 3, "Too short")
  |> should.equal([#("title", "Title is required")])
}

pub fn max_length_too_long_returns_error_test() {
  []
  |> validate.max_length("This is way too long", "title", 10, "Too long")
  |> should.equal([#("title", "Too long")])
}

pub fn max_length_within_limit_passes_test() {
  []
  |> validate.max_length("Short", "title", 10, "Too long")
  |> should.equal([])
}

pub fn inclusion_valid_value_passes_test() {
  []
  |> validate.inclusion("admin", "role", ["admin", "user"], "Invalid role")
  |> should.equal([])
}

pub fn inclusion_invalid_value_returns_error_test() {
  []
  |> validate.inclusion("superuser", "role", ["admin", "user"], "Invalid role")
  |> should.equal([#("role", "Invalid role")])
}

pub fn format_matching_predicate_passes_test() {
  let is_numeric = fn(s) {
    case s {
      "0" | "1" | "2" | "3" | "4" | "5" | "6" | "7" | "8" | "9" -> True
      _ -> False
    }
  }

  []
  |> validate.format("5", "count", is_numeric, "Must be numeric")
  |> should.equal([])
}

pub fn composing_multiple_validators_test() {
  let errors =
    []
    |> validate.required("", "title", "Title is required")
    |> validate.required("Some body", "body", "Body is required")
    |> validate.max_length("Some body", "body", 1000, "Body too long")

  errors
  |> should.equal([#("title", "Title is required")])
}
