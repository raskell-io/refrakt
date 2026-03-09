import blog/domain/auth
import gleeunit/should

pub fn hash_password_test() {
  let hash = auth.hash_password("secret123")
  auth.verify_password("secret123", hash)
  |> should.be_true
}

pub fn wrong_password_test() {
  let hash = auth.hash_password("secret123")
  auth.verify_password("wrong", hash)
  |> should.be_false
}
