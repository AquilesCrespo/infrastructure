#!/usr/bin/env bash
# Container commands intentionally expand variables in the container, not here.
# shellcheck disable=SC2016
set -Eeuo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$root/scripts/lib/common.sh"
compose=(docker compose --project-directory "$root")
failures=0
passes=0
skips=0

report_failure() {
  log_status FAIL "$*"
  failures=$((failures + 1))
}

report_pass() {
  log_status PASS "$*"
  passes=$((passes + 1))
}

report_skip() {
  log_status SKIP "$*"
  skips=$((skips + 1))
}

usage() {
  cat <<'EOF'
Usage: bash scripts/doctor.sh [SERVICE ...]
       bash scripts/doctor.sh --help

Without service names, check all core and profile-selected services plus running
optional services. With names, check only those services and require each one.
This command is read-only. Requires Docker Compose, Bash, and GNU timeout.

Examples:
  bash scripts/doctor.sh postgres redis mailpit
  COMPOSE_PROFILES=monitoring-postgres,tracing bash scripts/doctor.sh

Colors are automatic on terminals; set NO_COLOR to disable them.
EOF
}

if [[ $# -eq 1 && ( "$1" == --help || "$1" == -h ) ]]; then
  usage
  exit 0
fi
for argument in "$@"; do
  if [[ "$argument" == -* ]]; then
    report_failure "Unknown option: $argument"
    usage >&2
    exit 1
  fi
done
require_commands docker timeout || exit 1

if ! timeout 15 "${compose[@]}" version > /dev/null 2>&1; then
  report_failure "Docker Compose is unavailable; install or repair the Compose plugin."
  exit 1
fi
if ! timeout 15 "${compose[@]}" --profile '*' config --quiet > /dev/null 2>&1; then
  report_failure "Compose configuration is invalid. Check .env against .env.example, required values, image tags, and YAML syntax."
  exit 1
fi
report_pass 'Compose configuration'
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

if [[ $# -gt 0 ]]; then
  requested=""
  for argument in "$@"; do
    found=false
    while IFS= read -r service; do
      if [[ "$argument" == "$service" ]]; then
        found=true
        break
      fi
    done <<< "$services"
    if [[ "$found" != true ]]; then
      report_failure "Unknown service: $argument. Use docker compose --profile '*' config --services to list names."
      exit 1
    fi
    if [[ $'\n'"$requested"$'\n' != *$'\n'"$argument"$'\n'* ]]; then
      requested+="${requested:+$'\n'}$argument"
    fi
  done
  services="$requested"
  selected="$requested"
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
      report_skip "$service: optional service not created"
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
        report_skip "$service: optional container is $status"
      fi
      continue
    fi
    report_pass "$service: running"
    case "$health" in
      healthy) report_pass "$service: healthy" ;;
      none) log_status WARN "$service: no Docker healthcheck configured" ;;
      *) report_failure "$service: health is $health. Inspect docker compose logs --tail 100 $service locally." ;;
    esac

    if ! ports="$(timeout 15 docker port "$id" 2>/dev/null)"; then
      report_failure "$service: cannot inspect published ports."
    elif [[ "$service" == *-exporter ]]; then
      log_status INFO "$service: internal metrics endpoint; verify the scrape in Prometheus Targets"
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
          report_pass "$service: $endpoint accepts TCP connections"
        else
          report_failure "$service: $endpoint is unreachable from this host. Check the Docker context, port publication, and service listener."
        fi
      done <<< "$ports"
    fi
    case "$service" in
      mysql|postgres|mongodb|redis)
        if database_check "$service" "$id" > /dev/null 2>&1; then
          report_pass "$service: database connection"
        else
          report_failure "$service: database connection failed or timed out. Check readiness and container credentials; .env changes do not update stored database accounts."
        fi
        ;;
    esac
  done <<< "$ids"
done <<< "$services"

log_status INFO "Summary: $passes passed, $failures failed, $skips skipped checks (${SECONDS}s)."
if [[ "$failures" -gt 0 ]]; then
  log_status FAIL "Doctor found $failures failed check(s)."
  exit 1
fi
log_status PASS 'Doctor passed all required and running-service checks.'
