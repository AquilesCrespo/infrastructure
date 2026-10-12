# Application examples

[Documentation index](../README.md) | [Project README](../../README.md)

These are host-run project setup examples, not bundled starter applications.
Create projects outside this infrastructure directory. Install the appropriate
runtime/SDK and package manager first; select supported versions for your project.
Package installation alone does not implement database queries, migrations,
background jobs, or tracing.

Run each infrastructure command below from the repository root; run project commands
from your chosen application parent directory. Start specific services rather
than the whole stack:

| Example project | Infrastructure command | Typical libraries |
|---|---|---|
| PHP / Laravel web app | `docker compose up -d mysql redis mailpit` | PDO MySQL, Laravel database/mail clients, Predis or PhpRedis |
| Node.js / Express API | `docker compose up -d postgres redis mailpit` | `pg`, `redis`, `nodemailer` |
| Rust CLI / background worker | `docker compose up -d postgres redis` | `sqlx`, `tokio`, `redis` |
| .NET / ASP.NET Core API | `docker compose up -d postgres redis mailpit` | Npgsql, StackExchange.Redis, MailKit |
| .NET console / worker | `docker compose up -d postgres` | Npgsql; hosting/configuration packages as needed |

Applications running on the host use `127.0.0.1` and the configured host ports.
Applications containerized on the same Compose network use service names and
internal ports instead. Never copy the infrastructure's entire `.env` into an
application: provide only the credentials and endpoints it needs.
Replace the password placeholders below with your private development values.
The database names/usernames shown assume the defaults in `.env.example`.
Keep application env files private and ignored by Git.

## Guides

- [PHP / Laravel](./php.md)
- [Node.js / Express](./nodejs.md)
- [Rust CLI and workers](./rust.md)
- [.NET APIs, console apps, and workers](./dotnet.md)

## Application responsibilities

Each application project should define:

- Its runtime and dependencies, such as Node.js, Python, Java, or .NET.
- A development server and debugger, with hot reload where appropriate.
- Its own schema migrations and realistic seeds; this stack's demo seeds do not
  replace application-specific data setup.
- Unit, integration, and browser/end-to-end tests as appropriate.
- OpenTelemetry instrumentation and application metrics endpoints if needed.
- Reproducible setup through dependency lockfiles and documented runtime versions,
  optionally using a Dev Container.

Message brokers, authentication servers, and search engines should be added only
when the application uses them. Desktop and mobile development also require the
appropriate platform-specific SDKs and tooling.

Use the stack with a real project before expanding it further. Start only the
services that project needs, connect the application, run its migrations, and
exercise a complete workflow. Aim for a project-specific setup that gets the
application running, tested, and debuggable in one command rather than adding
more background infrastructure by default.

## Shared workflow for all project types

1. Select a Compose project and nonconflicting host ports.
2. Start the required services and run `bash scripts/doctor.sh`.
3. Configure the application's least-needed credentials and endpoints.
4. Implement clients, migrations, application-specific seeds, and tests.
5. Enable WireMock, storage, database monitoring, or tracing only when needed.
6. Instrument the app before expecting traces in Jaeger or application metrics
   in Prometheus. See the [observability guide](../observability.md).
7. Back up valuable local data before database upgrades or restore operations.

Examples for optional endpoints, using default host ports:

- Mock API: `http://127.0.0.1:8081`; route your test client's base URL here.
- S3-compatible storage: `http://127.0.0.1:8333`, bucket `local-bucket`, path-style
  addressing, and your `S3_ACCESS_KEY` / `S3_SECRET_KEY`.
- OTLP HTTP: `http://127.0.0.1:4318`, with an initialized OpenTelemetry exporter.

These settings are examples, not universal framework variables: configure the
appropriate library in each application. Frontend-only projects typically call
their backend API, not databases directly. Never send database credentials to
browser code; configure backend CORS or a development proxy when origins differ.
