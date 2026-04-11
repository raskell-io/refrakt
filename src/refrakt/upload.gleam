/// File upload handling.
///
/// Provides helpers for processing multipart file uploads from
/// Wisp's form data.
///
/// ## Usage
///
/// ```gleam
/// import refrakt/upload
///
/// pub fn create(req: Request, ctx: Context) -> Response {
///   use form_data <- wisp.require_form(req)
///
///   case upload.get_file(form_data, "avatar") {
///     Ok(file) -> {
///       // Save to disk
///       let assert Ok(path) = upload.save(file, to: "priv/uploads")
///       // path is like "priv/uploads/abc123_avatar.jpg"
///     }
///     Error(_) -> // No file uploaded
///   }
/// }
/// ```
///
import gleam/bit_array
import gleam/crypto
import gleam/list
import gleam/result
import gleam/string
import simplifile
import wisp

/// An uploaded file with metadata.
pub type UploadedFile {
  UploadedFile(
    field_name: String,
    file_name: String,
    path: String,
    content_type: String,
  )
}

/// Upload configuration.
pub type UploadConfig {
  UploadConfig(
    max_size_bytes: Int,
    allowed_types: List(String),
    upload_dir: String,
  )
}

/// Default upload config: 10MB max, common image types.
pub fn default_config() -> UploadConfig {
  UploadConfig(
    max_size_bytes: 10_000_000,
    allowed_types: [
      "image/jpeg", "image/png", "image/gif", "image/webp", "application/pdf",
    ],
    upload_dir: "priv/uploads",
  )
}

/// Extract an uploaded file from form data by field name.
pub fn get_file(
  form_data: wisp.FormData,
  field_name: String,
) -> Result(UploadedFile, String) {
  case
    list.find(form_data.files, fn(f) {
      let #(name, _) = f
      name == field_name
    })
  {
    Ok(#(name, uploaded)) ->
      Ok(UploadedFile(
        field_name: name,
        file_name: uploaded.file_name,
        path: uploaded.path,
        content_type: "",
      ))
    Error(_) -> Error("No file uploaded for field: " <> field_name)
  }
}

/// Save an uploaded file to the given directory.
/// Returns the full path of the saved file.
pub fn save(file: UploadedFile, to dest_dir: String) -> Result(String, String) {
  let _ = simplifile.create_directory_all(dest_dir)

  // Generate a unique filename
  let unique = generate_id()
  let ext = get_extension(file.file_name)
  let dest_name = unique <> "_" <> sanitize_filename(file.file_name)
  let dest_path = dest_dir <> "/" <> dest_name

  // Copy the temp file to the destination
  case simplifile.read_bits(file.path) {
    Ok(content) ->
      case simplifile.write_bits(dest_path, content) {
        Ok(_) -> Ok(dest_path)
        Error(_) -> Error("Failed to write file: " <> dest_path)
      }
    Error(_) -> Error("Failed to read uploaded file")
  }
}

/// Generate a random ID for filenames.
fn generate_id() -> String {
  crypto.strong_random_bytes(8)
  |> bit_array.base16_encode
  |> string.lowercase
}

/// Get the file extension from a filename.
fn get_extension(filename: String) -> String {
  case string.split(filename, ".") {
    [_, ..rest] ->
      case list.last(rest) {
        Ok(ext) -> "." <> ext
        Error(_) -> ""
      }
    _ -> ""
  }
}

/// Remove dangerous characters from a filename.
fn sanitize_filename(filename: String) -> String {
  filename
  |> string.replace("/", "_")
  |> string.replace("\\", "_")
  |> string.replace("..", "_")
  |> string.replace("\\0", "_")
}
