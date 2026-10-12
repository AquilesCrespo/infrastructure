# API mocking with WireMock

[Documentation index](./README.md) | [Project README](../README.md)

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

### Failure and pagination examples

| Request | Behavior |
|---|---|
| `GET /dev/error` | HTTP 503 with a JSON error |
| `GET /dev/delay` | HTTP 200 after a fixed 1,500 ms delay |
| `GET /dev/customers?page=1` | First customer, `nextPage: 2` |
| `GET /dev/customers?page=2` | Second customer, `nextPage: null` |
| `GET /dev/rate-limit` | First call: HTTP 429, `Retry-After: 1`; later calls: HTTP 200 |

The rate-limit example models a retry, not a real time-window limiter: the caller
must honor `Retry-After`. State is shared across callers to that WireMock instance.
Restart WireMock or `POST /__admin/scenarios/reset` to reset all scenario state.
Restart is also needed to load edited fixture files. Pagination intentionally
models only pages 1 and 2; other page values are unmatched (404).
