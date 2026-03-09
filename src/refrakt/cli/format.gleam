/// Run `gleam format` on generated files.
///
@external(erlang, "refrakt_format_ffi", "format_files")
pub fn format_files(paths: List(String)) -> Nil
