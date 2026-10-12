# Verification

[Documentation index](./README.md) | [Project README](../README.md)

```sh
bash tests/doctor.sh
bash tests/scheduled-backup.sh
bash tests/db-workflows.sh
node tests/observability.mjs
```

The retention/timer test uses fake Docker and systemctl commands plus
`systemd-analyze verify` to validate unit syntax, never enabling a real timer.
The observability integration test requires Node.js 18+ and Docker;
it starts an isolated project with ephemeral localhost ports and private volumes.
It verifies actual dashboard metric series, provisioned Grafana resources, OTLP
trace ingestion/retrieval, and WireMock's response shapes and delay threshold.
It also checks Mongo Express database access with URI-reserved credential
characters, continued UI authentication, authenticated database healthchecks,
and Grafana/Prometheus HTTP readiness.
Integration tests may pull missing images and clean up only their test resources.
Application metrics/instrumentation, fault injection, messaging, and authentication
services remain outside this workspace's implementation.

## Database workflow integration test

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

## Continuous integration

The [GitHub Actions workflow](../.github/workflows/validation.yml) runs Compose
configuration, Bash/Node syntax, whitespace, and mocked regression checks on
pushes and pull requests. It uses `.env.example`, never your private `.env`.

On Mondays at 06:00 UTC, and through **Actions > Infrastructure validation >
Run workflow**, it also runs the database and observability integration tests.
Scheduled runs use the default branch and require the workflow to be committed
and pushed. Tests use isolated projects, volumes, and disposable credentials;
they never connect to your workstation's development stack.

Image tags remain configurable and mutable as documented in
[configuration](./configuration.md#choosing-image-tags). Weekly integration runs
can detect changes in those image tags; they neither pull images on your
workstation nor automatically upgrade its containers. For repeatable runs,
set tested image versions in the workflow environment. Scheduled runs may be
disabled by GitHub for inactive public repositories; check the Actions page.
