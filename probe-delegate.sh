#!/usr/bin/env bash
# goai-crisis-cloud-bridge · p4 委派通知到底出没出（只读）
set -uo pipefail
C=agentteams-controller
LEAD=agentteams-worker-juchang-v14-lead
echo "=== [1/2] Leader 日志里 p4 的委派痕迹（带时间戳） ==="
docker logs $LEAD -t --since 90m 2>&1 | grep -E 'p4|delegate|readyNodes|assign' | tail -15 | sed -E 's/(token|password|key)[":= ]+[A-Za-z0-9._-]+/\1=<redacted>/gi'
echo "=== [2/2] 团队房间 + LeaderDM 里含 p4 的消息 ==="
docker exec $C sh -c '
T=$(curl -s -X POST -H "Content-Type: application/json" -d "{\"type\":\"m.login.password\",\"identifier\":{\"type\":\"m.id.user\",\"user\":\"admin\"},\"password\":\"$AGENTTEAMS_ADMIN_PASSWORD\"}" "http://127.0.0.1:6167/_matrix/client/v3/login" | sed -E "s/.*\"access_token\":\"([^\"]+)\".*/\1/")
for ROOM_ENC in "%21S7Rk2N6pPUGg08VdXo%3Amatrix-local.agentteams.io%3A18080" "%21GKL4XFzVKBFE6bqGad%3Amatrix-local.agentteams.io%3A18080"; do
  echo "--- room $ROOM_ENC ---"
  curl -s -H "Authorization: Bearer $T" "http://127.0.0.1:6167/_matrix/client/v3/rooms/$ROOM_ENC/messages?limit=40&dir=b" | jq -r ".chunk[]? | select(.type==\"m.room.message\") | select(.content.body|tostring|test(\"p4\")) | (.sender|split(\":\")[0]) + \" \" + (.origin_server_ts|tostring) + \" \" + (.content.body|tostring|.[0:100]|gsub(\"\\n\";\" \"))" 2>/dev/null | head -8
done
curl -s -X POST -H "Authorization: Bearer $T" "http://127.0.0.1:6167/_matrix/client/v3/logout" >/dev/null 2>&1
'
echo "=== PROBE_DELEGATE_DONE ==="
echo "判读：[2/2] 有 Leader 发的含 p4-01 的 JUCHANG_DSH_TASK 消息 = 通知已送达，问题在 Worker 消费侧；没有 = Leader 委派层没发出，问题在 Leader/TeamHarness。"
