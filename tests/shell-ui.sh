#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$root/scripts/lib/common.sh"
require_commands script mktemp grep ln stat find || exit 1
work="$(mktemp -d)"
bash_path="$(command -v bash)"
cleanup() {
  rm -f -- "$work/probe.sh" "$work/stdout" "$work/stderr" "$work/terminal" \
    "$work/docker" "$work/backup.sql" "$work/no-deps/dirname" "$work/no-deps/cat"
  rmdir -- "$work/no-deps" "$work"
}
trap cleanup EXIT
trap 'printf "Shell UI test failed at line %s.\n" "$LINENO" >&2' ERR

cat > "$work/probe.sh" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
source "$1"
log_status PASS 'Successful operation'
log_status INFO 'Informational message'
log_status SKIP 'Optional check'
log_status WARN 'Warning message'
log_status FAIL 'Failure message'
EOF
unset NO_COLOR
export TERM=xterm
bash "$work/probe.sh" "$root/scripts/lib/common.sh" > "$work/stdout" 2> "$work/stderr"
grep -Fxq 'PASS Successful operation' "$work/stdout"
grep -Fxq 'FAIL Failure message' "$work/stderr"
grep -Fxq 'WARN Warning message' "$work/stderr"
if grep -Fq $'\033' "$work/stdout" "$work/stderr"; then exit 1; fi
if grep -Eq '^(WARN|FAIL)' "$work/stdout" || grep -Eq '^(PASS|INFO|SKIP)' "$work/stderr"; then exit 1; fi

printf -v probe '%q ' "$bash_path" "$work/probe.sh" "$root/scripts/lib/common.sh"
script -q -e -c "$probe" /dev/null > "$work/terminal"
grep -Fq $'\033[32mPASS\033[0m' "$work/terminal"
grep -Fq $'\033[33mWARN\033[0m' "$work/terminal"
grep -Fq $'\033[31mFAIL\033[0m' "$work/terminal"
grep -Fq $'\033[2mINFO\033[0m' "$work/terminal"
NO_COLOR="" script -q -e -c "$probe" /dev/null > "$work/terminal"
if grep -Fq $'\033' "$work/terminal"; then exit 1; fi
TERM=dumb script -q -e -c "$probe" /dev/null > "$work/terminal"
if grep -Fq $'\033' "$work/terminal"; then exit 1; fi
printf -v redirected '%s > %q' "$probe" "$work/stdout"
script -q -e -c "$redirected" /dev/null > "$work/terminal"
if grep -Fq $'\033' "$work/stdout"; then exit 1; fi
grep -Fq $'\033[31mFAIL\033[0m' "$work/terminal"

status=0
# The child shell receives the helper path as its first positional argument.
# shellcheck disable=SC2016
PATH="" "$bash_path" -c 'source "$1"; require_commands missing-command-one missing-command-two' \
  bash "$root/scripts/lib/common.sh" \
  > "$work/stdout" 2> "$work/stderr" || status=$?
[[ "$status" == 1 ]]
grep -q missing-command-one "$work/stderr"
grep -q missing-command-two "$work/stderr"
[[ ! -s "$work/stdout" ]]

mkdir "$work/no-deps"
ln -s "$(command -v dirname)" "$work/no-deps/dirname"
ln -s "$(command -v cat)" "$work/no-deps/cat"
for file in doctor db scheduled-backup install-backup-timer; do
  for option in --help -h; do
    PATH="$work/no-deps" "$bash_path" "$root/scripts/$file.sh" "$option" \
      > "$work/stdout" 2> "$work/stderr"
    grep -q 'Usage:' "$work/stdout"
    [[ ! -s "$work/stderr" ]]
  done
  case "$file" in
    doctor) arguments=(redis); dependency=docker ;;
    db) arguments=(seed mysql); dependency=docker ;;
    scheduled-backup) arguments=(7); dependency=docker ;;
    install-backup-timer) arguments=(); dependency=systemctl ;;
  esac
  status=0
  PATH="$work/no-deps" "$bash_path" "$root/scripts/$file.sh" "${arguments[@]}" \
    > "$work/stdout" 2> "$work/stderr" || status=$?
  [[ "$status" == 1 && ! -s "$work/stdout" ]]
  grep -q "Required command '$dependency'" "$work/stderr"
done

cat > "$work/docker" <<'EOF'
#!/usr/bin/env bash
set -eu
if [[ "${SHELL_UI_FAIL:-}" == true ]]; then
  printf partial-dump
  exit 37
fi
printf test-dump
EOF
chmod +x "$work/docker"
PATH="$work:$PATH" bash "$root/scripts/db.sh" backup mysql "$work/backup.sql" \
  > "$work/stdout" 2> "$work/stderr"
grep -Eq '^PASS Backup saved to .* \(9 bytes, [0-9]+s; private file permissions\)\.$' "$work/stdout"
[[ "$(cat "$work/backup.sql")" == test-dump && "$(stat -c '%a' "$work/backup.sql")" == 600 ]]
rm -- "$work/backup.sql"
status=0
PATH="$work:$PATH" SHELL_UI_FAIL=true bash "$root/scripts/db.sh" backup mysql "$work/backup.sql" \
  > "$work/stdout" 2> "$work/stderr" || status=$?
[[ "$status" == 37 && ! -e "$work/backup.sql" ]]
[[ -z "$(find "$work" -name '*.partial.*' -print)" ]]
grep -q '^FAIL Database command failed' "$work/stderr"
if grep -q '^PASS' "$work/stdout"; then exit 1; fi
printf 'PASS: terminal colors, NO_COLOR, redirected streams, help, dependencies, backup summaries, and failure exit codes.\n'
