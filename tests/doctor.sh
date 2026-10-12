#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d)"
cleanup() {
  rm -f -- "$work/docker" "$work/timeout" "$work/output" "$work/calls"
  rmdir -- "$work"
}
trap cleanup EXIT

cat > "$work/docker" <<'EOF'
#!/usr/bin/env bash
set -eu
printf '%s\n' "$*" >> "$DOCTOR_CALLS"
case "$*" in
  *'config --quiet'*)
    if [[ "$SCENARIO" == invalid-config ]]; then
      echo 'PRIVATE_CREDENTIAL' >&2
      exit 1
    fi
    ;;
  *'config --services'*)
    printf 'mysql\nredis\npostgres\nmongodb\nmailpit\n'
    if [[ "$*" == *'--profile *'* || -n "${COMPOSE_PROFILES:-}" ]]; then
      printf 'redisinsight\n'
    fi
    if [[ "$SCENARIO" == exporter ]]; then printf 'redis-exporter\n'; fi
    ;;
  info)
    if [[ "$SCENARIO" == daemon ]]; then exit 1; fi
    ;;
  *'ps --all --quiet '*)
    service="${@: -1}"
    if [[ "$service" == redisinsight ]]; then
      if [[ "$SCENARIO" != optional-running && "$SCENARIO" != optional-stopped ]]; then exit 0; fi
    fi
    if [[ "$service" == mysql && "$SCENARIO" == missing ]]; then exit 0; fi
    printf '%s\n' "$service"
    ;;
  inspect*)
    service="${@: -1}"
    if [[ "$service" == mysql ]]; then
      case "$SCENARIO" in
        inspect-failure) exit 1 ;;
        stopped) echo 'exited|none'; exit 0 ;;
        unhealthy) echo 'running|unhealthy'; exit 0 ;;
        starting) echo 'running|starting'; exit 0 ;;
      esac
    fi
    if [[ "$service" == redisinsight ]]; then
      if [[ "$SCENARIO" == optional-stopped ]]; then
        echo 'exited|none'
      else
        echo 'running|none'
      fi
    else
      echo 'running|healthy'
    fi
    ;;
  port*)
    if [[ "$2" == redis-exporter ]]; then exit 0; fi
    if [[ "$2" == mysql ]]; then
      case "$SCENARIO" in
        no-ports) exit 0 ;;
        exposed) echo '3306/tcp -> 0.0.0.0:3306'; exit 0 ;;
      esac
    fi
    echo '3306/tcp -> 127.0.0.1:3306'
    ;;
  exec*)
    if [[ "$2" == mysql && "$SCENARIO" == auth ]]; then
      echo 'PRIVATE_CREDENTIAL' >&2
      exit 1
    fi
    ;;
  *version*) ;;
  *) echo 'Unexpected Docker command' >&2; exit 1 ;;
esac
EOF

cat > "$work/timeout" <<'EOF'
#!/usr/bin/env bash
set -eu
shift
if [[ "$1" == bash ]]; then
  [[ "$SCENARIO" != unreachable ]]
else
  exec "$@"
fi
EOF
chmod +x "$work/docker" "$work/timeout"
export PATH="$work:$PATH" DOCTOR_CALLS="$work/calls"
unset COMPOSE_PROFILES

check() {
  local scenario="$1" expected="$2" message="$3" status=0
  : > "$work/calls"
  SCENARIO="$scenario" bash "$root/scripts/doctor.sh" > "$work/output" 2>&1 || status=$?
  [[ "$status" == "$expected" ]]
  grep -Fq "$message" "$work/output"
  if grep -q PRIVATE_CREDENTIAL "$work/output"; then
    printf 'Raw credentials leaked in scenario %s\n' "$scenario" >&2
    exit 1
  fi
  if grep -Eq '(^| )(up|stop|restart|down|pull|rm)( |$)' "$work/calls"; then
    printf 'Mutating Docker command detected\n' >&2
    exit 1
  fi
}

check healthy 0 'Doctor passed'
grep -q 'SKIP redisinsight' "$work/output"
grep -Fq 'psql --host=postgres' "$work/calls"
check invalid-config 1 'Compose configuration is invalid'
check daemon 1 'Docker is unreachable'
check missing 1 'no container'
check stopped 1 'container is exited'
check unhealthy 1 'health is unhealthy'
check starting 1 'health is starting'
check inspect-failure 1 'cannot inspect'
check no-ports 1 'no published ports'
check exposed 1 'expected localhost-only TCP'
check unreachable 1 'unreachable from this host'
check auth 1 'database connection failed'
grep -q 'PASS postgres: database connection' "$work/output"
check optional-running 0 'no Docker healthcheck configured'
check optional-stopped 0 'optional container is exited'
check exporter 0 'internal metrics endpoint'
export COMPOSE_PROFILES=admin
check healthy 1 'redisinsight: no container'
check optional-stopped 1 'redisinsight: container is exited'
printf 'PASS: doctor success, failures, optional profiles, continued checks, credential suppression, and read-only Docker commands.\n'
