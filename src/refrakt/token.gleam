/// Secure, signed, expiring tokens for email verification,
/// password reset, API authentication, and similar flows.
///
/// ## Usage
///
/// ```gleam
/// import refrakt/token
///
/// // Sign a token (e.g., user ID for email verification)
/// let tok = token.sign(secret, "user:verify", "42", max_age_seconds: 3600)
///
/// // Verify and extract the data
/// case token.verify(secret, "user:verify", tok, max_age_seconds: 3600) {
///   Ok(data) -> // data == "42"
///   Error(token.Expired) -> // token expired
///   Error(token.Invalid) -> // signature mismatch or tampered
/// }
/// ```
///
import gleam/bit_array
import gleam/crypto
import gleam/int
import gleam/result
import gleam/string

/// Token verification errors.
pub type TokenError {
  Invalid
  Expired
  BadFormat
}

/// Sign data into a secure token with a purpose and timestamp.
/// The purpose prevents tokens from being used for different actions.
pub fn sign(
  secret: String,
  purpose: String,
  data: String,
  max_age_seconds max_age: Int,
) -> String {
  let timestamp = system_time_seconds()
  let payload = purpose <> "." <> data <> "." <> int.to_string(timestamp)
  let signature = compute_signature(secret, payload)
  payload <> "." <> signature
}

/// Verify a token and extract the data.
/// Returns Error if the token is expired, tampered, or has wrong purpose.
pub fn verify(
  secret: String,
  purpose: String,
  token: String,
  max_age_seconds max_age: Int,
) -> Result(String, TokenError) {
  case string.split(token, ".") {
    [token_purpose, data, timestamp_str, signature] -> {
      // Check purpose
      case token_purpose == purpose {
        False -> Error(Invalid)
        True -> {
          // Verify signature
          let payload = token_purpose <> "." <> data <> "." <> timestamp_str
          let expected = compute_signature(secret, payload)
          case
            crypto.secure_compare(
              bit_array.from_string(signature),
              bit_array.from_string(expected),
            )
          {
            False -> Error(Invalid)
            True -> {
              // Check expiry
              case int.parse(timestamp_str) {
                Error(_) -> Error(BadFormat)
                Ok(timestamp) -> {
                  let now = system_time_seconds()
                  case now - timestamp > max_age {
                    True -> Error(Expired)
                    False -> Ok(data)
                  }
                }
              }
            }
          }
        }
      }
    }
    _ -> Error(BadFormat)
  }
}

fn compute_signature(secret: String, payload: String) -> String {
  crypto.hmac(
    bit_array.from_string(payload),
    crypto.Sha256,
    bit_array.from_string(secret),
  )
  |> bit_array.base16_encode
  |> string.lowercase
}

@external(erlang, "refrakt_rate_limit_ffi", "system_time_seconds")
fn system_time_seconds() -> Int
