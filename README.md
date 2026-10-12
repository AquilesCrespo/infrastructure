# Local development infrastructure

## Setup and lifecycle

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

## Starting and stopping

Run commands from this directory:

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
and `storage`. Profile selection does not stop tools that are already running.
Stop unwanted services explicitly. Configuration changes, including log rotation,
take effect when affected containers are recreated by `up -d`; this may briefly
interrupt connections. This does not delete their named volumes.

Do not add `--volumes` / `-v` to `down` unless you intentionally want to delete
local database and tool data. Resetting data is not part of normal start/stop.
Changing initialization credentials in `.env` does not change accounts already
stored in database volumes.

## Connection cheat sheet

Host applications use `127.0.0.1`; containers on this Compose network use service
names. Inside a container, `127.0.0.1` refers to that container itself.
All published ports remain bound to host loopback.

| Service | From the host | From the Compose network | Credentials / notes |
|---|---|---|---|
| MySQL | `127.0.0.1:3306` | `mysql:3306` | `MYSQL_USER`, `MYSQL_PASSWORD`, `MYSQL_DATABASE`; root uses `MYSQL_ROOT_PASSWORD` |
| Redis | `127.0.0.1:6379` | `redis:6379` | No password or TLS configured |
| PostgreSQL | `127.0.0.1:5432` | `postgres:5432` | `POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_DB` |
| MongoDB | `127.0.0.1:27017` | `mongodb:27017` | `MONGO_ROOT_USERNAME`, `MONGO_ROOT_PASSWORD`; `authSource=admin` |
| Mailpit SMTP | `127.0.0.1:1025` | `mailpit:1025` | No authentication configured |
| Mailpit UI | http://127.0.0.1:8025 | `http://mailpit:8025` | Core service |
| RedisInsight | http://127.0.0.1:5540 | `http://redisinsight:5540` | `admin`; add database with `redis://redis:6379` |
| Adminer | http://127.0.0.1:8080 | `http://adminer:8080` | `admin`; server `mysql` or `postgres`, using database credentials |
| Mongo Express | http://127.0.0.1:8082 | `http://mongo-express:8081` | `admin`; UI login: `MONGO_EXPRESS_USER`, `MONGO_EXPRESS_PASSWORD` |
| Prometheus | http://127.0.0.1:9090 | `http://prometheus:9090` | `monitoring` |
| Grafana | http://127.0.0.1:3000 | `http://grafana:3000` | `monitoring`; `GRAFANA_ADMIN_USER`, `GRAFANA_ADMIN_PASSWORD` |
| SeaweedFS S3 | http://127.0.0.1:8333 | `http://seaweedfs:8333` | `storage`; `S3_ACCESS_KEY`, `S3_SECRET_KEY`; bucket `local-bucket`; configure client path-style addressing |
| WireMock | http://127.0.0.1:8081 | `http://wiremock:8080` | `mocking`; admin API under `/__admin` |

MongoDB credentials containing URI-reserved characters must be percent-encoded
when used in a connection URI, including the Mongo Express URI in Compose.

## WireMock fixtures

Mappings live in `wiremock/mappings/`; response bodies live in
`wiremock/__files/`. Both are mounted read-only so the container cannot modify
versioned fixtures. Add or edit files here, then restart WireMock to reload them:

```sh
docker compose restart wiremock
curl --fail http://127.0.0.1:8081/dev/health
```

The example returns `{"status":"ok","service":"development-mock"}` (whitespace
may differ). API-created stubs are transient; admin API save/record-to-disk
operations cannot write to these read-only directories. Store durable fixtures
in the workspace. Do not put real credentials or sensitive responses in them.

The previous `wiremock_data` volume declaration remains for rollback, but is
not mounted. No fixture files were found in the running container during this
change. If rolling back, restore the old volume mount without deleting the volume.

## Logs and monitoring scope

Each service uses the `json-file` logging driver with `max-size: 10m` and
`max-file: 3` (roughly 30 MB of retained logs per container). Inspect logs with
`docker compose logs --tail 100 SERVICE`.

Prometheus still scrapes only itself. Database exporters, application metrics,
dashboards, seeds, tracing, fault injection, messaging, and authentication
services are intentionally outside this first pass.
