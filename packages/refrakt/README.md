# refrakt

[![Package Version](https://img.shields.io/hexpm/v/refrakt)](https://hex.pm/packages/refrakt)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/refrakt/)

Runtime helpers for [Refrakt](https://github.com/raskell-io/refrakt), a
convention-first web framework for Gleam built on Wisp, Lustre and Mist.

This is the small library that Refrakt apps import at runtime. The code
generator lives in the separate [`refrakt_cli`](https://hex.pm/packages/refrakt_cli)
package, which apps only need as a dev-dependency.

```sh
gleam add refrakt
gleam add --dev refrakt_cli
```

New to Refrakt? Start with the
[installation guide](https://github.com/raskell-io/refrakt/blob/main/docs/installation.md)
and the [tutorial](https://github.com/raskell-io/refrakt/blob/main/docs/tutorial.md).

## Modules

| Module | What it does |
|--------|--------------|
| `refrakt/validate` | Composable validators that return `List(#(String, String))` errors |
| `refrakt/flash` | Flash messages on signed cookies |
| `refrakt/migrate` | Runs SQL migration files and tracks them in a `_migrations` table |
| `refrakt/testing` | Request builders for handler tests |
| `refrakt/dev_error` | Development error page |
| `refrakt/jobs` | Background jobs in OTP processes, with a concurrency limit |
| `refrakt/token` | Signed, expiring tokens bound to a purpose |
| `refrakt/mailer` | Email builder with pluggable delivery adapters |
| `refrakt/paginate` | Pagination helpers for list views |
| `refrakt/upload` | Multipart file upload handling |
| `refrakt/cors` | CORS middleware |
| `refrakt/rate_limit` | Sliding-window rate-limiting middleware |
| `refrakt/pubsub` | Topic-based publish/subscribe |
| `refrakt/telemetry` | Request counts, response times and error rates |

```gleam
import refrakt/validate

pub fn validate_post(title: String, body: String) -> List(#(String, String)) {
  []
  |> validate.required(title, "title", "Title is required")
  |> validate.max_length(title, "title", 200, "Title is too long")
  |> validate.required(body, "body", "Body is required")
}
```

Further documentation can be found at <https://hexdocs.pm/refrakt>.

## License

MIT
