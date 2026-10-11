# shellcheck shell=bash
# Shared GNU/Linux and macOS date helpers. This file is sourced by formatters.

if date -u -d '@0' '+%s' >/dev/null 2>&1; then
  CODEX_DATE_FLAVOR="gnu"
elif date -u -r 0 '+%s' >/dev/null 2>&1; then
  CODEX_DATE_FLAVOR="bsd"
else
  CODEX_DATE_FLAVOR="unsupported"
fi

codex_iso_to_epoch() {
  local timestamp="$1"
  local normalized

  case "$CODEX_DATE_FLAVOR" in
    gnu)
      date -u -d "$timestamp" '+%s'
      ;;
    bsd)
      normalized="${timestamp%Z}"
      normalized="${normalized%%.*}"
      date -j -u -f '%Y-%m-%dT%H:%M:%S' "$normalized" '+%s'
      ;;
    *)
      return 1
      ;;
  esac
}

codex_epoch_format_local() {
  local epoch="$1"
  local output_format="$2"

  case "$CODEX_DATE_FLAVOR" in
    gnu) date -d "@$epoch" "$output_format" ;;
    bsd) date -r "$epoch" "$output_format" ;;
    *) return 1 ;;
  esac
}

codex_numeric_date() {
  local epoch="$1"
  local numeric
  local month
  local day

  numeric="$(codex_epoch_format_local "$epoch" '+%m/%d')" || return
  month="${numeric%%/*}"
  day="${numeric#*/}"
  month="${month#0}"
  day="${day#0}"
  printf '%s/%s' "$month" "$day"
}

codex_month_date() {
  local epoch="$1"
  local formatted

  formatted="$(codex_epoch_format_local "$epoch" '+%b %d')" || return
  printf '%s' "${formatted/ 0/ }"
}

codex_exact_date() {
  local epoch="$1"
  local formatted

  formatted="$(codex_epoch_format_local "$epoch" '+%a %b %d, %I:%M %p %Z')" ||
    return
  printf '%s' "${formatted// 0/ }"
}
