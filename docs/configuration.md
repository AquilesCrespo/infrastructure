# Configuration and lifecycle

[Documentation index](./README.md) | [Project README](../README.md)

All commands in this guide run from the repository root.

## Environment setup

Copy `.env.example` to `.env` if needed, then replace the placeholder passwords.
Keep `.env` private; it is ignored by Git. Credential and database-name variables
must be nonempty: Compose validates them even for profiles that are not enabled.
Image-tag variables use the Compose defaults when missing or empty.

## Choosing image tags

Every service has its own tag variable in `.env` and `.env.example`:

| Variable | Default |
|---|---|
| `MYSQL_TAG` | `8.4` |
| `REDIS_TAG` | `alpine` |
| `POSTGRES_TAG` | `16-alpine` |
| `MONGO_TAG` | `7.0` |
| `MAILPIT_TAG` | `latest` |
| `PROMETHEUS_TAG` | `latest` |
| `GRAFANA_TAG` | `latest` |
| `REDISINSIGHT_TAG` | `latest` |
| `SEAWEEDFS_TAG` | `latest` |
| `WIREMOCK_TAG` | `latest` |
| `ADMINER_TAG` | `latest` |
| `MONGO_EXPRESS_TAG` | `latest` |
| `JAEGER_TAG` | `2.6.0` |
| `REDIS_EXPORTER_TAG` | `latest` |
| `POSTGRES_EXPORTER_TAG` | `latest` |
| `MYSQL_EXPORTER_TAG` | `latest` |

Set, for example, `REDIS_TAG=latest` or `REDIS_TAG=alpine` without editing Compose.
The tag must be published for that image; not every image provides `alpine`.
These are mutable tags, not immutable digest pins. Version-line tags limit
database upgrades to that release line; plain `latest` and `alpine` can cross
major versions. Back up valuable database data and check upgrade compatibility
before switching versions. Switching back against an upgraded volume may not work.

An exported shell variable overrides the value in `.env`. For a one-off Redis
selection (also possible with any other service's tag variable):

```sh
REDIS_TAG=latest docker compose pull redis
REDIS_TAG=latest docker compose up -d redis
```

Changing `.env` alone does not update running containers. To apply its selected
tags, pull and then recreate the services you need, for example:

```sh
docker compose pull redis redisinsight
docker compose up -d redis redisinsight
```

Neither command deletes named volumes. No automatic update service is configured.

### Low-maintenance update policy

Review images periodically (for example monthly), rather than updating every time
a tag changes. Keep persistent databases on supported release lines; mutable
`latest` tool tags are convenient but can still introduce breaking changes.
An urgent fix may justify an earlier review.

Before a database update, back up valuable data and exercise restore in an
isolated project. Pull and recreate only the services being updated, then verify
readiness and application connectivity. Do not assume a downgrade can reuse an
upgraded database volume. See [recovery checks](./databases.md#recovery-practice).
Scheduled integration tests detect compatibility problems but do not update your
development containers automatically.

## Profiles

| Profile | Optional services selected |
|---|---|
| `admin` | Adminer, Mongo Express, RedisInsight |
| `monitoring` | Prometheus and Grafana |
| `monitoring-redis` | Redis exporter, Prometheus, Grafana |
| `monitoring-postgres` | PostgreSQL exporter, Prometheus, Grafana |
| `monitoring-mysql` | MySQL exporter, Prometheus, Grafana |
| `mocking` | WireMock |
| `storage` | SeaweedFS |
| `tracing` | Jaeger |

Core services have no profile and start with an unqualified `up -d`.
Combine profiles to select multiple capabilities. Explicit service targets
start only the requested services and their dependencies. See the
[connection reference](./connections.md) for addresses and
[project isolation](./project-isolation.md) for host-port configuration.

## Starting and stopping

Run commands from the repository root:

```sh
# Validate without printing resolved credentials.
docker compose --profile "*" config --quiet

# Core: MySQL, Redis, PostgreSQL, MongoDB, Mailpit.
docker compose up -d

# Core plus selected tools.
docker compose --profile admin up -d
docker compose --profile monitoring up -d
docker compose --profile mocking up -d
docker compose --profile storage up -d
docker compose --profile tracing up -d

# Each database profile also starts Prometheus and Grafana:
docker compose --profile monitoring-redis up -d
docker compose --profile monitoring-postgres up -d
docker compose --profile monitoring-mysql up -d

# Start Redis and its UI without the other admin tools.
docker compose up -d redis redisinsight

# Start everything.
docker compose --profile "*" up -d

# Stop everything, preserving containers and data.
docker compose --profile "*" stop

# Remove containers and networks, preserving named volumes.
docker compose --profile "*" down
```

The previous `tools` profile is replaced by `admin`, `monitoring`, `mocking`,
and `storage`, with optional `tracing` and database-specific monitoring profiles.
Profile selection does not stop tools that are already running.
Stop unwanted services explicitly. Configuration changes, including log rotation,
take effect when affected containers are recreated by `up -d`; this may briefly
interrupt connections. This does not delete their named volumes.

Do not add `--volumes` / `-v` to `down` unless you intentionally want to delete
local database and tool data. Resetting data is not part of normal start/stop.
Changing initialization credentials in `.env` does not change accounts already
stored in database volumes.

## Recommended lightweight workflow

Use explicit service targets for daily work instead of enabling every profile:

```sh
# Typical PostgreSQL-backed application:
docker compose up -d --wait postgres redis mailpit
# Or a MySQL-backed application:
docker compose up -d --wait mysql redis mailpit

# Add only the tools needed for the current task:
docker compose up -d --wait redisinsight
docker compose --profile monitoring-postgres up -d --wait postgres-exporter grafana
docker compose up -d --wait wiremock jaeger
```

These commands do not stop previously running services. Adminer depends on both
relational databases, so selecting it also starts MySQL and PostgreSQL.
Doctor currently expects all core services; intentionally omitted services are
reported as missing. For a partial stack, inspect `docker compose ps` and the
application's own connectivity checks instead.

MySQL and PostgreSQL healthchecks run authenticated queries against the configured
database. PostgreSQL uses its service address rather than loopback, which the
official image can trust without checking passwords. Prometheus probes `/-/ready`;
Grafana probes `/api/health` and waits for
healthy Prometheus. These checks do not prove every dashboard query or application
workflow. Existing databases with stale initialization credentials may now report
unhealthy rather than merely accepting connections; repair accounts deliberately,
not by deleting volumes.

Measure resource use with `docker compose stats --no-stream` before adding memory
or CPU limits. Start fewer services first; arbitrary database limits can cause
unexpected termination. Logs are bounded, but database and tool volumes still
need disk-space monitoring.
