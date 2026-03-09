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
```

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
