#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d)"
export BACKUP_TEST_PROJECT="infrastructure-retention-test-$$"
directory="$root/backups/scheduled/$BACKUP_TEST_PROJECT"
cleanup() {
  if [[ -L "$directory" ]]; then
    rm -- "$directory"
  elif [[ -d "$directory" ]]; then
    while IFS= read -r -d '' file; do
      rm -- "$file"
    done < <(find "$directory" -maxdepth 1 -type f -print0)
    rmdir -- "$directory"
  fi
  while IFS= read -r -d '' file; do
    rm -- "$file"
  done < <(find "$work" -type f -print0)
  if [[ -d "$work/config/systemd/user" ]]; then
    rmdir -- "$work/config/systemd/user" "$work/config/systemd" "$work/config"
  fi
  rmdir -- "$work"
}
trap cleanup EXIT
trap 'printf "Scheduled-backup test failed at line %s.\n" "$LINENO" >&2' ERR

cat > "$work/docker" <<'EOF'
#!/usr/bin/env bash
set -eu
case "$*" in
  *config*) printf 'name: %s\n' "$BACKUP_TEST_PROJECT" ;;
  *'exec -T postgres '*)
    if [[ "${BACKUP_TEST_FAIL:-}" == true ]]; then exit 1; fi
    printf 'test-only postgres dump\n'
    ;;
  *'exec -T mysql '*) printf 'test-only mysql dump\n' ;;
  *'exec -T mongodb '*) printf 'test-only mongodb dump\n' ;;
  *) exit 1 ;;
esac
EOF
cat > "$work/systemctl" <<'EOF'
#!/usr/bin/env bash
set -eu
[[ "$*" == '--user daemon-reload' ]]
printf '%s\n' "$*" >> "$SCHEDULER_TEST_CALLS"
EOF
chmod +x "$work/docker" "$work/systemctl"
export PATH="$work:$PATH" XDG_CONFIG_HOME="$work/config" SCHEDULER_TEST_CALLS="$work/calls"
unset COMPOSE_FILE COMPOSE_ENV_FILES COMPOSE_PROJECT_NAME

mkdir -p -- "$root/backups/scheduled"
ln -s "$work" "$directory"
if bash "$root/scripts/scheduled-backup.sh" > "$work/output" 2>&1; then exit 1; fi
grep -q 'Refusing symlinked backup directory' "$work/output"
rm -- "$directory"
mkdir -- "$directory"
old="$directory/scheduled-20000101T000000Z-1-mysql.sql"
manual="$directory/manual.sql"
partial="$directory/scheduled-20000101T000000Z-1-mysql.sql.partial.keep"
printf old > "$old"
printf manual > "$manual"
printf partial > "$partial"
touch -d '8 days ago' "$old" "$manual" "$partial"
export BACKUP_TEST_FAIL=true
if bash "$root/scripts/scheduled-backup.sh" > "$work/output" 2>&1; then exit 1; fi
[[ -f "$old" && -f "$manual" && -f "$partial" ]]
unset BACKUP_TEST_FAIL
bash "$root/scripts/scheduled-backup.sh" > "$work/output"
[[ ! -e "$old" && -f "$manual" && -f "$partial" ]]
[[ "$(find "$directory" -name '*-postgres.dump' -type f | wc -l)" == 1 ]]
[[ "$(find "$directory" -name '*-mongodb.archive.gz' -type f | wc -l)" == 1 ]]
if bash "$root/scripts/scheduled-backup.sh" 0 > "$work/output" 2>&1; then exit 1; fi
grep -q 'Usage:' "$work/output"
(
  flock --exclusive 9
  if bash "$root/scripts/scheduled-backup.sh" > "$work/output" 2>&1; then exit 1; fi
  grep -q 'Another scheduled backup is running' "$work/output"
) 9> "$directory/.lock"

bash "$root/scripts/install-backup-timer.sh" > "$work/output"
[[ "$(cat "$work/calls")" == '--user daemon-reload' ]]
timer="$(find "$work/config/systemd/user" -name '*.timer')"
service="$(find "$work/config/systemd/user" -name '*.service')"
grep -q 'OnCalendar=.*03:00:00' "$timer"
grep -q 'Persistent=true' "$timer"
grep -q 'scheduled-backup.sh" 7' "$service"
systemd-analyze verify "$service" "$timer"
grep -q 'enable --now' "$work/output"
if bash "$root/scripts/install-backup-timer.sh" > "$work/output" 2>&1; then exit 1; fi
grep -q 'already exists' "$work/output"
printf 'PASS: seven-day retention only removes owned completed backups after success; locking, symlinks, and disabled timer installation are checked.\n'
