# Diagnostics and troubleshooting

[Documentation index](./README.md) | [Project README](../README.md)

Run all commands from the repository root.

## Read-only diagnostics

```sh
bash scripts/doctor.sh

# Require the optional profiles too, even if their containers are absent:
COMPOSE_PROFILES=admin,monitoring,mocking,storage bash scripts/doctor.sh
```

Doctor validates Compose configuration, Docker access, container state and health,
and each running container's published localhost TCP ports. It checks MySQL and
PostgreSQL with authenticated `SELECT 1` queries against their configured databases,
MongoDB with an authenticated ping, and Redis with `PING`.
Compose also uses authenticated MySQL/PostgreSQL query healthchecks and HTTP
readiness checks for Prometheus and Grafana. Recreate only affected services when
you choose to apply changed healthchecks; existing containers keep their old
checks until recreated.
PostgreSQL queries use the `postgres` service address to avoid the official image's
loopback trust rule. Existing volumes with customized authentication rules may
behave differently; the checks do not rewrite those rules.

Core services and services selected by `COMPOSE_PROFILES` are required. Other
optional services are skipped if absent or stopped, but checked when running.
Containers without healthchecks are identified, not assumed healthy. Checks are
bounded by timeouts, failures include next steps, and the command exits nonzero
if any check fails. TCP acceptance is not a full HTTP or application-functionality
test. Database probes run inside the containers; host-side probes test TCP only.
Exporters deliberately publish no additional host ports; Doctor reports their
metrics endpoints as internal. Check scrape status in Prometheus Targets.

Requires Bash, Docker Compose, and `timeout` (provided by GNU coreutils on Linux).
Host port probes assume a local Docker daemon; a remote context can cause expected
host reachability failures. The command never starts or stops services, modifies
database records, or prints resolved configuration, credentials, or raw error logs.
Changing `.env` does not change credentials stored in existing database volumes.

Run `bash tests/doctor.sh` for the dependency-free regression checks (Bash and
standard Linux utilities only). They use fake Docker responses to exercise failure
handling, optional profiles, credential suppression, and read-only command usage,
without connecting to Docker or changing the development stack.

## Container logs

Each service uses the `json-file` logging driver with `max-size: 10m` and
`max-file: 3` (roughly 30 MB of retained logs per container). Inspect logs with
`docker compose logs --tail 100 SERVICE`.

## Common failures

| Symptom | Check or next step |
|---|---|
| RedisInsight cannot connect to Redis | Use `redis://redis:6379` from the UI; container localhost is not Redis |
| Host port is already in use | Choose a free host port in the project env file; see [project isolation](./project-isolation.md) |
| Credentials fail after editing `.env` | Existing database accounts are stored in volumes; env changes do not update them |
| Grafana restarts with `Datasource provisioning error: data source not found` | Preserve the existing Prometheus datasource UID; do not assign a different UID during provisioning |
| A database dashboard has no data | Enable the relevant exporter profile and inspect Prometheus Targets; allow multiple scrapes |
| MySQL's scrape target is DOWN without its exporter | Expected when `monitoring-mysql` is disabled; see [metrics](./observability.md#database-metrics-and-dashboards) |
| Jaeger has no application traces | Start tracing and enable an application SDK/agent; env settings alone do not instrument code |
| Scheduled backup does not run | The generated timer is disabled until explicitly enabled; see [backup scheduling](./databases.md#opt-in-scheduled-backups-and-retention) |

For the Grafana provisioning issue, the provided dashboard selects Prometheus by
name and the configuration preserves its existing UID. Restore that configuration
and restart only Grafana. Do not delete its volume to work around the failure.
