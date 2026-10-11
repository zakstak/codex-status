#!/usr/bin/env bash

feature=""
formatter_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
theme_path="$formatter_dir/theme.json"

# shellcheck source=date-portability.sh
. "$formatter_dir/date-portability.sh"
# shellcheck source=theme.sh
. "$formatter_dir/theme.sh"

while (($# > 0)); do
  case "$1" in
    --feature)
      feature="$2"
      shift 2
      ;;
    --layout) shift 2 ;;
    *) shift ;;
  esac
done

payload="$(cat)"

ansi_from_hex() {
  local hex
  local red
  local green
  local blue

  if [[ -n "${NO_COLOR:-}" || "${TERM:-}" == "dumb" ]]; then
    return
  fi

  hex="${1#\#}"
  red=$((16#${hex:0:2}))
  green=$((16#${hex:2:2}))
  blue=$((16#${hex:4:2}))
  printf '\033[38;2;%d;%d;%dm' "$red" "$green" "$blue"
}

codex_theme_load "$theme_path" || {
  printf 'Codex status unavailable\n  Invalid shared theme\n'
  exit 0
}
safe_color="$(ansi_from_hex "$CODEX_THEME_SAFE")"
warning_color="$(ansi_from_hex "$CODEX_THEME_WARNING")"
critical_color="$(ansi_from_hex "$CODEX_THEME_CRITICAL")"
muted_color="$(ansi_from_hex "$CODEX_THEME_MUTED")"

if [[ -n "$safe_color" ]]; then
  reset_color=$'\033[0m'
  bold=$'\033[1m'
else
  reset_color=""
  bold=""
fi

if [[ "$(jq -r '.ok' <<<"$payload")" != true ]]; then
  printf '%s%sCodex status unavailable%s\n  %s%s%s\n' \
    "$bold" "$critical_color" "$reset_color" \
    "$muted_color" "$(jq -r '.error // "Unknown error"' <<<"$payload")" \
    "$reset_color"
  exit 0
fi

now="$(date +%s)"

format_duration() {
  local seconds="$1"

  if ((seconds <= 0)); then
    printf 'now'
  elif ((seconds < 86400)); then
    printf '%dh %dm' "$((seconds / 3600))" "$(((seconds % 3600) / 60))"
  else
    printf '%dd %dh' "$((seconds / 86400))" "$(((seconds % 86400) / 3600))"
  fi
}

yes_no() {
  if [[ "$1" == true ]]; then
    printf 'yes'
  else
    printf 'no'
  fi
}

color_for_percent() {
  color_for_state "$(codex_theme_state_for_percent "$1")"
}

color_for_remaining() {
  color_for_state "$(codex_theme_state_for_remaining "$1")"
}

color_for_state() {
  case "$1" in
    critical) printf '%s' "$critical_color" ;;
    warning) printf '%s' "$warning_color" ;;
    safe) printf '%s' "$safe_color" ;;
    muted) printf '%s' "$muted_color" ;;
    *) return 1 ;;
  esac
}

print_usage() {
  plan_type="$(jq -r '.data.plan_type // "unknown"' <<<"$payload")"
  allowed="$(jq -r '.data.rate_limit.allowed // false' <<<"$payload")"
  limit_reached="$(jq -r '.data.rate_limit.limit_reached // false' <<<"$payload")"
  used_percent="$(jq -r '.data.rate_limit.primary_window.used_percent' <<<"$payload")"
  window_seconds="$(jq -r '.data.rate_limit.primary_window.limit_window_seconds' <<<"$payload")"
  reset_at="$(jq -r '.data.rate_limit.primary_window.reset_at' <<<"$payload")"
  reset_credits="$(jq -r '.data.rate_limit_reset_credits.available_count // 0' <<<"$payload")"
  reset_remaining="$(format_duration "$((reset_at - now))")"
  reset_exact="$(codex_exact_date "$reset_at")"
  usage_color="$(color_for_percent "$used_percent")"

  printf '%s%sCodex usage%s\n' "$bold" "$muted_color" "$reset_color"
  printf '  %s%-16s%s %s\n' "$muted_color" 'Plan' "$reset_color" "$plan_type"
  printf '  %s%-16s%s %s%s%%%s used over %sd\n' \
    "$muted_color" 'Primary limit' "$reset_color" \
    "$usage_color" "$used_percent" "$reset_color" "$((window_seconds / 86400))"
  printf '  %s%-16s%s %s%s (%s remaining)%s\n' \
    "$muted_color" 'Resets' "$reset_color" \
    "$usage_color" "$reset_exact" "$reset_remaining" "$reset_color"

  if [[ "$allowed" == true ]]; then
    allowed_color="$safe_color"
  else
    allowed_color="$critical_color"
  fi
  if [[ "$limit_reached" == true ]]; then
    reached_color="$critical_color"
  else
    reached_color="$safe_color"
  fi

  printf '  %s%-16s%s %s%s%s\n' \
    "$muted_color" 'Allowed' "$reset_color" \
    "$allowed_color" "$(yes_no "$allowed")" "$reset_color"
  printf '  %s%-16s%s %s%s%s\n' \
    "$muted_color" 'Limit reached' "$reset_color" \
    "$reached_color" "$(yes_no "$limit_reached")" "$reset_color"
  printf '  %s%-16s%s %s%s%s\n' \
    "$muted_color" 'Reset credits' "$reset_color" \
    "$safe_color" "$reset_credits" "$reset_color"

  additional_limits="$(
    jq -r '
            .data.additional_rate_limits[]?
            | select(.rate_limit.primary_window != null)
            | [
                .limit_name,
                .rate_limit.primary_window.used_percent,
                .rate_limit.primary_window.limit_window_seconds,
                .rate_limit.primary_window.reset_at
            ]
            | @tsv
        ' <<<"$payload"
  )"

  if [[ -n "$additional_limits" ]]; then
    printf '\n%s%sAdditional limits%s\n' "$bold" "$muted_color" "$reset_color"
    while IFS=$'\t' read -r limit_name additional_used additional_window additional_reset; do
      [[ -n "$limit_name" ]] || continue
      additional_remaining="$(format_duration "$((additional_reset - now))")"
      additional_color="$(color_for_percent "$additional_used")"
      printf '  %s%s%s\n' "$muted_color" "$limit_name" "$reset_color"
      printf '    %s%s%%%s used over %sd · resets in %s\n' \
        "$additional_color" "$additional_used" "$reset_color" \
        "$((additional_window / 86400))" "$additional_remaining"
    done <<<"$additional_limits"
  fi
}

