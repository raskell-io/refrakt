import gleeunit/should
import refrakt/token

const secret = "test-secret-key"

pub fn verify_valid_token_returns_data_test() {
  let tok = token.sign(secret, "user:verify", "42", max_age_seconds: 3600)

  token.verify(secret, "user:verify", tok, max_age_seconds: 3600)
  |> should.equal(Ok("42"))
}

pub fn verify_data_containing_dots_test() {
  let tok =
    token.sign(secret, "reset", "jane.doe@example.com", max_age_seconds: 60)

  token.verify(secret, "reset", tok, max_age_seconds: 60)
  |> should.equal(Ok("jane.doe@example.com"))
}

pub fn verify_wrong_purpose_returns_invalid_test() {
  let tok = token.sign(secret, "user:verify", "42", max_age_seconds: 3600)

  token.verify(secret, "password:reset", tok, max_age_seconds: 3600)
  |> should.equal(Error(token.Invalid))
}

pub fn verify_wrong_secret_returns_invalid_test() {
  let tok = token.sign(secret, "user:verify", "42", max_age_seconds: 3600)

  token.verify("other-secret", "user:verify", tok, max_age_seconds: 3600)
  |> should.equal(Error(token.Invalid))
}

pub fn verify_expired_token_returns_expired_test() {
  let tok = token.sign(secret, "user:verify", "42", max_age_seconds: 3600)

  token.verify(secret, "user:verify", tok, max_age_seconds: -1)
  |> should.equal(Error(token.Expired))
}

pub fn verify_garbage_returns_bad_format_test() {
  token.verify(secret, "user:verify", "garbage", max_age_seconds: 3600)
  |> should.equal(Error(token.BadFormat))
}
