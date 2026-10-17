# refrakt_cli

[![Package Version](https://img.shields.io/hexpm/v/refrakt_cli)](https://hex.pm/packages/refrakt_cli)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/refrakt_cli/)

The code generator for [Refrakt](https://github.com/raskell-io/refrakt), a
convention-first web framework for Gleam. It scaffolds projects and
generates plain Gleam code (handlers, Lustre views, forms, domain types,
repos, migrations and tests) that you own and edit freely.

This is a development tool. Generated apps depend on the small
[`refrakt`](https://hex.pm/packages/refrakt) runtime library and list
`refrakt_cli` as a dev-dependency only; it is never part of your
production build.

## Create a new app

Gleam runs modules from a project's dependencies, so the very first app is
bootstrapped from a throwaway project:

```sh
gleam new refrakt_bootstrap
cd refrakt_bootstrap
gleam add --dev refrakt_cli
gleam run -m refrakt_cli -- new ../my_app --db sqlite   # or --db postgres, or no --db
cd ../my_app
rm -rf ../refrakt_bootstrap
gleam run                                               # http://localhost:4000
```

The generated app already lists `refrakt_cli` under `[dev-dependencies]`,
so from then on every command runs inside the app:

```sh
gleam run -m refrakt_cli -- gen resource posts title:string body:text published:bool
gleam run -m refrakt_cli -- gen auth
gleam run -m refrakt_cli -- migrate
gleam run -m refrakt_cli -- routes
gleam run -m refrakt_cli -- help
```

See the [CLI reference](https://github.com/raskell-io/refrakt/blob/main/docs/cli.md)
for every command and flag.

## License

MIT
