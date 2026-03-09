import gleam/bit_array
import gleam/crypto
import gleam/string

/// Hash a password using a simple HMAC-based approach.
/// Replace with a proper bcrypt/argon2 library for production.
pub fn hash_password(password: String) -> String {
  crypto.hash(crypto.Sha256, bit_array.from_string(password))
  |> bit_array.base16_encode
  |> string.lowercase
}

/// Verify a password against a hash.
pub fn verify_password(password: String, hash: String) -> Bool {
  hash_password(password) == hash
}
