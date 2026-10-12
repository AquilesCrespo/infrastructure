# Documentation

[Project README](../README.md)

This documentation describes the local infrastructure's setup, operation, and
application integration. Run infrastructure commands from the repository root,
not from this directory. Application commands run in the application's directory.
Examples use default ports and placeholder credentials unless stated otherwise.

## Start here

1. Follow the [quick start](../README.md#quick-start).
2. Choose [services and profiles](./configuration.md#profiles).
3. Find the [connection settings](./connections.md) for your application.
4. Follow the relevant [language example](./examples/README.md).

## Guides by task

| Task | Guide |
|---|---|
| Configure environment variables and image tags | [Configuration and lifecycle](./configuration.md) |
| Run multiple independent projects | [Project isolation](./project-isolation.md) |
| Connect an app or database UI | [Connection reference](./connections.md) |
| Seed, back up, or restore databases | [Database workflows](./databases.md) |
| Schedule backups and manage retention | [Scheduled backups](./databases.md#opt-in-scheduled-backups-and-retention) |
| Inspect traces and database metrics | [Tracing and metrics](./observability.md) |
| Simulate external APIs and failure responses | [API mocking](./mocking.md) |
| Diagnose configuration or connection failures | [Troubleshooting](./troubleshooting.md) |
| Validate changes without modifying development data | [Verification](./verification.md) |
| Configure Copilot and browser automation | [AI assistant tools](./agent-tools.md) |
| Work on Windows without a Bash shell | [Native Windows development](./windows.md) |

## Application examples

- [PHP / Laravel](./examples/php.md)
- [Node.js / Express](./examples/nodejs.md)
- [Rust CLI and background workers](./examples/rust.md)
- [.NET APIs, console applications, and workers](./examples/dotnet.md)

These are integration instructions, not bundled runnable starter projects.
Applications still need their own migrations, tests, and instrumentation.

## Repository layout

| Location | Responsibility |
|---|---|
| [docker-compose.yml](../docker-compose.yml) | Services, profiles, networks, ports, and data volumes |
| [.env.example](../.env.example) | Environment variable template |
| [scripts/](../scripts/) | Diagnostics and database workflow commands |
| [seeds/](../seeds/) | Repeatable isolated demo data |
| [prometheus/](../prometheus/) | Scrape configuration |
| [grafana/](../grafana/) | Provisioned data sources and dashboards |
| [jaeger/](../jaeger/) | OTLP receiver and trace storage configuration |
| [wiremock/](../wiremock/) | Versioned API mappings and response bodies |
| [tests/](../tests/) | Regression and isolated integration tests |

Detailed instructions have one primary home in the guides above. The project
README retains only the overview, quick start, and essential safety notes.
