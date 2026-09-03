#!/usr/bin/env bash
# goai-crisis-cloud-bridge · 一键房间校验（自动定位 verify-room-target.sh）
# 用法：bash verify-room.sh '!真实房间ID'
set -uo pipefail
ROOM_ID="${1:-}"
if [ -z "$ROOM_ID" ] || [ "${ROOM_ID#\!}" = "$ROOM_ID" ]; then
  echo "Usage: bash verify-room.sh '!xxxx:matrix-local.agentteams.io:18080'"
  echo "Get the real room_id from Element room settings (must start with !)"
  exit 1
fi
VERIFY=$(find /workspace /root /home -name 'verify-room-target.sh' -type f 2>/dev/null | head -1)
if [ -z "$VERIFY" ]; then
  echo "ERROR: verify-room-target.sh not found"
  exit 1
fi
echo "VERIFY=$VERIFY"
cd "$(dirname "$VERIFY")" || exit 1
bash verify-room-target.sh "$ROOM_ID"
