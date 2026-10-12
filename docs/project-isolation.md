# Project isolation

[Documentation index](./README.md) | [Project README](../README.md)

`COMPOSE_PROJECT_NAME=infrastructure` in `.env` preserves the original project
name and its existing named volumes. Fixed container names have been removed.
When applying this change with the same project name, Compose may recreate the
old `local_*` containers with generated names; named database volumes are retained.
Use service names with `docker compose exec`, not hard-coded container names.
No running container is renamed until you apply the configuration.

For another application, copy `.env.example` to `.env.project-b`, choose distinct
credentials, set `COMPOSE_PROJECT_NAME=project-b`, and change host ports for every
service you plan to run. All `*_PORT` variables are listed in `.env.example`.
For example, change `MYSQL_PORT=3307`, `REDIS_PORT=6380`,
`POSTGRES_PORT=5433`, `MONGO_PORT=27018`, `MAILPIT_HTTP_PORT=8026`,
and `MAILPIT_SMTP_PORT=1026`; change the optional tool ports as well if enabled.
The [connection reference](./connections.md) shows defaults; use your chosen ports from the host.
Container-to-container addresses do not change.

```sh
COMPOSE_ENV_FILES=.env.project-b docker compose up -d
COMPOSE_ENV_FILES=.env.project-b bash scripts/doctor.sh
COMPOSE_ENV_FILES=.env.project-b bash scripts/db.sh seed all
```

Compose project names isolate networks and named volumes, not host ports.
Never change the project name expecting to reuse the old project's data:
a different project gets different volumes. The WireMock fixtures and read-only
configuration files remain shared when projects use the same workspace.
An exported `COMPOSE_PROJECT_NAME` overrides the env file. Keep project env files
private; `.env.*` is ignored except `.env.example`.
