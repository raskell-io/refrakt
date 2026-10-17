# Field Types

Field types are used with `refrakt gen resource` to define the
fields of a resource.

## Syntax

```bash
refrakt gen resource <name> <field:type> [field:type ...]
```

Example:

```bash
refrakt gen resource posts title:string body:text published:bool
refrakt gen resource products name:string price:float stock:int
refrakt gen resource events title:string 'starts_on:optional(date)' 'capacity:optional(int)'
```

Quote `optional(...)` specs: the parentheses are shell syntax in bash
and zsh.

Field names are lowercase letters, digits and underscores, starting
with a letter. `id`, `inserted_at` and `updated_at` are taken: every
table has them. An unknown type, a malformed spec or a repeated name is
an error, and nothing is generated.

## Available types

| CLI Type | Gleam Type | HTML Input | Postgres SQL | SQLite SQL |
|----------|-----------|------------|-------------|------------|
| `string` | `String` | `<input type="text">` | `TEXT` | `TEXT` |
| `text` | `String` | `<textarea>` | `TEXT` | `TEXT` |
| `int` | `Int` | `<input type="number">` | `INTEGER` | `INTEGER` |
| `float` | `Float` | `<input type="number">` | `DOUBLE PRECISION` | `REAL` |
| `bool` | `Bool` | `<input type="checkbox">` | `BOOLEAN` | `INTEGER` |
| `date` | `String` | `<input type="text">` | `DATE` | `TEXT` |
| `datetime` | `String` | `<input type="text">` | `TIMESTAMPTZ` | `TEXT` |
| `optional(T)` | `Option(T)` | as for `T`; `optional(bool)` is a `<select>` | `T`, nullable | `T`, nullable |

`T` in `optional(T)` is any type above: `optional(string)`,
`optional(text)`, `optional(int)`, `optional(float)`, `optional(bool)`,
`optional(date)` or `optional(datetime)`.

## How types affect generated code

### `string`

- Form: text input, direct string value
- Validation: `validate.required` generated
- Repo: `pog.text()` / `sqlight.text()` parameter
- Decoder: `decode.string`

### `text`

Same as `string` except the HTML input is a `<textarea>` instead of
a single-line text input. Use for longer content like descriptions
or body text.

### `int`

- Form: number input, parsed with `int.parse`
- Validation: none generated (add your own)
- Repo: `pog.int()` / `sqlight.int()` parameter
- Decoder: `decode.int`

### `float`

- Form: number input, parsed with `float.parse`
- Validation: none generated (add your own)
- Repo: `pog.float()` / `sqlight.float()` parameter
- Decoder: `decode.float`

### `bool`

- Form: checkbox input, checked if value is present
- Validation: none (always has a value: True or False)
- Repo: `pog.bool()` / `sqlight.bool()` parameter
- Decoder: `decode.bool` (Pog) / `sqlight.decode_bool()` (SQLite)

Note: HTML checkboxes only send a value when checked. The form
decoder treats the presence of the field as `True` and absence
as `False`.

### `date` and `datetime`

Stored as strings in Gleam. The SQL type is `DATE` / `TIMESTAMPTZ`
for Postgres and `TEXT` for SQLite. You may want to add proper
date parsing and formatting in your domain layer.

On Postgres the repo reads these columns as text (`starts_on::text`)
and sends them as text for Postgres to cast (`$2::text::date`), so a
value such as `2026-10-17` or `2026-10-17 09:30:00+00` round-trips as a
`String`.

### `optional(T)`

A field that may have no value: `Option(T)` in the domain type, the
form and the params, and a nullable column (no `NOT NULL`).

- Migration: the column type of `T` without `NOT NULL`
- Repo: `pog.nullable(pog.int, params.capacity)` /
  `sqlight.nullable(sqlight.int, params.capacity)`; decoded with
  `decode.optional(decode.int)`. `None` is `NULL`.
- Form: a blank input (after trimming) is `None`; anything else is
  parsed as `T`. Optional fields are never `required`, but a non-blank
  `optional(int)`, `optional(float)` or `optional(bool)` value that does
  not parse is a validation error (422), such as "Capacity must be a
  whole number".
- Form view: `None` renders as an empty input.
- Show view: `None` renders as `—` (an em dash).
- JSON API (`--api`): a missing key or `null` is `None`; `None` is
  encoded as `null` (`json.nullable`). An empty string stays
  `Some("")` in JSON.

#### `optional(bool)`

A checkbox cannot say "not set": an unchecked box sends nothing, just
like an untouched one. An `optional(bool)` field is a `<select>` with a
blank option (`—`, `None`), `Yes` (`true`) and `No` (`false`). Any other
submitted value is a 422 ("... must be yes or no"). In JSON it is
`true`, `false` or `null`.

## Default values in forms

| Type | Empty form value |
|------|-----------------|
| `string` | `""` |
| `text` | `""` |
| `int` | `0` |
| `float` | `0.0` |
| `bool` | `False` |
| `date` | `""` |
| `datetime` | `""` |
| `optional(T)` | `None` |

## All generated columns

Every migration includes these automatic columns in addition to
your fields:

| Column | Postgres | SQLite |
|--------|----------|--------|
| `id` | `SERIAL PRIMARY KEY` | `INTEGER PRIMARY KEY AUTOINCREMENT` |
| `inserted_at` | `TIMESTAMPTZ DEFAULT NOW()` | `TEXT DEFAULT datetime('now')` |
| `updated_at` | `TIMESTAMPTZ DEFAULT NOW()` | `TEXT DEFAULT datetime('now')` |

## Adding custom types

If you need a type not in this list, use `string` and parse it in
your domain layer. The generated form, repo, and migration are
plain Gleam files — modify them to handle any custom type.
