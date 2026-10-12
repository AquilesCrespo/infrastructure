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

## Database backup and restore

Run `bash scripts/db.sh` from this directory. The script uses the running
containers' credentials, so it does not source or print `.env`. Services must
already be running; these commands never start, stop, or recreate them.

```sh
mkdir -p backups
bash scripts/db.sh backup mysql backups/mysql.sql
bash scripts/db.sh backup postgres backups/postgres.dump
bash scripts/db.sh backup mongodb backups/mongodb.archive.gz
```

Choose a new filename for each backup (for example, include a date). Existing
files are never overwritten. Files are created with private permissions, and
only published at the requested path after the dump succeeds. Failed partial
files are removed. `backups/` is ignored by Git; treat backups as sensitive and
keep them out of source control if you store them anywhere else.

| Service | Backup scope | Restore behavior |
|---|---|---|
| MySQL | Configured `MYSQL_DATABASE`, including routines, events, and triggers | Loads SQL into the configured database; replaces tables present in the dump |
| PostgreSQL | Configured `POSTGRES_DB`; no role definitions, ownership, or ACLs | Cleans and restores backed-up objects in one transaction, owned by the configured user |
| MongoDB | `mongodump` default database scope, including any exported admin metadata | Drops and restores collections present in the archive, excluding `admin`, `config`, and `local`; retains current credentials |

Restore requires the explicit `--confirm` argument:

```sh
bash scripts/db.sh restore mysql backups/mysql.sql --confirm
bash scripts/db.sh restore postgres backups/postgres.dump --confirm
bash scripts/db.sh restore mongodb backups/mongodb.archive.gz --confirm
```

Stop application writes and take a fresh backup before restoring. Only restore
trusted files: SQL dumps can execute SQL. These are logical data backups, not
complete snapshots of container configuration or database users. Objects absent
from a backup are not necessarily removed on restore. MySQL and MongoDB restores
are not atomic; a failure can leave partial changes. Do not resume applications
until you have checked the restore outcome.

MySQL's snapshot is consistent for transactional tables; avoid concurrent DDL,
and stop writes for nontransactional tables. The standalone MongoDB deployment
does not offer a cross-collection point-in-time dump: stop writes for consistency.
Backups across these three services are not one coordinated transaction.
Test restore compatibility before upgrading database major versions.
Redis is intentionally untouched.

## Repeatable demo seeds

```sh
bash scripts/db.sh seed all
# Or one database:
bash scripts/db.sh seed postgres
```

Reserved demo locations:

- MySQL: `infrastructure_demo_customers` in `MYSQL_DATABASE`.
- PostgreSQL: `infrastructure_demo.customers` in `POSTGRES_DB`.
- MongoDB: `infrastructure_demo.customers` (database and collection).

The versioned scripts in `seeds/` upsert two fictional customers with fixed IDs.
Running them again refreshes those demo records without duplicating them; other
records and application tables/collections are not deleted. Reserve these names
and IDs for this tooling; do not use them for application data. Seeds are explicit,
not first-start initialization scripts, so they also work with existing volumes.
`seed all` stops at the first failure; it is not a cross-database transaction.

### Verify the database workflows

```sh
bash tests/db-workflows.sh
```

This integration test starts a uniquely named Compose project with three temporary
database volumes and no published ports. It checks repeated seeding, preservation
of unrelated data, backup/restore round trips, private backup permissions, and
failure safeguards. It removes only its own test containers and volumes on exit;
the development stack is not touched. It requires Docker Compose with `--wait`
support and available database images, and may pull images if they are missing.
The test uses the same database tag variables/defaults as the development stack.

## Logs and monitoring scope

Each service uses the `json-file` logging driver with `max-size: 10m` and
`max-file: 3` (roughly 30 MB of retained logs per container). Inspect logs with
`docker compose logs --tail 100 SERVICE`.

Prometheus still scrapes only itself. Database exporters, application metrics,
dashboards, tracing, fault injection, messaging, and authentication
services are intentionally outside this first pass.
