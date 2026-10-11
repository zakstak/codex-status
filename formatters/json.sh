#!/usr/bin/env bash

feature=""

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

if [[ "$(jq -r '.ok' <<<"$payload")" != true ]]; then
  jq '{
        schema_version,
        ok,
        feature,
        error
    }' <<<"$payload"
  exit 0
fi

case "$feature" in
  usage)
    jq '{
            schema_version,
            ok,
            feature,
            cached,
            fetched_at,
            usage: {
                plan_type: .data.plan_type,
                rate_limit: .data.rate_limit,
                code_review_rate_limit: .data.code_review_rate_limit,
                additional_rate_limits: .data.additional_rate_limits,
                credits: .data.credits,
                spend_control: .data.spend_control,
                rate_limit_reached_type: .data.rate_limit_reached_type,
                promo: .data.promo,
                rate_limit_reset_credits: .data.rate_limit_reset_credits
            }
        }' <<<"$payload"
    ;;
  credits)
    jq '{
            schema_version,
            ok,
            feature,
            cached,
            fetched_at,
            available_count: .data.available_count,
            total_earned_count: .data.total_earned_count,
            credits: [
                .data.credits[]?
                | {
                    id,
                    reset_type,
                    is_supported_by_plan,
                    status,
                    granted_at,
                    expires_at,
                    redeem_started_at,
                    redeemed_at,
                    title,
                    description
                }
            ]
        }' <<<"$payload"
    ;;
  *)
    jq -cn \
      --arg feature "$feature" \
      '{
                schema_version: 1,
                ok: false,
                feature: $feature,
                error: "unsupported feature"
            }'
    ;;
esac
