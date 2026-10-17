import argus
import gleam/result

/// Hash a password with Argon2id, using a fresh random salt and the
/// OWASP-recommended cost settings. The result is a self-describing
/// string (`$argon2id$...`) holding the salt and parameters, so it
/// can be stored as-is and checked later with `verify_password`.
pub fn hash_password(password: String) -> Result(String, Nil) {
  argus.hasher()
  |> argus.hash(password)
  |> result.map(fn(output) { output.encoded_hash })
  |> result.replace_error(Nil)
}

/// Check a password against a hash from `hash_password`. The comparison
/// is constant-time; a malformed hash never matches.
pub fn verify_password(password: String, hash: String) -> Bool {
  argus.verify(hash, password)
  |> result.unwrap(False)
}
