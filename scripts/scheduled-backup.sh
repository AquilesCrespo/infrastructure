#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$root/scripts/lib/common.sh"
usage() {
  cat <<'EOF'
Usage: bash scripts/scheduled-backup.sh [retention-days: 1-9999]
       bash scripts/scheduled-backup.sh --help

Back up all three databases; prune only owned completed backups after success.
Default retention: seven days. Databases must already be running.
Requires Docker Compose, Bash, GNU coreutils, sed, find, and flock.

Example: bash scripts/scheduled-backup.sh 30
Colors are automatic on terminals; set NO_COLOR to disable them.
EOF
}
if [[ $# -eq 1 && ( "$1" == --help || "$1" == -h ) ]]; then
  usage
  exit 0
fi
days="${1:-7}"
if [[ $# -gt 1 || ! "$days" =~ ^[1-9][0-9]{0,3}$ ]]; then
  log_status FAIL 'Retention must be an integer from 1 to 9999 days.'
  usage >&2
  exit 1
fi
trap 'abort "$?" "Scheduled backup failed at line $LINENO; retention cleanup was not completed."' ERR
require_commands docker bash sed mkdir flock date timeout mktemp find rm stat ln || exit 1

if ! project="$(docker compose --project-directory "$root" config 2>/dev/null |
    sed -n 's/^name: //p')"; then
  log_status FAIL 'Cannot resolve Compose project; check configuration and .env.'
  exit 1
fi
if [[ ! "$project" =~ ^[a-z0-9][a-z0-9_-]*$ ]]; then
  log_status FAIL 'Invalid or missing Compose project name.'
  exit 1
fi
for directory in "$root/backups" "$root/backups/scheduled" "$root/backups/scheduled/$project"; do
  if [[ -L "$directory" ]]; then
    log_status FAIL "Refusing symlinked backup directory: $directory"
    exit 1
  fi
  mkdir -p -- "$directory"
done
directory="$root/backups/scheduled/$project"
if [[ -L "$directory/.lock" ]]; then
  log_status FAIL 'Refusing symlinked backup lock.'
  exit 1
fi
exec 9> "$directory/.lock"
if ! flock --nonblock 9; then
  log_status FAIL "Another scheduled backup is running for $project; try again later."
  exit 1
fi

stamp="$(date -u +%Y%m%dT%H%M%SZ)-$$"
for service in mysql postgres mongodb; do
  case "$service" in
    mysql) extension=sql ;;
    postgres) extension=dump ;;
    mongodb) extension=archive.gz ;;
  esac
  timeout 600 bash "$root/scripts/db.sh" backup "$service" \
    "$directory/scheduled-$stamp-$service.$extension"
done

# Only completed files with this workflow's exact naming convention are eligible.
candidates="$(mktemp "$directory/.retention.XXXXXX")"
removed=0
trap 'rm -f -- "$candidates"' EXIT
find "$directory" -maxdepth 1 -type f -mmin "+$((days * 1440))" -print0 > "$candidates"
while IFS= read -r -d '' file; do
  name="${file##*/}"
  if [[ "$name" =~ ^scheduled-[0-9]{8}T[0-9]{6}Z-[0-9]+-(mysql\.sql|postgres\.dump|mongodb\.archive\.gz)$ ]]; then
    rm -- "$file"
    removed=$((removed + 1))
    log_status INFO "Removed expired scheduled backup: $file"
  fi
done < "$candidates"
log_status PASS "Scheduled backups completed for $project; retention is $days days; removed $removed expired backup(s) (${SECONDS}s)."
