# shellcheck shell=bash
# Shared palette, gate validation, and urgency selection.

codex_theme_load() {
  local theme_path="$1"
  local integer_filter='
        select(type == "number" and . >= 0 and . == floor)
    '

  CODEX_THEME_CRITICAL="$(jq -er '.critical | strings' "$theme_path")" || return
  CODEX_THEME_WARNING="$(jq -er '.warning | strings' "$theme_path")" || return
  CODEX_THEME_SAFE="$(jq -er '.safe | strings' "$theme_path")" || return
  CODEX_THEME_MUTED="$(jq -er '.muted | strings' "$theme_path")" || return
  CODEX_USAGE_WARNING_AT="$(
    jq -er ".gates.usage.warning_at_percent | $integer_filter" "$theme_path"
  )" || return
  CODEX_USAGE_CRITICAL_AT="$(
    jq -er ".gates.usage.critical_at_percent | $integer_filter" "$theme_path"
  )" || return
  CODEX_EXPIRATION_CRITICAL_BELOW="$(
    jq -er ".gates.expiration.critical_below_seconds | $integer_filter" "$theme_path"
  )" || return
  CODEX_EXPIRATION_WARNING_BELOW="$(
    jq -er ".gates.expiration.warning_below_seconds | $integer_filter" "$theme_path"
  )" || return

  ((CODEX_USAGE_WARNING_AT < CODEX_USAGE_CRITICAL_AT)) || return
  ((CODEX_USAGE_CRITICAL_AT <= 100)) || return
  ((CODEX_EXPIRATION_CRITICAL_BELOW < CODEX_EXPIRATION_WARNING_BELOW)) || return
}

codex_theme_state_for_percent() {
  local percent

  percent="$(printf '%.0f' "$1")"
  if ((percent >= CODEX_USAGE_CRITICAL_AT)); then
    printf 'critical'
  elif ((percent >= CODEX_USAGE_WARNING_AT)); then
    printf 'warning'
  else
    printf 'safe'
  fi
}

codex_theme_state_for_remaining() {
  local seconds="$1"

  if ((seconds < CODEX_EXPIRATION_CRITICAL_BELOW)); then
    printf 'critical'
  elif ((seconds < CODEX_EXPIRATION_WARNING_BELOW)); then
    printf 'warning'
  else
    printf 'safe'
  fi
}

codex_theme_hex_for_state() {
  case "$1" in
    critical) printf '%s' "$CODEX_THEME_CRITICAL" ;;
    warning) printf '%s' "$CODEX_THEME_WARNING" ;;
    safe) printf '%s' "$CODEX_THEME_SAFE" ;;
    muted) printf '%s' "$CODEX_THEME_MUTED" ;;
    *) return 1 ;;
  esac
}
