# Local development infrastructure

## Purpose and coverage

This stack is a shared infrastructure foundation for most web and backend
development. It supplies supporting services, not a complete application
development environment. Add services only when an application needs them.

| Development need | Available services or tooling |
|---|---|
| Relational databases | MySQL and PostgreSQL |
| Document storage | MongoDB |
| Cache and Redis-backed workflows | Redis |
| Email testing | Mailpit |
| S3-compatible storage testing | SeaweedFS |
| External API simulation | WireMock, including failures, delays, pagination, and retries |
| Database administration | Adminer, Mongo Express, and RedisInsight |
| Database monitoring | Prometheus, database exporters, and Grafana dashboards |
| Distributed tracing | Jaeger; applications must emit OpenTelemetry traces |
| Data workflows | Repeatable demo seeds, backup/restore, and opt-in scheduled backups |
| Diagnostics and isolation | Doctor command, separate Compose projects, and configurable host ports |

Your application still owns its runtime, debugger, migrations, realistic seeds,
tests, and instrumentation. See the [application guides](./docs/examples/README.md)
for setup examples and the recommended development workflow.

## Quick start

### Prerequisites

- Docker with a running daemon and Docker Compose v2 or newer.
- Bash and GNU coreutils for the diagnostic and database scripts.
- Your application's runtime/SDK, installed separately.

For native Windows/PowerShell setup and commands, use the
[Windows guide](./docs/windows.md); the Bash examples below are for Linux/WSL.

The optional backup timer requires Linux systemd user services and `flock`.
Integration tests have additional requirements in the
[verification guide](./docs/verification.md).

Run commands from the repository root:

```sh
# First setup only: do not overwrite an existing .env.
cp -n .env.example .env
```

Edit `.env` to replace placeholder credentials, then:

```sh
docker compose --profile "*" config --quiet
docker compose up -d
bash scripts/doctor.sh
```

The default startup includes MySQL, Redis, PostgreSQL, MongoDB, and Mailpit.
For a smaller stack, start specific services, for example:

```sh
docker compose up -d postgres redis mailpit
bash scripts/doctor.sh postgres redis mailpit
```

Doctor requires all core services by default; pass service names to check only
your smaller stack. See [diagnostics](./docs/troubleshooting.md).
Optional tools are selected through [profiles](./docs/configuration.md#profiles).
For everyday work, prefer the [lightweight workflow](./docs/configuration.md#recommended-lightweight-workflow)
over starting all services.
Host/container addresses and UI URLs are in the
[connection reference](./docs/connections.md).

### Stop without deleting data

```sh
docker compose --profile "*" stop
# Remove containers and networks while preserving named volumes:
docker compose --profile "*" down
```

## Safety and scope

- Do not use `down --volumes` / `down -v` unless you intend to delete local data.
- Keep `.env`, project env files, and backups private and out of source control.
- Back up valuable data before changing database versions or restoring dumps.
- A different Compose project name creates separate volumes, not a copy of data.
- Scheduled backups remain opt-in; installation alone does not enable the timer.

This configuration is not a production deployment. Credentials, exporter
privileges, network access, in-memory trace storage, backup consistency and
recovery, and service availability require a separate production design.
S3-compatible local testing also does not guarantee full AWS S3 behavior parity.

## Documentation

| Guide | What you will find |
|---|---|
| [Documentation index](./docs/README.md) | Task-oriented navigation and repository layout |
| [Configuration and lifecycle](./docs/configuration.md) | Environment settings, image tags, profiles, start/stop commands |
| [Project isolation](./docs/project-isolation.md) | Multiple deployments, host ports, and volume ownership |
| [Connection reference](./docs/connections.md) | Database addresses, UI URLs, and credential variable names |
| [Database workflows](./docs/databases.md) | Demo seeds, backup/restore, scheduling, and retention |
| [Tracing and metrics](./docs/observability.md) | Jaeger, instrumentation, exporters, and Grafana |
| [API mocking](./docs/mocking.md) | WireMock fixtures and failure/retry scenarios |
| [Troubleshooting](./docs/troubleshooting.md) | Doctor checks, limitations, logs, and common failures |
| [Verification](./docs/verification.md) | Regression and isolated integration tests |
| [Windows development](./docs/windows.md) | Native PowerShell commands and opt-in Task Scheduler backups |
| [Application examples](./docs/examples/README.md) | PHP, Node.js, Rust, and .NET project setup |