print_credits() {
  available_count="$(jq -r '.data.available_count // 0' <<<"$payload")"
  total_earned_count="$(jq -r '.data.total_earned_count // 0' <<<"$payload")"
  expirations="$(
    jq -r '
            [.data.credits[]?]
            | sort_by(.expires_at)
            | .[]
            | [.status, .expires_at, .title]
            | @tsv
        ' <<<"$payload"
  )"

  printf '%s%sCodex reset credits%s\n' "$bold" "$muted_color" "$reset_color"
  printf '  %s%-16s%s %s%s%s\n' \
    "$muted_color" 'Available' "$reset_color" \
    "$safe_color" "$available_count" "$reset_color"
  printf '  %s%-16s%s %s\n' \
    "$muted_color" 'Total earned' "$reset_color" "$total_earned_count"

  if [[ -n "$expirations" ]]; then
    printf '\n%s%sCredits%s\n' "$bold" "$muted_color" "$reset_color"
    while IFS=$'\t' read -r status expires_at title; do
      [[ -n "$expires_at" ]] || continue
      expires_epoch="$(codex_iso_to_epoch "$expires_at" 2>/dev/null)" || continue
      exact="$(codex_exact_date "$expires_epoch")"
      remaining_seconds=$((expires_epoch - now))
      remaining="$(format_duration "$remaining_seconds")"
      expiration_color="$(color_for_remaining "$remaining_seconds")"
      printf '  %s%-12s%s %s\n' \
        "$expiration_color" "$status" "$reset_color" "${title:-Credit}"
      printf '    %sExpires %s (%s remaining)%s\n' \
        "$expiration_color" "$exact" "$remaining" "$reset_color"
    done <<<"$expirations"
  fi
}

case "$feature" in
  usage) print_usage ;;
  credits) print_credits ;;
  *) printf '%sCodex status unavailable%s\n  Unsupported feature: %s\n' \
    "$critical_color" "$reset_color" "$feature" ;;
esac

if [[ "$(jq -r '.cached' <<<"$payload")" == true ]]; then
  printf '\n%sCached response%s\n' "$warning_color" "$reset_color"
fi
