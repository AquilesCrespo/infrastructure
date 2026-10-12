#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
days="${1:-7}"
if [[ $# -gt 1 || ! "$days" =~ ^[1-9][0-9]{0,3}$ ]]; then
  printf 'Usage: bash scripts/scheduled-backup.sh [retention-days: 1-9999]\n' >&2
  exit 1
fi
trap 'printf "Scheduled backup failed at line %s; retention cleanup was not completed.\n" "$LINENO" >&2' ERR

if ! project="$(docker compose --project-directory "$root" config 2>/dev/null |
    sed -n 's/^name: //p')"; then
  printf 'Cannot resolve Compose project; check configuration and .env.\n' >&2
  exit 1
fi
if [[ ! "$project" =~ ^[a-z0-9][a-z0-9_-]*$ ]]; then
  printf 'Invalid or missing Compose project name.\n' >&2
  exit 1
fi
for directory in "$root/backups" "$root/backups/scheduled" "$root/backups/scheduled/$project"; do
  if [[ -L "$directory" ]]; then
    printf 'Refusing symlinked backup directory: %s\n' "$directory" >&2
    exit 1
  fi
  mkdir -p -- "$directory"
done
directory="$root/backups/scheduled/$project"
if [[ -L "$directory/.lock" ]]; then
  printf 'Refusing symlinked backup lock.\n' >&2
  exit 1
fi
exec 9> "$directory/.lock"
if ! flock --nonblock 9; then
  printf 'Another scheduled backup is running for %s; try again later.\n' "$project" >&2
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
trap 'rm -f -- "$candidates"' EXIT
find "$directory" -maxdepth 1 -type f -mmin "+$((days * 1440))" -print0 > "$candidates"
while IFS= read -r -d '' file; do
  name="${file##*/}"
  if [[ "$name" =~ ^scheduled-[0-9]{8}T[0-9]{6}Z-[0-9]+-(mysql\.sql|postgres\.dump|mongodb\.archive\.gz)$ ]]; then
    rm -- "$file"
    printf 'Removed expired scheduled backup: %s\n' "$file"
  fi
done < "$candidates"
printf 'Scheduled backups completed for %s; retention is %s days.\n' "$project" "$days"
