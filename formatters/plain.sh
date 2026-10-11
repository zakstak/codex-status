#!/usr/bin/env bash

surface=""
feature=""
layout="compact"
formatter_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

# shellcheck source=date-portability.sh
. "$formatter_dir/date-portability.sh"

while (($# > 0)); do
  case "$1" in
    --surface)
      surface="$2"
      shift 2
      ;;
    --feature)
      feature="$2"
      shift 2
      ;;
    --layout)
      layout="$2"
      shift 2
      ;;
    *) shift ;;
  esac
done

payload="$(cat)"

if [[ "$(jq -r '.ok' <<<"$payload")" != true ]]; then
  printf 'Codex unavailable'
  exit 0
fi

now="$(date +%s)"

format_duration() {
  local seconds="$1"

  if ((seconds <= 0)); then
    printf 'now'
  elif ((seconds < 86400)); then
    printf '%dh%02dm' "$((seconds / 3600))" "$(((seconds % 3600) / 60))"
  else
    printf '%dd%02dh' "$((seconds / 86400))" "$(((seconds % 86400) / 3600))"
  fi
}

case "$feature" in
  usage)
    used_percent_raw="$(jq -r '.data.rate_limit.primary_window.used_percent' <<<"$payload")"
    used_percent="$(printf '%.0f' "$used_percent_raw")"
    reset_at="$(jq -r '.data.rate_limit.primary_window.reset_at' <<<"$payload")"
    remaining="$(format_duration "$((reset_at - now))")"

    case "$surface" in
      codexcli) printf 'weekly %s%% · %s' "$used_percent" "$remaining" ;;
      tmux | zellij) printf '󰚩 %s%% · %s' "$used_percent" "$remaining" ;;
    esac
    ;;
  credits)
    expirations="$(
      jq -r '
                [.data.credits[]? | select(.status == "available")]
                | sort_by(.expires_at)
                | .[].expires_at
            ' <<<"$payload"
    )"
    joined=""

    if [[ "$layout" == "full" ]]; then
      date_style="month"
    else
      date_style="numeric"
    fi

    while IFS= read -r expires_at; do
      [[ -n "$expires_at" ]] || continue
      expires_epoch="$(codex_iso_to_epoch "$expires_at" 2>/dev/null)" || continue
      if [[ "$date_style" == "month" ]]; then
        label="$(codex_month_date "$expires_epoch")"
      else
        label="$(codex_numeric_date "$expires_epoch")"
      fi
      [[ -z "$joined" ]] || joined+=" · "
      joined+="$label"
    done <<<"$expirations"

    printf 'resets %s' "${joined:-none}"
    ;;
esac
