#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ $# -ne 0 ]]; then
  printf 'Usage: bash scripts/install-backup-timer.sh\nInstalls a disabled daily user timer; does not run backups or enable it.\n' >&2
  exit 1
fi
trap 'printf "Backup timer installation failed at line %s.\n" "$LINENO" >&2' ERR

for value in "$root" "${COMPOSE_PROJECT_NAME:-}" "${COMPOSE_ENV_FILES:-}" "${COMPOSE_FILE:-}"; do
  if [[ "$value" == *['"'\%\\]* || "$value" == *$'\n'* || "$value" == *$'\r'* ]]; then
    printf 'Paths and Compose selectors must not contain quotes, percent signs, backslashes, or newlines.\n' >&2
    exit 1
  fi
done
directory="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
mkdir -p -- "$directory"
identity="$(printf '%s' "$root:${COMPOSE_PROJECT_NAME:-}:${COMPOSE_ENV_FILES:-}:${COMPOSE_FILE:-}" | cksum)"
unit="infrastructure-backup-${identity%% *}"
for file in "$directory/$unit.service" "$directory/$unit.timer"; do
  if [[ -e "$file" || -L "$file" ]]; then
    printf 'Unit already exists; inspect it before reinstalling: %s\n' "$file" >&2
    exit 1
  fi
done
{
  printf '[Unit]\nDescription=Local infrastructure database backups\n\n[Service]\nType=oneshot\n'
  printf 'WorkingDirectory=%s\n' "$root"
  printf 'Environment="PATH=%s"\n' "/usr/local/bin:/usr/bin:/bin"
  if [[ -n "${COMPOSE_PROJECT_NAME:-}" ]]; then
    printf 'Environment="COMPOSE_PROJECT_NAME=%s"\n' "$COMPOSE_PROJECT_NAME"
  fi
  if [[ -n "${COMPOSE_ENV_FILES:-}" ]]; then
    printf 'Environment="COMPOSE_ENV_FILES=%s"\n' "$COMPOSE_ENV_FILES"
  fi
  if [[ -n "${COMPOSE_FILE:-}" ]]; then
    printf 'Environment="COMPOSE_FILE=%s"\n' "$COMPOSE_FILE"
  fi
  printf 'ExecStart=/usr/bin/bash "%s/scripts/scheduled-backup.sh" 7\n' "$root"
  printf 'UMask=0077\nTimeoutStartSec=35min\n'
} > "$directory/$unit.service"
cat > "$directory/$unit.timer" <<EOF
[Unit]
Description=Daily local infrastructure backup (opt-in)

[Timer]
OnCalendar=*-*-* 03:00:00
Persistent=true
RandomizedDelaySec=15min
Unit=$unit.service

[Install]
WantedBy=timers.target
EOF
systemctl --user daemon-reload
printf 'Installed disabled timer. Enable explicitly:\n  systemctl --user enable --now %s.timer\n' "$unit"
printf 'Inspect runs:\n  journalctl --user -u %s.service\n' "$unit"
printf 'Disable:\n  systemctl --user disable --now %s.timer\n' "$unit"
