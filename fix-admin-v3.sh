#!/usr/bin/env bash
# goai-crisis-cloud-bridge · Tuwunel admin 密码应急恢复 v3（supervisord environment 注入法）
# 步骤：注入 CONDUWUIT_EMERGENCY_PASSWORD → 重启 tuwunel → @conduit 机器人登录 → #admins 房间重置 @admin 密码
#       为 controller env 的当前值 → 验证 → 撤除应急配置 → 再重启 → 复查。
# 安全：应急密码为脚本内随机值、用完即撤；不打印任何密码/token；Matrix 中断约 20-40 秒。
set -uo pipefail
C=agentteams-controller
DOMAIN='matrix-local.agentteams.io:18080'
MATRIX_URL='http://127.0.0.1:6167'
CONF='/etc/supervisor/conf.d/supervisord.conf'
EMERGENCY="$(head -c 24 /dev/urandom | od -An -tx1 | tr -d ' \n')"

echo "=== [1/8] 注入应急密码到 [program:tuwunel] ==="
docker exec $C sh -c "grep -n 'program:tuwunel' '$CONF' && grep -c 'CONDUWUIT_EMERGENCY_PASSWORD' '$CONF' || true"
# 幂等：先清旧行再插入（在 [program:tuwunel] 的 command 行之后）
docker exec $C sh -c "sed -i '/CONDUWUIT_EMERGENCY_PASSWORD/d' '$CONF' && sed -i '/\[program:tuwunel\]/a environment=CONDUWUIT_EMERGENCY_PASSWORD=\"$EMERGENCY\"' '$CONF'"
docker exec $C sh -c "grep -A 2 'program:tuwunel' '$CONF' | sed -E 's/(EMERGENCY_PASSWORD=).*/\1<set>/'"

echo "=== [2/8] supervisor 重读并重启 Tuwunel ==="
docker exec $C sh -c "supervisorctl -c '$CONF' reread && supervisorctl -c '$CONF' update && supervisorctl -c '$CONF' restart tuwunel" 2>&1 | head -5
sleep 14
docker exec $C sh -c 'curl -s -o /dev/null -w "tuwunel-up=%{http_code}\n" http://127.0.0.1:6167/_matrix/client/versions'

echo "=== [3/8] 服务器机器人应急登录 ==="
BOT_TOKEN=$(docker exec $C sh -c "jq -cn --arg u '@conduit:$DOMAIN' --arg p '$EMERGENCY' '{type:\"m.login.password\",identifier:{type:\"m.id.user\",user:\$u},password:\$p}' | curl -s -X POST -H 'Content-Type: application/json' -d @- $MATRIX_URL/_matrix/client/v3/login" | jq -r '.access_token // empty')
if [ -z "$BOT_TOKEN" ]; then
  echo "BOT_LOGIN_FAIL — 该构建可能用别的机器人名。尝试 @tuwunel："
  BOT_TOKEN=$(docker exec $C sh -c "jq -cn --arg u '@tuwunel:$DOMAIN' --arg p '$EMERGENCY' '{type:\"m.login.password\",identifier:{type:\"m.id.user\",user:\$u},password:\$p}' | curl -s -X POST -H 'Content-Type: application/json' -d @- $MATRIX_URL/_matrix/client/v3/login" | jq -r '.access_token // empty')
fi
if [ -z "$BOT_TOKEN" ]; then
  echo "FAIL: 两种机器人名都登录失败。回滚中..."
  docker exec $C sh -c "sed -i '/CONDUWUIT_EMERGENCY_PASSWORD/d' '$CONF' && supervisorctl -c '$CONF' reread && supervisorctl -c '$CONF' update && supervisorctl -c '$CONF' restart tuwunel"
  exit 1
fi
echo "BOT_LOGIN_OK"

echo "=== [4/8] 在 #admins 房间重置 admin 密码为 controller env 当前值 ==="
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

echo "=== [5/8] 撤除应急配置并重启 Tuwunel ==="
docker exec $C sh -c "sed -i '/CONDUWUIT_EMERGENCY_PASSWORD/d' '$CONF' && supervisorctl -c '$CONF' reread && supervisorctl -c '$CONF' update && supervisorctl -c '$CONF' restart tuwunel" 2>&1 | head -3
sleep 12

echo "=== [6/8] 验证：admin 用 controller env 密码可登录 ==="
CODE=$(docker exec $C sh -c 'P=$(jq -cn --arg u admin --arg p "$AGENTTEAMS_ADMIN_PASSWORD" "{type:\"m.login.password\",identifier:{type:\"m.id.user\",user:\$u},password:\$p}"); curl -s -o /dev/null -w "%{http_code}" -X POST -H "Content-Type: application/json" -d "$P" "http://127.0.0.1:6167/_matrix/client/v3/login"')
echo "admin login => $CODE（200=恢复成功）"

echo "=== [7/8] 复查 Team 状态 ==="
docker exec $C agt get teams juchang-change-control-v14 2>&1 | grep -E 'Phase|Message|LeaderReady|ReadyWorkers' || true

echo "=== [8/8] 清理机器人会话 ==="
docker exec -e BOT_TOKEN="$BOT_TOKEN" $C sh -c 'curl -s -X POST -H "Authorization: Bearer $BOT_TOKEN" "http://127.0.0.1:6167/_matrix/client/v3/logout" >/dev/null 2>&1 || true'
echo "=== FIX_ADMIN_V3_DONE ==="
echo "判读：admin login => 200 即恢复成功，可跑 dispatch.sh；Team Phase 若仍 Failed，等 1-2 分钟 reconcile 或重启 controller。"
