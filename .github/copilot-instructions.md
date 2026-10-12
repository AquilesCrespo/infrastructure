# Repository instructions

## Architecture

This is a Docker Compose local-development infrastructure repository, not an
application codebase. Application runtime setup examples in `docs/examples/` are
documentation, not bundled applications.

- `docker-compose.yml` owns service definitions, environment interpolation,
  profiles, localhost port publication, and project-scoped named volumes.
  MySQL, Redis, PostgreSQL, MongoDB, and Mailpit are unprofiled core services.
  Admin tools, storage, mocking, tracing, and monitoring are optional.
- Database-specific monitoring profiles select their exporter plus Prometheus
  and Grafana. Prometheus discovers Redis/PostgreSQL exporters through DNS.
  MySQL's exporter shares MySQL's network namespace and is scraped at
  `mysql:9104`; it authenticates as root locally, not through remote root access.
- Grafana mounts provisioned data sources and dashboards. Preserve the existing
  Prometheus data-source UID: assigning a new UID breaks startup with existing
  volumes. The dashboard resolves it by name through `prometheus_source`.
- Jaeger receives OTLP traces and keeps bounded, memory-only storage. Applications
  must supply their own OpenTelemetry instrumentation.
- Bash scripts operate through Compose or container clients. `db.sh` owns
  backup/restore/seeding; `scheduled-backup.sh` reuses it; the timer installer
  generates disabled systemd user units. `doctor.sh` is strictly read-only.
- WireMock loads workspace mappings and response bodies through read-only mounts.
  API-created stubs are transient; durable scenarios belong in the fixtures.

See the [documentation index](../docs/README.md), especially
[configuration](../docs/configuration.md), [database workflows](../docs/databases.md),
and [observability](../docs/observability.md).
For browser automation and container-tool boundaries, see
[AI assistant tools](../docs/agent-tools.md).

## Validation and tests

Run infrastructure commands from the repository root. Each test below is an
independent focused test entry point; select the relevant one rather than running
every integration test for a small change.

```sh
# Compose syntax/interpolation; do not print resolved credentials.
docker compose --profile "*" config --quiet

# Shell syntax and whitespace checks.
for file in scripts/*.sh scripts/lib/*.sh tests/*.sh; do bash -n "$file"; done
shellcheck --external-sources scripts/*.sh scripts/lib/*.sh tests/*.sh
git diff --check

# Shared shell output, help, and error behavior; uses util-linux script.
bash tests/shell-ui.sh

# Mocked diagnostic behavior; does not connect to Docker.
bash tests/doctor.sh

# Mocked backups/timer installation; also uses systemd-analyze verify.
bash tests/scheduled-backup.sh

# Isolated database seed and backup/restore integration test.
bash tests/db-workflows.sh

# Isolated tracing, metrics, dashboards, WireMock, and project isolation test.
node tests/observability.mjs
```

Integration tests require Docker, may pull missing images, and clean up their own
uniquely named projects and volumes. The observability test requires Node.js 18+;
it also verifies an existing Grafana volume upgrade, not just fresh provisioning.
Do not replace isolated tests with experiments against development databases.
Use `bash scripts/doctor.sh` for read-only live-stack diagnostics.
See [verification](../docs/verification.md) for dependencies and scope.

## Repository conventions

- Every image has a per-service `*_TAG` variable with a Compose fallback.
  Every published port has a configurable host-port variable and remains bound
  to `127.0.0.1`. Update `.env.example` and configuration documentation when adding
  settings; do not expose private `.env` contents.
- Required credential/database variables use `${VARIABLE:?message}`. Container
  shell references in Compose healthchecks use `$$` to avoid host interpolation.
- Do not introduce fixed `container_name` values or globally named volumes.
  Service DNS/internal ports stay stable; project names and host ports provide
  isolation. Existing database account credentials live in volumes, so editing
  `.env` does not change them.
- Preserve shared `json-file` log rotation (10 MB, three files) for new services.
- Scripts resolve the repository root from their own location and honor Compose
  selectors such as `COMPOSE_ENV_FILES` and `COMPOSE_PROJECT_NAME`. Follow the
  existing `set -Eeuo pipefail`, explicit failure reporting, and private backup
  permissions patterns. Reuse `scripts/lib/common.sh` for status output and
  dependency checks; preserve per-stream terminal detection and `NO_COLOR`.
- Backups refuse overwrite and publish only completed dumps. Restore requires
  `--confirm`. Demo seeds upsert reserved IDs in isolated demo tables/collections;
  Redis and application-owned data are not reset by seeding.
- Scheduled retention deletes only correctly named completed backups in the
  selected project's scheduled folder, after all database dumps succeed.
  Preserve locking, symlink rejection, manual/partial files, and disabled-by-default
  timer installation.
- Do not delete development volumes, enable timers, pull upgrades, or restart
  services as an incidental validation step. Integration-test volume cleanup is
  confined to the test project's resources.
- Keep the README concise. Detailed instructions have one primary home in
  `docs/`, with relative links; infrastructure commands run from the repository
  root, application example commands from application directories.

## Infrastructure operations

Explicit service targets avoid starting unrelated core services. For example,
`docker compose up -d redis redisinsight` starts Redis and its UI; profiles select
optional groups, and changing profile selection does not stop already running
containers. Doctor still requires all core services by default; pass service names for
partial-stack diagnostics.

Use the same Compose project/env selectors for startup, diagnostics, backups,
and restores. Changing project names selects different volumes, not migrated
data. `docker compose --profile "*" stop` and `down` preserve named volumes;
`down --volumes` does not. Follow the
[project-isolation guide](../docs/project-isolation.md) before changing identity.

Inspect bounded logs for provisioning or authentication failures before changing
configuration. Preserve saved Grafana data and fix provisioning incompatibilities
instead of deleting volumes. A disabled MySQL exporter can legitimately leave its
scrape target DOWN; distinguish that from an enabled exporter's failure.
See [troubleshooting](../docs/troubleshooting.md).

## Application integration

Host applications use `127.0.0.1` and configured published ports; containers on
the same Compose network use service names and internal ports. Separate Compose
projects do not automatically share DNS or networks. Redis has no configured
password/TLS, and Mailpit SMTP uses no authentication/TLS.

Language guides cover PHP/Laravel, Node.js/Express, Rust, and .NET. Keep their
runtime/env-loading differences explicit; do not imply that installing client
libraries or setting OTEL variables initializes clients or instrumentation.
Applications own real schemas/migrations, seeds, metrics endpoints, and tests.
Do not add nonexistent application scrape targets or send database credentials
to frontend code. See [application examples](../docs/examples/README.md) and the
[connection reference](../docs/connections.md).
