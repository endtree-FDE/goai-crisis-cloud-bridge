#!/usr/bin/env bash
# goai-crisis-cloud-bridge · 在 controller 容器内向指定房间发一条消息（只读 env，不打印 token）
# 用法（在容器内）：bash send-room-message.sh '<room_id>' /tmp/dispatch.txt
set -euo pipefail
room="$1"
file="$2"
: "${AGENTTEAMS_MATRIX_URL:?AGENTTEAMS_MATRIX_URL is required}"
: "${AGENTTEAMS_ADMIN_USER:?AGENTTEAMS_ADMIN_USER is required}"
: "${AGENTTEAMS_ADMIN_PASSWORD:?AGENTTEAMS_ADMIN_PASSWORD is required}"

token=""
cleanup() {
  if [[ -n "${token}" ]]; then
    curl -sS -X POST -H "Authorization: Bearer ${token}" "${AGENTTEAMS_MATRIX_URL}/_matrix/client/v3/logout" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

login_payload="$(jq -cn --arg user "${AGENTTEAMS_ADMIN_USER}" --arg password "${AGENTTEAMS_ADMIN_PASSWORD}" '{type:"m.login.password",identifier:{type:"m.id.user",user:$user},password:$password,initial_device_display_name:"juchang-crisis-dispatch"}')"
token="$(curl -fsS -X POST -H 'Content-Type: application/json' -d "${login_payload}" "${AGENTTEAMS_MATRIX_URL}/_matrix/client/v3/login" | jq -er '.access_token')"
room_uri="$(jq -rn --arg value "${room}" '$value|@uri')"
message="$(cat "${file}")"
payload="$(jq -cn --arg body "${message}" '{msgtype:"m.text",body:$body}')"
curl -fsS -X PUT -H "Authorization: Bearer ${token}" -H 'Content-Type: application/json' -d "${payload}" \
  "${AGENTTEAMS_MATRIX_URL}/_matrix/client/v3/rooms/${room_uri}/send/m.room.message/$(date +%s%N)" >/dev/null
echo "DISPATCH_MESSAGE_SENT room=${room} bytes=${#message}"
