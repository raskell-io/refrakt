import blog/domain/auth
import gleam/string
import gleeunit/should

pub fn hash_password_round_trip_test() {
  let assert Ok(hash) = auth.hash_password("secret123")
  auth.verify_password("secret123", hash)
  |> should.be_true
}

pub fn wrong_password_test() {
  let assert Ok(hash) = auth.hash_password("secret123")
  auth.verify_password("wrong", hash)
  |> should.be_false
}

pub fn hash_uses_argon2id_test() {
  let assert Ok(hash) = auth.hash_password("secret123")
  string.starts_with(hash, "$argon2id$")
  |> should.be_true
}

pub fn hashes_are_salted_test() {
  let assert Ok(first) = auth.hash_password("secret123")
  let assert Ok(second) = auth.hash_password("secret123")
  first
  |> should.not_equal(second)
}

pub fn malformed_hash_never_matches_test() {
  auth.verify_password("secret123", "not-a-hash")
  |> should.be_false
}
