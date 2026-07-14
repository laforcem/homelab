#!/bin/sh
set -eu
: "${TELEGRAM_BOT_TOKEN:?}" "${TELEGRAM_CHAT_ID_MALC:?}" "${TELEGRAM_CHAT_ID_GRUG:?}"

POLL_INTERVAL="${POLL_INTERVAL:-60}"
STATE_DIR="${STATE_DIR:-/state}"
mkdir -p "$STATE_DIR"

notify() {
  account="$1"; message="$2"; chat_id="$3"
  curl -fsS -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    -d chat_id="$chat_id" \
    -d text="icloudpd (${account}): ${message}"
}

check_account() {
  account="$1"; url="$2"; chat_id="$3"
  state_file="$STATE_DIR/${account}.state"
  prev="$(cat "$state_file" 2>/dev/null || echo unknown)"

  body="$(curl -fsS "$url" || echo "")"
  if echo "$body" | grep -q 'name="code"'; then
    current=need_mfa
  elif echo "$body" | grep -q 'name="password"'; then
    current=need_password
  else
    current=ok
  fi

  if [ "$current" != "$prev" ] && [ "$current" != "ok" ]; then
    notify "$account" "webui is waiting for input ($current) — go handle it now" "$chat_id" \
      || echo "notify failed: $account $current" >&2
  fi
  echo "$current" > "$state_file"
}

while true; do
  check_account malc "http://icloudpd-malc:8080/status" "$TELEGRAM_CHAT_ID_MALC"
  check_account grug "http://icloudpd-grug:8080/status" "$TELEGRAM_CHAT_ID_GRUG"
  sleep "$POLL_INTERVAL"
done
