#!/usr/bin/env bash
# goai-crisis-cloud-bridge · Tuwunel admin 密码应急恢复 v3.3（SIGHUP 全量重载法）
# 本环境 supervisord 无控制 socket；SIGHUP = supervisord 官方「停全部进程+重读配置+拉起」语义。
# 影响：容器内全部进程（Tuwunel/Higress/MinIO/controller 等）重启一次，约 30-60 秒；Worker/Manager 容器不受影响（跨容器重连）。
set -uo pipefail
C=agentteams-controller
DOMAIN='matrix-local.agentteams.io:18080'
MATRIX_URL='http://127.0.0.1:6167'
FRAG='/etc/supervisor/conf.d/supervisord.conf'
EMERGENCY="$(head -c 24 /dev/urandom | od -An -tx1 | tr -d ' \n')"

echo "=== [1/9] 注入应急密码到 [program:tuwunel] ==="
docker exec $C sh -c "sed -i '/CONDUWUIT_EMERGENCY_PASSWORD/d' '$FRAG' && sed -i '/\[program:tuwunel\]/a environment=CONDUWUIT_EMERGENCY_PASSWORD=\"$EMERGENCY\"' '$FRAG'"
docker exec $C sh -c "grep -A 2 'program:tuwunel' '$FRAG' | sed -E 's/(EMERGENCY_PASSWORD=).*/\1<set>/'"

echo "=== [2/9] SIGHUP supervisord（全量重载，约 30-60 秒） ==="
docker exec $C sh -c 'kill -HUP $(pgrep -f supervisord | head -1) && echo SIGHUP_SENT'
sleep 30
echo "--- 等待基础设施回来（最多 90 秒） ---"
i=0
until docker exec $C sh -c 'curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:6167/_matrix/client/versions' 2>/dev/null | grep -q 200; do
  i=$((i+1)); [ $i -gt 18 ] && { echo "FAIL: Tuwunel 90 秒未恢复，截图发回"; exit 1; }
  sleep 5
done
echo "tuwunel-up=200"

echo "=== [3/9] 验证应急变量已进入新进程环境 ==="
INJECTED=$(docker exec $C sh -c 'PID=$(pgrep -x tuwunel | head -1); [ -n "$PID" ] && tr "\0" "\n" < /proc/$PID/environ | grep -c "^CONDUWUIT_EMERGENCY_PASSWORD=" || echo 0')
echo "injected_env_present=$INJECTED"
if [ "$INJECTED" != "1" ]; then
  echo "FAIL: 应急变量未生效。回滚（去行+再 SIGHUP）..."
  docker exec $C sh -c "sed -i '/CONDUWUIT_EMERGENCY_PASSWORD/d' '$FRAG' && kill -HUP \$(pgrep -f supervisord | head -1)"
  exit 1
fi

echo "=== [4/9] 服务器机器人应急登录 ==="
BOT_TOKEN=""
for BOT in conduit tuwunel; do
  BOT_TOKEN=$(docker exec $C sh -c "jq -cn --arg u '@$BOT:$DOMAIN' --arg p '$EMERGENCY' '{type:\"m.login.password\",identifier:{type:\"m.id.user\",user:\$u},password:\$p}' | curl -s -X POST -H 'Content-Type: application/json' -d @- $MATRIX_URL/_matrix/client/v3/login" | jq -r '.access_token // empty')
  [ -n "$BOT_TOKEN" ] && { echo "BOT_LOGIN_OK (@$BOT)"; break; }
done
if [ -z "$BOT_TOKEN" ]; then
  echo "FAIL: 机器人登录失败。回滚中..."
  docker exec $C sh -c "sed -i '/CONDUWUIT_EMERGENCY_PASSWORD/d' '$FRAG' && kill -HUP \$(pgrep -f supervisord | head -1)"
  exit 1
fi

echo "=== [5/9] 在 #admins 房间重置 admin 密码为 controller env 当前值 ==="
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

echo "=== [6/9] 撤除应急配置并再次 SIGHUP ==="
docker exec $C sh -c "sed -i '/CONDUWUIT_EMERGENCY_PASSWORD/d' '$FRAG' && kill -HUP \$(pgrep -f supervisord | head -1) && echo SIGHUP_SENT"
sleep 30
i=0
until docker exec $C sh -c 'curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:6167/_matrix/client/versions' 2>/dev/null | grep -q 200; do
  i=$((i+1)); [ $i -gt 18 ] && { echo "WARN: 第二次重载后 Tuwunel 未在 90 秒内恢复，人工查看"; break; }
  sleep 5
done

echo "=== [7/9] 验证：admin 用 controller env 密码可登录 ==="
CODE=$(docker exec $C sh -c 'P=$(jq -cn --arg u admin --arg p "$AGENTTEAMS_ADMIN_PASSWORD" "{type:\"m.login.password\",identifier:{type:\"m.id.user\",user:\$u},password:\$p}"); curl -s -o /dev/null -w "%{http_code}" -X POST -H "Content-Type: application/json" -d "$P" "http://127.0.0.1:6167/_matrix/client/v3/login"')
echo "admin login => $CODE（200=恢复成功）"

echo "=== [8/9] 清理机器人会话 ==="
docker exec -e BOT_TOKEN="$BOT_TOKEN" $C sh -c 'curl -s -X POST -H "Authorization: Bearer $BOT_TOKEN" "http://127.0.0.1:6167/_matrix/client/v3/logout" >/dev/null 2>&1 || true'

echo "=== [9/9] 复查 Team 状态 ==="
docker exec $C agt get teams juchang-change-control-v14 2>&1 | grep -E 'Phase|Message|LeaderReady|ReadyWorkers' || echo "(controller 可能仍在启动，1 分钟后再查)"
echo "=== FIX_ADMIN_V33_DONE ==="
