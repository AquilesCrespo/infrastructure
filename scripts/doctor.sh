#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
compose=(docker compose --project-directory "$root")
failures=0

report_failure() {
  printf 'FAIL %s\n' "$*" >&2
  failures=$((failures + 1))
}

if [[ $# -ne 0 ]]; then
  printf 'Usage: bash scripts/doctor.sh\nEnable optional checks with COMPOSE_PROFILES (for example monitoring-redis,tracing).\n' >&2
  exit 1
fi

for tool in docker timeout; do
  if ! command -v "$tool" > /dev/null; then
    report_failure "Install $tool before running diagnostics."
    exit 1
  fi
done

if ! timeout 15 "${compose[@]}" version > /dev/null 2>&1; then
  report_failure "Docker Compose is unavailable; install or repair the Compose plugin."
  exit 1
fi
if ! timeout 15 "${compose[@]}" --profile '*' config --quiet > /dev/null 2>&1; then
  report_failure "Compose configuration is invalid. Check .env against .env.example, required values, image tags, and YAML syntax."
  exit 1
fi
printf 'PASS Compose configuration\n'
if ! timeout 15 docker info > /dev/null 2>&1; then
  report_failure "Docker is unreachable. Check the daemon, active context, and socket permissions."
  exit 1
fi
if ! services="$(timeout 15 "${compose[@]}" --profile '*' config --services 2>/dev/null)" ||
   ! selected="$(timeout 15 "${compose[@]}" config --services 2>/dev/null)" ||
   [[ -z "$services" || -z "$selected" ]]; then
  report_failure "Cannot enumerate Compose services; check configuration and selected profiles."
  exit 1
fi

database_check() {
  case "$1" in
    mysql)
      timeout 15 docker exec "$2" sh -eu -c '
        export MYSQL_PWD="$MYSQL_PASSWORD"
        exec mysql --host=127.0.0.1 --connect-timeout=5 \
          --user="$MYSQL_USER" "$MYSQL_DATABASE" --execute="SELECT 1"
      '
      ;;
    postgres)
      timeout 15 docker exec "$2" sh -eu -c '
        export PGPASSWORD="$POSTGRES_PASSWORD" PGCONNECT_TIMEOUT=5
        exec psql --host=postgres --username="$POSTGRES_USER" \
          --dbname="$POSTGRES_DB" --no-psqlrc --set=ON_ERROR_STOP=1 --command="SELECT 1"
      '
      ;;
    mongodb)
      timeout 15 docker exec "$2" mongosh --quiet \
        --host 127.0.0.1 --eval '
          const admin = db.getSiblingDB("admin");
          if (!admin.auth(process.env.MONGO_INITDB_ROOT_USERNAME,
                          process.env.MONGO_INITDB_ROOT_PASSWORD)) {
            throw new Error("Authentication failed");
          }
          if (admin.runCommand({ping: 1}).ok !== 1) {
            throw new Error("Ping failed");
          }
        '
      ;;
    redis)
      timeout 15 docker exec "$2" sh -eu -c \
        'test "$(redis-cli -h 127.0.0.1 ping)" = PONG'
      ;;
  esac
}

while IFS= read -r service; do
  [[ -n "$service" ]] || continue
  required=false
  while IFS= read -r active; do
    if [[ "$active" == "$service" ]]; then
      required=true
      break
    fi
  done <<< "$selected"

  if ! ids="$(timeout 15 "${compose[@]}" ps --all --quiet "$service" 2>/dev/null)"; then
    report_failure "$service: cannot query containers; check Docker connectivity."
    continue
  fi
  if [[ -z "$ids" ]]; then
    if [[ "$required" == true ]]; then
      report_failure "$service: no container. Start it with docker compose up -d $service."
    else
      printf 'SKIP %s: optional service not created\n' "$service"
    fi
    continue
  fi

  while IFS= read -r id; do
    if ! state="$(timeout 15 docker inspect --format \
      '{{.State.Status}}|{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$id" 2>/dev/null)"; then
      report_failure "$service: cannot inspect container; it may have been removed."
      continue
    fi
    status="${state%%|*}"
    health="${state#*|}"
    if [[ "$status" != running ]]; then
      if [[ "$required" == true ]]; then
        report_failure "$service: container is $status. Start it with docker compose up -d $service."
      else
        printf 'SKIP %s: optional container is %s\n' "$service" "$status"
      fi
      continue
    fi
    printf 'PASS %s: running\n' "$service"
    case "$health" in
      healthy) printf 'PASS %s: healthy\n' "$service" ;;
      none) printf 'INFO %s: no Docker healthcheck configured\n' "$service" ;;
      *) report_failure "$service: health is $health. Inspect docker compose logs --tail 100 $service locally." ;;
    esac

    if ! ports="$(timeout 15 docker port "$id" 2>/dev/null)"; then
      report_failure "$service: cannot inspect published ports."
    elif [[ "$service" == *-exporter ]]; then
      printf 'INFO %s: internal metrics endpoint; verify the scrape in Prometheus Targets\n' "$service"
    elif [[ -z "$ports" ]]; then
      report_failure "$service: no published ports; recreate it with the development Compose configuration."
    else
      while IFS= read -r mapping; do
        endpoint="${mapping##* -> }"
        host="${endpoint%:*}"
        port="${endpoint##*:}"
        if [[ "$mapping" != *"/tcp -> "* || "$host" != 127.0.0.1 || ! "$port" =~ ^[0-9]+$ ]]; then
          report_failure "$service: unexpected binding $mapping; expected localhost-only TCP."
          continue
        fi
        if timeout 3 bash -c 'exec 3<>/dev/tcp/127.0.0.1/"$1"' bash "$port" > /dev/null 2>&1; then
          printf 'PASS %s: %s accepts TCP connections\n' "$service" "$endpoint"
        else
          report_failure "$service: $endpoint is unreachable from this host. Check the Docker context, port publication, and service listener."
        fi
      done <<< "$ports"
    fi
    case "$service" in
      mysql|postgres|mongodb|redis)
        if database_check "$service" "$id" > /dev/null 2>&1; then
          printf 'PASS %s: database connection\n' "$service"
        else
          report_failure "$service: database connection failed or timed out. Check readiness and container credentials; .env changes do not update stored database accounts."
        fi
        ;;
    esac
  done <<< "$ids"
done <<< "$services"

if [[ "$failures" -gt 0 ]]; then
  printf 'Doctor found %s failed check(s).\n' "$failures" >&2
  exit 1
fi
printf 'Doctor passed all required and running-service checks.\n'
