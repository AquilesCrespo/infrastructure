# Rust: CLI or background worker

[Documentation index](../README.md) | [Project README](../../README.md)

Follow the [shared setup guidance](./README.md) first. Run infrastructure commands
from the repository root and project commands from your application directory.

Requires Rust and Cargo, normally installed through rustup.

```sh
cargo new rust-worker
cd rust-worker
cargo add tokio --features macros,rt-multi-thread
cargo add sqlx --no-default-features --features runtime-tokio,postgres
cargo add redis --features tokio-comp
cargo add dotenvy
cargo check
cargo run
cargo test
```

Create a private `.env` for your application:

```dotenv
DATABASE_URL=postgres://dev_user:REPLACE_WITH_POSTGRES_PASSWORD@127.0.0.1:5432/local_pg_db
REDIS_URL=redis://127.0.0.1:6379
```

URI usernames/passwords must be percent-encoded if they contain reserved
characters. Cargo does not load `.env` automatically: explicitly load it using
`dotenvy`, or supply environment variables through your launcher.
The generated project still prints "Hello, world!" until you implement it.
Add a Tokio async entry point, a SQLx PostgreSQL pool, and an async Redis client
when implementing worker logic; propagate initialization and query errors.
Use SQLx migrations for the application's schema. Add `axum` if the Rust project
also needs an HTTP API. Rust tools that do not use network services need none of
these database dependencies or containers.
