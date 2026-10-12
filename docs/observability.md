# Tracing and metrics

[Documentation index](./README.md) | [Project README](../README.md)

Run infrastructure commands from the repository root.

## Application tracing

```sh
docker compose --profile tracing up -d
```

Jaeger accepts OTLP over HTTP and gRPC, and its UI is available at
http://127.0.0.1:16686 by default. Trace storage is memory-only, bounded to 10,000
traces; traces are lost on restart. Grafana's Jaeger data source works when the
tracing profile is running. It is unavailable when Jaeger is stopped.

Configure an OpenTelemetry-instrumented host application with:

```dotenv
OTEL_SERVICE_NAME=my-development-api
OTEL_TRACES_EXPORTER=otlp
OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf
OTEL_EXPORTER_OTLP_ENDPOINT=http://127.0.0.1:4318
OTEL_METRICS_EXPORTER=none
OTEL_LOGS_EXPORTER=none
```

For an app container on this project's network, use `http://jaeger:4318` instead.
If the app runs in a separate Compose project, its `localhost` is not this host:
explicitly configure network access; service names resolve only on shared networks.
The generic OTLP endpoint has no `/v1/traces` suffix; a trace-specific
`OTEL_EXPORTER_OTLP_TRACES_ENDPOINT` requires the complete `/v1/traces` URL.

Environment variables alone do not instrument an application. Install and enable
the language's OpenTelemetry SDK/agent and supported web/HTTP/database integrations
before application startup. Add spans around your own background jobs or other
operations that auto-instrumentation cannot see. Propagate W3C trace context
across HTTP calls and message boundaries. SDK support for environment settings
varies; verify your runtime's exporter setup.

Official starting points:

- [Node.js automatic instrumentation](https://opentelemetry.io/docs/zero-code/js/)
- [Python automatic instrumentation](https://opentelemetry.io/docs/zero-code/python/)
- [Java agent](https://opentelemetry.io/docs/zero-code/java/agent/)

Trigger an application request and search for `my-development-api` in Jaeger.
This infrastructure workspace contains no application source, so no applications
were instrumented here. Avoid sensitive attributes, payloads, and credentials
in spans. Jaeger is not an application-metrics backend.

## Database metrics and dashboards

Enable only the exporters you need:

```sh
docker compose --profile monitoring-redis --profile monitoring-postgres up -d
# Add --profile monitoring-mysql if MySQL metrics are needed.
```

`monitoring` alone starts only Prometheus and Grafana, not exporters. The
`Development databases` dashboard is automatically provisioned under the
Development folder. It shows connection status, Redis command rate/memory,
PostgreSQL connection counts/commit rates, and MySQL connections/query rates.
The dashboard selects the Prometheus source by name through a datasource
variable. Provisioning preserves its existing generated UID, so upgrading an
existing Grafana volume does not replace the source or break existing references.
Rate panels need multiple scrapes (15-second interval); allow a minute for data.
Disabled exporters produce no database metrics; missing data is not a zero.

Redis and PostgreSQL targets use DNS discovery for running exporters. MySQL's
exporter shares MySQL's network namespace and is scraped at `mysql:9104`, so its
target is DOWN when MySQL is running without its exporter. This is expected for
a disabled monitoring profile. Check `/targets` in Prometheus for actual failures.

Exporter endpoints are internal only (`redis-exporter:9121`,
`postgres-exporter:9187`, and `mysql:9104`). For this development-only setup,
PostgreSQL uses the configured database user; MySQL uses root over localhost in
the shared namespace so no remotely accessible root account is needed.
Do not use this account model for production: provision least-privilege monitoring
accounts there. Exporter reads do not seed or alter application data.

Application request/error rates and latency require app instrumentation too.
Expose a Prometheus metrics endpoint using your application's runtime libraries,
then add a reachable target to `prometheus/prometheus.yml` and reload/restart
Prometheus. No nonexistent app endpoint is configured by default.
