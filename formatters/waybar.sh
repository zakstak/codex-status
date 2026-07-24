#!/usr/bin/env bash

set -o pipefail

feature=""
layout="full"
formatter_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
theme_path="$formatter_dir/theme.json"

# shellcheck source=date-portability.sh
. "$formatter_dir/date-portability.sh"
# shellcheck source=theme.sh
. "$formatter_dir/theme.sh"

while (( $# > 0 )); do
    case "$1" in
        --feature) feature="$2"; shift 2 ;;
        --layout) layout="$2"; shift 2 ;;
        *) shift ;;
    esac
done

payload="$(cat)"

emit_error() {
    jq -cn \
        --arg text "?" \
        --arg tooltip "$1" \
        '{text: $text, tooltip: $tooltip, class: "error"}'
    exit 0
}

[[ "$(jq -r '.ok' <<<"$payload")" == true ]] ||
    emit_error "$(jq -r '.error // "Codex status unavailable"' <<<"$payload")"

codex_theme_load "$theme_path" ||
    emit_error "Codex status: invalid shared theme"

now="$(date +%s)"

format_duration() {
    local seconds="$1"

    if (( seconds <= 0 )); then
        printf 'now'
    elif (( seconds < 86400 )); then
        printf '%dh %dm' "$((seconds / 3600))" "$(((seconds % 3600) / 60))"
    else
        printf '%dd %dh' "$((seconds / 86400))" "$(((seconds % 86400) / 3600))"
    fi
}

render_credits() {
    local markup=""
    local tooltip
    local nearest_class="safe"

    expirations="$(
        jq -r '
            [.data.credits[]?
                | select(.status == "available")
                | select(.expires_at | type == "string")]
            | sort_by(.expires_at)
            | .[].expires_at
        ' <<<"$payload"
    )"

    if [[ -z "$expirations" ]]; then
        jq -cn \
            --arg text "—" \
            --arg tooltip "Codex reset credits: none available" \
            '{text: $text, tooltip: $tooltip, class: "empty"}'
        return
    fi

    available_count="$(
        jq -r '[.data.credits[]? | select(.status == "available")] | length' \
            <<<"$payload"
    )"
    tooltip="Codex reset credits: $available_count available"

    while IFS= read -r expires_at; do
        [[ -n "$expires_at" ]] || continue
        expires_epoch="$(codex_iso_to_epoch "$expires_at" 2>/dev/null)" || continue
        remaining=$((expires_epoch - now))

        class="$(codex_theme_state_for_remaining "$remaining")"
        color="$(codex_theme_hex_for_state "$class")"

        if [[ "$class" == "critical" ]]; then
            nearest_class="critical"
        elif [[ "$class" == "warning" && "$nearest_class" == "safe" ]]; then
            nearest_class="warning"
        fi

        if [[ "$layout" == "compact" ]]; then
            label="$(codex_numeric_date "$expires_epoch")"
            separator=$'\n'
        else
            label="$(codex_month_date "$expires_epoch")"
            separator="  "
        fi

        [[ -z "$markup" ]] || markup+="$separator"
        markup+="<span foreground=\"$color\">$label</span>"

        if (( remaining <= 0 )); then
            remaining_text="expired"
        else
            remaining_text="$(format_duration "$remaining") remaining"
        fi

        exact="$(codex_exact_date "$expires_epoch")"
        tooltip+=$'\n'"$exact — $remaining_text"
    done <<<"$expirations"

    if [[ "$(jq -r '.cached' <<<"$payload")" == true ]]; then
        tooltip+=$'\n\nCached response'
    fi

    jq -cn \
        --arg text "$markup" \
        --arg tooltip "$tooltip" \
        --arg class "$nearest_class" \
        '{text: $text, tooltip: $tooltip, class: $class}'
}

render_usage() {
    used_percent="$(jq -er '.data.rate_limit.primary_window.used_percent | numbers' <<<"$payload")" ||
        emit_error "Codex usage unavailable: missing primary usage window"
    window_seconds="$(jq -er '.data.rate_limit.primary_window.limit_window_seconds | numbers' <<<"$payload")" ||
        emit_error "Codex usage unavailable: missing window duration"
    reset_at="$(jq -er '.data.rate_limit.primary_window.reset_at | numbers' <<<"$payload")" ||
        emit_error "Codex usage unavailable: missing reset time"

    used_rounded="$(printf '%.0f' "$used_percent")"
    remaining=$((reset_at - now))
    remaining_text="$(format_duration "$remaining")"
    exact_reset="$(codex_exact_date "$reset_at")"

    class="$(codex_theme_state_for_percent "$used_rounded")"
    color="$(codex_theme_hex_for_state "$class")"

    if [[ "$layout" == "compact" ]]; then
        text="<span foreground=\"$color\">󰚩"$'\n'"${used_rounded}%</span>"
    else
        text="<span foreground=\"$color\">󰚩 ${used_rounded}% · $remaining_text</span>"
    fi

    tooltip="Codex usage: ${used_rounded}% used"
    tooltip+=$'\n'"$((window_seconds / 86400))d window resets $exact_reset"
    tooltip+=$'\n'"$remaining_text remaining"

    while IFS=$'\t' read -r limit_name additional_used additional_window additional_reset; do
        [[ -n "$limit_name" ]] || continue
        additional_remaining=$((additional_reset - now))
        tooltip+=$'\n\n'"$limit_name: $(printf '%.0f' "$additional_used")% used"
        tooltip+=$'\n'"$((additional_window / 86400))d window · $(format_duration "$additional_remaining") remaining"
    done < <(
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
    )

    plan_type="$(jq -r '.data.plan_type // empty' <<<"$payload")"
    reset_credit_count="$(jq -r '.data.rate_limit_reset_credits.available_count // empty' <<<"$payload")"

    [[ -z "$plan_type" ]] || tooltip+=$'\n\n'"Plan: $plan_type"
    [[ -z "$reset_credit_count" ]] || tooltip+=$'\n'"Reset credits: $reset_credit_count available"
    if [[ "$(jq -r '.cached' <<<"$payload")" == true ]]; then
        tooltip+=$'\n\nCached response'
    fi

    jq -cn \
        --arg text "$text" \
        --arg tooltip "$tooltip" \
        --arg class "$class" \
        '{text: $text, tooltip: $tooltip, class: $class}'
}

case "$feature" in
    credits) render_credits ;;
    usage) render_usage ;;
    *) emit_error "Codex status: unsupported feature $feature" ;;
esac
