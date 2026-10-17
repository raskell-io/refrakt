/// Shared types for the CLI.
///
import gleam/option.{type Option}

pub type DbChoice {
  Postgres
  Sqlite
  NoDb
}

/// The parent of a resource generated with `--belongs-to <parent>`.
///
/// For `gen resource comments body:text --belongs-to posts`:
/// `Relation(plural: "posts", singular: "post", type_name: "Post",
/// table: "posts", field: "post_id", label: Some("title"))`.
pub type Relation {
  Relation(
    /// The parent resource as given to `--belongs-to`; its routes live
    /// under `/<plural>`.
    plural: String,
    singular: String,
    type_name: String,
    /// The parent's table, named the way `gen resource` names tables.
    table: String,
    /// The foreign key column and field of the child, `<singular>_id`.
    field: String,
    /// The parent's first required string field, used to label parents in
    /// a `<select>`; `None` labels them by id.
    label: Option(String),
  )
}
