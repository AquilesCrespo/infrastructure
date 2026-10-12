#!/usr/bin/env bash

log_status() {
  local level="$1" fd=1 color=""
  shift
  case "$level" in
    FAIL) fd=2; color=31 ;;
    WARN) fd=2; color=33 ;;
    PASS) color=32 ;;
    SKIP) color=33 ;;
    INFO) color=2 ;;
  esac
  if [[ -t "$fd" && "${TERM:-dumb}" != dumb && -z "${NO_COLOR+x}" ]]; then
    printf '\033[%sm%s\033[0m %s\n' "$color" "$level" "$*" >&"$fd"
  else
    printf '%s %s\n' "$level" "$*" >&"$fd"
  fi
}

require_commands() {
  local command missing=0
  for command in "$@"; do
    if ! command -v "$command" > /dev/null 2>&1; then
      log_status FAIL "Required command '$command' is unavailable; install it or check PATH."
      missing=1
    fi
  done
  return "$missing"
}

abort() {
  local status="$1"
  shift
  log_status FAIL "$*"
  exit "$status"
}
