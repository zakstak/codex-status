#!/usr/bin/env bash

# Fetch and normalize Codex account status. Presentation belongs to the
# formatter selected with --format.

set +x
set -o pipefail

feature=""
output_format=""
layout="full"
auth_path="${CODEX_HOME:-$HOME/.codex}/auth.json"
case "$(uname -s)" in
    Darwin) cache_root="${XDG_CACHE_HOME:-$HOME/Library/Caches}" ;;
    *) cache_root="${XDG_CACHE_HOME:-$HOME/.cache}" ;;
esac
cache_dir="$cache_root/codex-status"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
formatter_dir="$script_dir/formatters"

show_help() {
    printf '%s\n' \
        'Usage: codex-status.sh (--usage | --credits) --format FORMAT [--compact | --full]' \
        '' \
        'Formats: json, pretty, waybar, codexcli, zellij, tmux' \
        'Requires: bash 3.2+, curl, jq' \
        'Supported platforms: macOS and Linux'
}

formatter_path_for() {
    case "$1" in
        json|pretty|waybar|codexcli|zellij|tmux)
            printf '%s/%s.sh' "$formatter_dir" "$1"
            ;;
        *)
            return 1
            ;;
    esac
}

render() {
    local formatter_path

    formatter_path="$(formatter_path_for "$output_format")" || return 1
    bash "$formatter_path" --feature "$feature" --layout "$layout"
}

emit_error() {
    local message="$1"
    local formatter_path

    if formatter_path="$(formatter_path_for "$output_format" 2>/dev/null)" &&
        [[ -r "$formatter_path" ]]; then
        jq -cn \
            --arg feature "$feature" \
            --arg error "$message" \
            '{schema_version: 1, ok: false, feature: $feature, error: $error}' |
            render
    else
        printf 'Codex status: %s\n' "$message" >&2
    fi
    exit 0
}

while (( $# > 0 )); do
    case "$1" in
        --credits|--usage)
            [[ -z "$feature" ]] || emit_error "choose exactly one feature"
            feature="${1#--}"
            shift
            ;;
        --format)
            (( $# >= 2 )) || emit_error "--format requires a value"
            output_format="$2"
            shift 2
            ;;
        --format=*)
            output_format="${1#--format=}"
            shift
            ;;
        --compact)
            layout="compact"
            shift
            ;;
        --full)
            layout="full"
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            emit_error "unknown option $1"
            ;;
    esac
done

[[ -n "$feature" ]] || emit_error "use --credits or --usage"
[[ -n "$output_format" ]] || emit_error "--format is required"
formatter_path="$(formatter_path_for "$output_format")" ||
    emit_error "unsupported format $output_format"
[[ -r "$formatter_path" ]] ||
    emit_error "unsupported format $output_format"

case "$feature" in
    credits)
        endpoint="rate-limit-reset-credits"
        cache_path="$cache_dir/codex-credit-expirations.json"
        validator='.credits | type == "array"'
        error_label="Codex credits"
        ;;
    usage)
        endpoint="usage"
        cache_path="$cache_dir/codex-usage.json"
        validator='.rate_limit | type == "object"'
        error_label="Codex usage"
        ;;
esac

token="$(jq -er '.tokens.access_token' "$auth_path" 2>/dev/null)" ||
    emit_error "$error_label unavailable: could not read access token"
account_id="$(jq -er '.tokens.account_id' "$auth_path" 2>/dev/null)" ||
    emit_error "$error_label unavailable: could not read account ID"

# Credentials travel through curl's stdin config so they never appear in
# process arguments.
response="$(
    printf 'header = "Authorization: Bearer %s"\nheader = "ChatGPT-Account-ID: %s"\n' \
        "$token" "$account_id" |
        curl --fail --silent --show-error --max-time 15 \
            --config - \
            "https://chatgpt.com/backend-api/wham/$endpoint" \
            -H 'originator: Codex Desktop' \
            2>/dev/null
)"
curl_status=$?
unset token account_id
using_cache=false

if (( curl_status == 0 )) &&
    jq -e "$validator" >/dev/null 2>&1 <<<"$response"; then
    umask 077
    mkdir -p "$cache_dir"
    printf '%s\n' "$response" >"$cache_path"
elif [[ -r "$cache_path" ]] &&
    jq -e "$validator" "$cache_path" >/dev/null 2>&1; then
    response="$(<"$cache_path")"
    using_cache=true
else
    emit_error "$error_label unavailable: request failed"
fi

jq -cn \
    --arg feature "$feature" \
    --argjson cached "$using_cache" \
    --argjson fetched_at "$(date +%s)" \
    --argjson data "$response" \
    '{
        schema_version: 1,
        ok: true,
        feature: $feature,
        cached: $cached,
        fetched_at: $fetched_at,
        data: $data
    }' |
    render
