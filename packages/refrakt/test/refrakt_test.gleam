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

pub fn email_valid_address_passes_test() {
  []
  |> validate.email("jane@example.com", "email", "Invalid email")
  |> should.equal([])
}

pub fn email_trims_surrounding_whitespace_test() {
  []
  |> validate.email("  jane@example.com  ", "email", "Invalid email")
  |> should.equal([])
}

pub fn email_missing_at_sign_returns_error_test() {
  []
  |> validate.email("jane.example.com", "email", "Invalid email")
  |> should.equal([#("email", "Invalid email")])
}

pub fn email_multiple_at_signs_returns_error_test() {
  []
  |> validate.email("jane@example@com", "email", "Invalid email")
  |> should.equal([#("email", "Invalid email")])
}

pub fn email_empty_local_part_returns_error_test() {
  []
  |> validate.email("@example.com", "email", "Invalid email")
  |> should.equal([#("email", "Invalid email")])
}

pub fn email_empty_returns_error_test() {
  []
  |> validate.email("", "email", "Invalid email")
  |> should.equal([#("email", "Invalid email")])
}

pub fn email_domain_without_dot_returns_error_test() {
  []
  |> validate.email("jane@example", "email", "Invalid email")
  |> should.equal([#("email", "Invalid email")])
}

pub fn email_domain_with_empty_label_returns_error_test() {
  []
  |> validate.email("jane@example..com", "email", "Invalid email")
  |> should.equal([#("email", "Invalid email")])
}

pub fn email_local_part_with_space_returns_error_test() {
  []
  |> validate.email("jane doe@example.com", "email", "Invalid email")
  |> should.equal([#("email", "Invalid email")])
}

pub fn int_between_in_range_passes_test() {
  []
  |> validate.int_between("5", "age", 1, 10, "Out of range")
  |> should.equal([])
}

pub fn int_between_lower_bound_passes_test() {
  []
  |> validate.int_between("1", "age", 1, 10, "Out of range")
  |> should.equal([])
}

pub fn int_between_upper_bound_passes_test() {
  []
  |> validate.int_between("10", "age", 1, 10, "Out of range")
  |> should.equal([])
}

pub fn int_between_trims_whitespace_test() {
  []
  |> validate.int_between(" 5 ", "age", 1, 10, "Out of range")
  |> should.equal([])
}

pub fn int_between_below_range_returns_error_test() {
  []
  |> validate.int_between("0", "age", 1, 10, "Out of range")
  |> should.equal([#("age", "Out of range")])
}

pub fn int_between_above_range_returns_error_test() {
  []
  |> validate.int_between("11", "age", 1, 10, "Out of range")
  |> should.equal([#("age", "Out of range")])
}

pub fn int_between_not_a_number_returns_error_test() {
  []
  |> validate.int_between("five", "age", 1, 10, "Out of range")
  |> should.equal([#("age", "Out of range")])
}

pub fn int_between_empty_returns_error_test() {
  []
  |> validate.int_between("", "age", 1, 10, "Out of range")
  |> should.equal([#("age", "Out of range")])
}

pub fn int_between_skips_when_field_already_has_error_test() {
  [#("age", "Age is required")]
  |> validate.int_between("", "age", 1, 10, "Out of range")
  |> should.equal([#("age", "Age is required")])
}

pub fn float_between_in_range_passes_test() {
  []
  |> validate.float_between("2.5", "weight", 1.0, 3.0, "Out of range")
  |> should.equal([])
}

pub fn float_between_bounds_are_inclusive_test() {
  []
  |> validate.float_between("1.0", "weight", 1.0, 3.0, "Out of range")
  |> should.equal([])

  []
  |> validate.float_between("3.0", "weight", 1.0, 3.0, "Out of range")
  |> should.equal([])
}

pub fn float_between_below_range_returns_error_test() {
  []
  |> validate.float_between("0.9", "weight", 1.0, 3.0, "Out of range")
  |> should.equal([#("weight", "Out of range")])
}

pub fn float_between_above_range_returns_error_test() {
  []
  |> validate.float_between("3.1", "weight", 1.0, 3.0, "Out of range")
  |> should.equal([#("weight", "Out of range")])
}

pub fn float_between_not_a_number_returns_error_test() {
  []
  |> validate.float_between("heavy", "weight", 1.0, 3.0, "Out of range")
  |> should.equal([#("weight", "Out of range")])
}

pub fn float_between_skips_when_field_already_has_error_test() {
  [#("weight", "Weight is required")]
  |> validate.float_between("", "weight", 1.0, 3.0, "Out of range")
  |> should.equal([#("weight", "Weight is required")])
}

pub fn confirmation_matching_values_pass_test() {
  []
  |> validate.confirmation(
    "hunter2!",
    "hunter2!",
    "password",
    "Passwords do not match",
  )
  |> should.equal([])
}

pub fn confirmation_mismatched_values_return_error_test() {
  []
  |> validate.confirmation(
    "hunter2!",
    "hunter3!",
    "password",
    "Passwords do not match",
  )
  |> should.equal([#("password", "Passwords do not match")])
}

pub fn confirmation_is_case_sensitive_test() {
  []
  |> validate.confirmation(
    "Secret",
    "secret",
    "password",
    "Passwords do not match",
  )
  |> should.equal([#("password", "Passwords do not match")])
}

pub fn confirmation_does_not_trim_test() {
  []
  |> validate.confirmation(
    " secret ",
    "secret",
    "password",
    "Passwords do not match",
  )
  |> should.equal([#("password", "Passwords do not match")])
}

pub fn confirmation_skips_when_field_already_has_error_test() {
  [#("password", "Password is required")]
  |> validate.confirmation("", "", "password", "Passwords do not match")
  |> should.equal([#("password", "Password is required")])
}

pub fn composing_email_and_integer_range_validators_test() {
  let errors =
    []
    |> validate.email("jane", "email", "Invalid email")
    |> validate.int_between("200", "age", 13, 120, "Age must be 13 or more")

  errors
  |> should.equal([
    #("age", "Age must be 13 or more"),
    #("email", "Invalid email"),
  ])
}
