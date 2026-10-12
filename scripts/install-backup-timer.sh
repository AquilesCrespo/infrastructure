#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$root/scripts/lib/common.sh"
usage() {
  cat <<'EOF'
Usage: bash scripts/install-backup-timer.sh
       bash scripts/install-backup-timer.sh --help

Installs a disabled daily systemd user timer; does not run backups or enable it.
Requires Linux systemd user services, mkdir, and cksum. Timer execution requires
Docker access and the scheduled-backup script's dependencies.
Export Compose selectors before installation to capture them in the user units.

Colors are automatic on terminals; set NO_COLOR to disable them.
EOF
}
if [[ $# -eq 1 && ( "$1" == --help || "$1" == -h ) ]]; then
  usage
  exit 0
fi
if [[ $# -ne 0 ]]; then
  log_status FAIL 'This installer accepts no arguments except --help.'
  usage >&2
  exit 1
fi
trap 'abort "$?" "Backup timer installation failed at line $LINENO."' ERR
require_commands systemctl mkdir cksum || exit 1

for value in "$root" "${COMPOSE_PROJECT_NAME:-}" "${COMPOSE_ENV_FILES:-}" "${COMPOSE_FILE:-}"; do
  if [[ "$value" == *['"'%\\]* || "$value" == *$'\n'* || "$value" == *$'\r'* ]]; then
    log_status FAIL 'Paths and Compose selectors must not contain quotes, percent signs, backslashes, or newlines.'
    exit 1
  fi
done
directory="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
mkdir -p -- "$directory"
identity="$(printf '%s' "$root:${COMPOSE_PROJECT_NAME:-}:${COMPOSE_ENV_FILES:-}:${COMPOSE_FILE:-}" | cksum)"
unit="infrastructure-backup-${identity%% *}"
for file in "$directory/$unit.service" "$directory/$unit.timer"; do
  if [[ -e "$file" || -L "$file" ]]; then
    log_status FAIL "Unit already exists; inspect it before reinstalling: $file"
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
log_status PASS 'Installed disabled timer. Enable explicitly:'
printf '  systemctl --user enable --now %s.timer\n' "$unit"
log_status INFO 'Inspect runs:'
printf '  journalctl --user -u %s.service\n' "$unit"
log_status INFO 'Disable:'
printf '  systemctl --user disable --now %s.timer\n' "$unit"
