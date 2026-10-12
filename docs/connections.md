# Connection reference

[Documentation index](./README.md) | [Project README](../README.md)

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
| Jaeger UI / query | http://127.0.0.1:16686 | `http://jaeger:16686` | `tracing`; `JAEGER_PORT` |
| OTLP HTTP | http://127.0.0.1:4318 | `http://jaeger:4318` | `tracing`; `OTLP_HTTP_PORT`; trace path `/v1/traces` |
| OTLP gRPC | `127.0.0.1:4317` | `jaeger:4317` | `tracing`; `OTLP_GRPC_PORT` |

MongoDB credentials containing URI-reserved characters must be percent-encoded
when used in an application connection URI. Mongo Express encodes the raw
`MONGO_ROOT_USERNAME` and `MONGO_ROOT_PASSWORD` values at startup; do not
pre-encode those environment values. Its normal image entrypoint is preserved.
