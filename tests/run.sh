#!/usr/bin/env bash
# Offline integration coverage for the installed runtime and formatter protocols.
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/codex-status-tests.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT
export TZ=UTC LC_ALL=C NO_COLOR=1
export CODEX_HOME="$test_dir/auth" XDG_CACHE_HOME="$test_dir/cache"
export TEST_RESPONSE="$test_dir/response.json"
mkdir -p "$CODEX_HOME" "$test_dir/bin"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

# Only synthetic credentials are used, and no request leaves this test process.
jq -n '{tokens: {access_token: "fixture-token", account_id: "fixture-account"}}' >"$CODEX_HOME/auth.json"
cat >"$test_dir/bin/curl" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
case "$*" in
  *fixture-token* | *fixture-account*) exit 90 ;;
esac
config="$(cat)"
[[ "$config" == *'Authorization: Bearer fixture-token'* ]]
[[ "$config" == *'ChatGPT-Account-ID: fixture-account'* ]]
[[ "${TEST_CURL_FAIL:-0}" == 0 ]] || exit 22
cat "$TEST_RESPONSE"
SH
chmod +x "$test_dir/bin/curl"
export PATH="$test_dir/bin:$PATH"

bash "$repo_dir/install.sh" --config-root "$test_dir/config" >/dev/null
installed="$test_dir/config/codex-status"
cmp "$repo_dir/formatters/theme.json" "$installed/formatters/theme.default.json"
jq '.safe = "#123456"' "$installed/formatters/theme.json" >"$test_dir/custom-theme.json"
cp "$test_dir/custom-theme.json" "$installed/formatters/theme.json"
bash "$repo_dir/install.sh" --config-root "$test_dir/config" >/dev/null
cmp "$test_dir/custom-theme.json" "$installed/formatters/theme.json"
cmp "$repo_dir/formatters/theme.json" "$installed/formatters/theme.default.json"
if bash "$repo_dir/install.sh" --config-root >/dev/null 2>&1; then
  fail 'installer accepted a missing config-root argument'
fi

reset_at="$(($(date +%s) + 7200))"
jq -n --argjson reset "$reset_at" '{
  email: "private@example.invalid", plan_type: "plus",
  rate_limit: {allowed: true, limit_reached: false,
    primary_window: {used_percent: 75, limit_window_seconds: 604800, reset_at: $reset}},
  additional_rate_limits: [], rate_limit_reset_credits: {available_count: 1}
}' >"$TEST_RESPONSE"

for surface in json pretty waybar codexcli tmux zellij; do
  output="$(bash "$installed/codex-status.sh" --usage --format "$surface" --compact)"
  case "$surface" in
    json)
      jq -e '.schema_version == 1 and .ok and .feature == "usage" and
        (.cached | not) and .usage.rate_limit.primary_window.used_percent == 75 and
        (has("data") | not) and (has("email") | not)' <<<"$output" >/dev/null
      ;;
    waybar)
      jq -e '.class == "warning" and (.text | contains("75%")) and
        (.tooltip | contains("Plan: plus"))' <<<"$output" >/dev/null
      ;;
    pretty)
      [[ "$output" == *'Codex usage'* && "$output" == *'75% used'* ]] || fail 'pretty usage'
      [[ "$output" != *$'\033'* ]] || fail 'NO_COLOR ignored'
      ;;
    codexcli) [[ "$output" == 'weekly 75% · '* ]] || fail 'codexcli usage' ;;
    tmux | zellij) [[ "$output" == '󰚩 75% · '* ]] || fail "$surface usage" ;;
  esac
  [[ "$output" != *'private@example.invalid'* ]] || fail "$surface leaked email"
done

export TEST_CURL_FAIL=1
output="$(bash "$installed/codex-status.sh" --usage --format json)"
jq -e '.ok and .cached' <<<"$output" >/dev/null
unset TEST_CURL_FAIL
[[ -f "$XDG_CACHE_HOME/codex-status/codex-usage.json" ]] || fail 'cache missing'
[[ ! -r "$XDG_CACHE_HOME/codex-status/auth.json" ]] || fail 'auth cached'
if [[ "$(uname -s)" == Darwin ]]; then
  cache_mode="$(stat -f '%Lp' "$XDG_CACHE_HOME/codex-status/codex-usage.json")"
else
  cache_mode="$(stat -c '%a' "$XDG_CACHE_HOME/codex-status/codex-usage.json")"
fi
[[ "$cache_mode" == 600 ]] || fail 'cache is not user-only'

jq -n '{available_count: 1, total_earned_count: 2, credits: [
  {id: "fixture-credit", status: "available", expires_at: "2099-01-02T12:00:00.123Z", title: "Fixture"},
  {id: "fixture-used", status: "redeemed", expires_at: "2099-01-01T12:00:00Z", title: "Used"}
]}' >"$TEST_RESPONSE"
for surface in json pretty waybar codexcli tmux zellij; do
  output="$(bash "$installed/codex-status.sh" --credits --format "$surface" --compact)"
  case "$surface" in
    json) jq -e '.ok and .feature == "credits" and .available_count == 1 and (.credits | length == 2)' <<<"$output" >/dev/null ;;
    pretty) [[ "$output" == *'Codex reset credits'* && "$output" == *'Fixture'* ]] || fail 'pretty credits' ;;
    waybar) jq -e '.class == "safe" and (.text | contains("1/2")) and (.text | contains("1/1") | not)' <<<"$output" >/dev/null ;;
    *) [[ "$output" == 'resets 1/2' ]] || fail "$surface credits" ;;
  esac
done
output="$(bash "$installed/codex-status.sh" --credits --format tmux --full)"
[[ "$output" == 'resets Jan 2' ]] || fail 'full credit date'

printf '%s\n' '{"available_count":0,"total_earned_count":0,"credits":[]}' >"$TEST_RESPONSE"
output="$(bash "$installed/codex-status.sh" --credits --format waybar)"
jq -e '.class == "empty"' <<<"$output" >/dev/null
mv "$CODEX_HOME/auth.json" "$CODEX_HOME/auth.saved"
output="$(bash "$installed/codex-status.sh" --usage --format json)"
jq -e '(.ok | not) and (.error | contains("access token"))' <<<"$output" >/dev/null
output="$(bash "$installed/codex-status.sh" --usage --credits --format json 2>&1)"
[[ "$output" == *'choose exactly one feature'* ]] || fail 'conflicting features accepted'

# Verify both platform branches select the documented date flags. BSD is
# simulated here; this is not a substitute for a native macOS test run.
(
  date() {
    case "$*" in
      '-u -d @0 +%s') return 1 ;;
      '-u -r 0 +%s') printf '0\n' ;;
      '-j -u -f %Y-%m-%dT%H:%M:%S 2099-01-02T12:00:00 +%s') printf '4071038400\n' ;;
      '-r 0 +%m/%d') printf '01/01\n' ;;
      *) return 2 ;;
    esac
  }
  # shellcheck source=../formatters/date-portability.sh
  . "$repo_dir/formatters/date-portability.sh"
  [[ "$CODEX_DATE_FLAVOR" == bsd ]]
  [[ "$(codex_iso_to_epoch '2099-01-02T12:00:00.123Z')" == 4071038400 ]]
  [[ "$(codex_numeric_date 0)" == 1/1 ]]
)

printf 'Offline shell integration checks passed.\n'
