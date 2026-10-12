#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
compose=(docker compose --project-directory "$root")
temporary=""

cleanup() {
  if [[ -n "$temporary" ]]; then
    rm -f -- "$temporary"
  fi
}
trap cleanup EXIT
trap 'printf "Database command failed at line %s; no success was reported.\n" "$LINENO" >&2' ERR

usage() {
  cat <<'EOF'
Usage:
  bash scripts/db.sh backup  mysql|postgres|mongodb FILE
  bash scripts/db.sh restore mysql|postgres|mongodb FILE --confirm
  bash scripts/db.sh seed    mysql|postgres|mongodb|all

Restore modifies existing data. Stop application writes and back up first.
Use only trusted backup files. Redis is not managed by this script.
EOF
}

fail() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

action="${1:-}"
service="${2:-}"
case "$action" in
  backup)
    [[ $# -eq 3 ]] || { usage >&2; exit 1; }
    ;;
  restore)
    [[ $# -eq 4 && "${4:-}" == "--confirm" ]] || {
      usage >&2
      fail "Restore requires FILE and --confirm; nothing was restored."
    }
    ;;
  seed)
    [[ $# -eq 2 ]] || { usage >&2; exit 1; }
    ;;
  *)
    usage >&2
    exit 1
    ;;
esac

case "$service" in
  mysql|postgres|mongodb) ;;
  all)
    [[ "$action" == "seed" ]] || fail "'all' is supported only for seed."
    ;;
  *) fail "Unsupported database: $service" ;;
esac

backup() {
  case "$service" in
    mysql)
      "${compose[@]}" exec -T mysql sh -eu -c '
        export MYSQL_PWD="$MYSQL_ROOT_PASSWORD"
        exec mysqldump --user=root --single-transaction --routines --events \
          --triggers --no-tablespaces --set-gtid-purged=OFF "$MYSQL_DATABASE"
      '
      ;;
    postgres)
      "${compose[@]}" exec -T postgres sh -eu -c '
        export PGPASSWORD="$POSTGRES_PASSWORD"
        exec pg_dump --username="$POSTGRES_USER" --dbname="$POSTGRES_DB" \
          --format=custom --no-owner --no-acl
      '
      ;;
    mongodb)
      "${compose[@]}" exec -T mongodb sh -eu -c '
        exec mongodump --username="$MONGO_INITDB_ROOT_USERNAME" \
          --password="$MONGO_INITDB_ROOT_PASSWORD" --authenticationDatabase=admin \
          --archive --gzip
      '
      ;;
  esac
}

restore() {
  case "$service" in
    mysql)
      "${compose[@]}" exec -T mysql sh -eu -c '
        export MYSQL_PWD="$MYSQL_ROOT_PASSWORD"
        exec mysql --user=root "$MYSQL_DATABASE"
      '
      ;;
    postgres)
      "${compose[@]}" exec -T postgres sh -eu -c '
        export PGPASSWORD="$POSTGRES_PASSWORD"
        exec pg_restore --username="$POSTGRES_USER" --dbname="$POSTGRES_DB" \
          --clean --if-exists --exit-on-error --single-transaction --no-owner --no-acl
      '
      ;;
    mongodb)
      "${compose[@]}" exec -T mongodb sh -eu -c '
        exec mongorestore --username="$MONGO_INITDB_ROOT_USERNAME" \
          --password="$MONGO_INITDB_ROOT_PASSWORD" --authenticationDatabase=admin \
          --archive --gzip --drop --stopOnError \
          --nsExclude="admin.*" --nsExclude="config.*" --nsExclude="local.*"
      '
      ;;
  esac
}

seed() {
  case "$1" in
    mysql)
      "${compose[@]}" exec -T mysql sh -eu -c '
        export MYSQL_PWD="$MYSQL_PASSWORD"
        exec mysql --user="$MYSQL_USER" "$MYSQL_DATABASE"
      ' < "$root/seeds/mysql.sql"
      ;;
    postgres)
      "${compose[@]}" exec -T postgres sh -eu -c '
        export PGPASSWORD="$POSTGRES_PASSWORD"
        exec psql --username="$POSTGRES_USER" --dbname="$POSTGRES_DB" \
          --no-psqlrc --set=ON_ERROR_STOP=1 --single-transaction
      ' < "$root/seeds/postgres.sql"
      ;;
    mongodb)
      "${compose[@]}" exec -T mongodb sh -eu -c '
        exec mongosh --quiet --username="$MONGO_INITDB_ROOT_USERNAME" \
          --password="$MONGO_INITDB_ROOT_PASSWORD" --authenticationDatabase=admin \
          --file /dev/stdin
      ' < "$root/seeds/mongodb.js"
      ;;
  esac
  printf 'Seeded %s demo data.\n' "$1"
}

case "$action" in
  backup)
    output="$3"
    [[ ! -e "$output" && ! -L "$output" ]] || fail "Backup destination already exists: $output"
    [[ -d "$(dirname -- "$output")" ]] || fail "Create the backup destination directory first."
    temporary="$(mktemp -- "${output}.partial.XXXXXX")"
    backup > "$temporary"
    [[ -s "$temporary" ]] || fail "Backup output was empty."
    ln -- "$temporary" "$output"
    printf 'Backup saved to %s (private file permissions).\n' "$output"
    ;;
  restore)
    [[ -f "$3" && -r "$3" && -s "$3" ]] || fail "Backup must be a readable, nonempty file."
    printf 'Restoring %s from %s; existing backed-up objects may be replaced.\n' "$service" "$3" >&2
    restore < "$3"
    printf 'Restored %s successfully.\n' "$service"
    ;;
  seed)
    if [[ "$service" == "all" ]]; then
      for database in mysql postgres mongodb; do
        seed "$database"
      done
    else
      seed "$service"
    fi
    ;;
esac
