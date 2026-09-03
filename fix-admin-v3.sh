#!/usr/bin/env bash
# goai-crisis-cloud-bridge · Tuwunel admin 密码应急恢复 v3.1（自动定位 supervisord 主配置 + 注入验证）
set -uo pipefail
C=agentteams-controller
DOMAIN='matrix-local.agentteams.io:18080'
MATRIX_URL='http://127.0.0.1:6167'
FRAG='/etc/supervisor/conf.d/supervisord.conf'
EMERGENCY="$(head -c 24 /dev/urandom | od -An -tx1 | tr -d ' \n')"

echo "=== [1/9] 定位 supervisord 主配置 ==="
SUPMAIN=$(docker exec $C sh -c 'ps aux | grep -v grep | grep supervisord | head -1 | grep -oE "\-c [^ ]+" | cut -d" " -f2')
[ -z "$SUPMAIN" ] && SUPMAIN=$(docker exec $C sh -c 'for f in /etc/supervisord.conf /etc/supervisor/supervisord.conf /opt/agentteams/supervisord.conf; do [ -f "$f" ] && echo "$f" && break; done')
echo "SUPMAIN=${SUPMAIN:-NOT_FOUND}"
[ -z "$SUPMAIN" ] && { echo "FAIL: 找不到 supervisord 主配置，截图发回"; exit 1; }
docker exec $C sh -c "grep -c 'supervisorctl' '$SUPMAIN'"

echo "=== [2/9] 注入应急密码到 [program:tuwunel]（片段文件） ==="
docker exec $C sh -c "sed -i '/CONDUWUIT_EMERGENCY_PASSWORD/d' '$FRAG' && sed -i '/\[program:tuwunel\]/a environment=CONDUWUIT_EMERGENCY_PASSWORD=\"$EMERGENCY\"' '$FRAG'"
docker exec $C sh -c "grep -A 2 'program:tuwunel' '$FRAG' | sed -E 's/(EMERGENCY_PASSWORD=).*/\1<set>/'"

echo "=== [3/9] reread + update + 重启 Tuwunel ==="
docker exec $C sh -c "supervisorctl -c '$SUPMAIN' reread && supervisorctl -c '$SUPMAIN' update && supervisorctl -c '$SUPMAIN' restart tuwunel" 2>&1 | head -5
sleep 14
docker exec $C sh -c 'curl -s -o /dev/null -w "tuwunel-up=%{http_code}\n" http://127.0.0.1:6167/_matrix/client/versions'

echo "=== [4/9] 验证应急变量已进入新进程环境 ==="
INJECTED=$(docker exec $C sh -c 'PID=$(pgrep -x tuwunel | head -1); [ -n "$PID" ] && tr "\0" "\n" < /proc/$PID/environ | grep -c "^CONDUWUIT_EMERGENCY_PASSWORD=" || echo 0')
echo "injected_env_present=$INJECTED"
if [ "$INJECTED" != "1" ]; then
  echo "FAIL: 应急变量未进入 tuwunel 进程（supervisor 的 environment 语法可能需要追加到既有 environment 行）。回滚中..."
  docker exec $C sh -c "sed -i '/CONDUWUIT_EMERGENCY_PASSWORD/d' '$FRAG' && supervisorctl -c '$SUPMAIN' reread && supervisorctl -c '$SUPMAIN' update && supervisorctl -c '$SUPMAIN' restart tuwunel"
  exit 1
fi

echo "=== [5/9] 服务器机器人应急登录 ==="
BOT_TOKEN=""
for BOT in conduit tuwunel; do
  BOT_TOKEN=$(docker exec $C sh -c "jq -cn --arg u '@$BOT:$DOMAIN' --arg p '$EMERGENCY' '{type:\"m.login.password\",identifier:{type:\"m.id.user\",user:\$u},password:\$p}' | curl -s -X POST -H 'Content-Type: application/json' -d @- $MATRIX_URL/_matrix/client/v3/login" | jq -r '.access_token // empty')
  [ -n "$BOT_TOKEN" ] && { echo "BOT_LOGIN_OK (@$BOT)"; break; }
done
if [ -z "$BOT_TOKEN" ]; then
  echo "FAIL: 机器人登录失败。回滚中..."
  docker exec $C sh -c "sed -i '/CONDUWUIT_EMERGENCY_PASSWORD/d' '$FRAG' && supervisorctl -c '$SUPMAIN' reread && supervisorctl -c '$SUPMAIN' update && supervisorctl -c '$SUPMAIN' restart tuwunel"
  exit 1
fi

echo "=== [6/9] 在 #admins 房间重置 admin 密码为 controller env 当前值 ==="
docker exec -e BOT_TOKEN="$BOT_TOKEN" $C sh -c '
  DOMAIN="'"$DOMAIN"'"; MATRIX_URL="'"$MATRIX_URL"'"
  NEW_PW=$(printenv AGENTTEAMS_ADMIN_PASSWORD)
  [ -z "$NEW_PW" ] && { echo "FAIL: controller env 无 AGENTTEAMS_ADMIN_PASSWORD"; exit 1; }
  ROOM=$(curl -s -H "Authorization: Bearer $BOT_TOKEN" "$MATRIX_URL/_matrix/client/v3/directory/room/%23admins%3A$DOMAIN" | jq -r ".room_id // empty")
  echo "admin_room=${ROOM:-NOT_FOUND}"
  [ -z "$ROOM" ] && exit 1
  CMD="!admin users reset-password @admin:$DOMAIN $NEW_PW"
  PAYLOAD=$(jq -cn --arg b "$CMD" "{msgtype:\"m.text\",body:\$b}")
  ROOM_ENC=$(jq -rn --arg r "$ROOM" "\$r|@uri")
  curl -s -X PUT -H "Authorization: Bearer $BOT_TOKEN" -H "Content-Type: application/json" -d "$PAYLOAD" "$MATRIX_URL/_matrix/client/v3/rooms/$ROOM_ENC/send/m.room.message/$(date +%s%N)" | jq -r "if .event_id then \"RESET_CMD_SENT\" else \"SEND_FAIL\" end"
  sleep 4
'

echo "=== [7/9] 撤除应急配置并重启 Tuwunel ==="
docker exec $C sh -c "sed -i '/CONDUWUIT_EMERGENCY_PASSWORD/d' '$FRAG' && supervisorctl -c '$SUPMAIN' reread && supervisorctl -c '$SUPMAIN' update && supervisorctl -c '$SUPMAIN' restart tuwunel" 2>&1 | head -3
sleep 12

echo "=== [8/9] 验证：admin 用 controller env 密码可登录 ==="
CODE=$(docker exec $C sh -c 'P=$(jq -cn --arg u admin --arg p "$AGENTTEAMS_ADMIN_PASSWORD" "{type:\"m.login.password\",identifier:{type:\"m.id.user\",user:\$u},password:\$p}"); curl -s -o /dev/null -w "%{http_code}" -X POST -H "Content-Type: application/json" -d "$P" "http://127.0.0.1:6167/_matrix/client/v3/login"')
echo "admin login => $CODE（200=恢复成功）"

echo "=== [9/9] 清理机器人会话 + 复查 Team ==="
docker exec -e BOT_TOKEN="$BOT_TOKEN" $C sh -c 'curl -s -X POST -H "Authorization: Bearer $BOT_TOKEN" "http://127.0.0.1:6167/_matrix/client/v3/logout" >/dev/null 2>&1 || true'
docker exec $C agt get teams juchang-change-control-v14 2>&1 | grep -E 'Phase|Message|LeaderReady|ReadyWorkers' || true
echo "=== FIX_ADMIN_V31_DONE ==="
