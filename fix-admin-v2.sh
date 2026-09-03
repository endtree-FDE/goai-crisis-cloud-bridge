#!/usr/bin/env bash
# goai-crisis-cloud-bridge · Tuwunel admin 密码应急恢复（路线B）
# 原理：Tuwunel/conduwuit 支持 emergency_password——设置后可用服务器机器人账号（@conduit）登录并获得服务端管理权，
#       再用 !admin users reset-password 把 @admin 的密码重置为 controller env 里的当前值，使环境变量与服务器一致。
# 安全：应急密码为脚本内随机值，用完即撤；全程不打印任何密码/token；Matrix 中断约 10-30 秒（tuwunel 重启两次）。
set -uo pipefail
C=agentteams-controller
DOMAIN='matrix-local.agentteams.io:18080'
ADMIN_USER='admin'
MATRIX_URL='http://127.0.0.1:6167'
EMERGENCY="$(head -c 24 /dev/urandom | od -An -tx1 | tr -d ' \n')"

echo "=== [1/8] 定位 Tuwunel 配置与 supervisor 编排 ==="
docker exec $C sh -c 'ps aux | grep -iE "tuwunel|conduit" | grep -v grep | head -3'
TOML=$(docker exec $C sh -c 'find /etc /opt /usr/local /root /data -maxdepth 4 -name "*.toml" 2>/dev/null | xargs grep -l "server_name\|database" 2>/dev/null | head -1')
echo "TOML=$TOML"
if [ -z "$TOML" ]; then echo "FAIL: 找不到 Tuwunel 配置文件，截图发回"; exit 1; fi

echo "=== [2/8] 写入应急密码配置（emergency_password） ==="
docker exec $C sh -c "printf '\nemergency_password = \"%s\"\n' '$EMERGENCY' >> '$TOML'"
docker exec $C sh -c "tail -3 '$TOML' | sed 's/=.*/= <redacted>/'"

echo "=== [3/8] 重启 Tuwunel（supervisor 内） ==="
docker exec $C sh -c 'supervisorctl restart tuwunel 2>/dev/null || supervisorctl -c /etc/supervisord.conf restart tuwunel 2>/dev/null || (command -v supervisorctl || echo NO_SUPERVISORCTL)'
sleep 12
docker exec $C sh -c 'curl -s -o /dev/null -w "tuwunel-up=%{http_code}\n" http://127.0.0.1:6167/_matrix/client/versions'

echo "=== [4/8] 用应急密码登录服务器机器人 ==="
BOT_LOGIN=$(docker exec $C sh -c "jq -cn --arg u '@conduit:$DOMAIN' --arg p '$EMERGENCY' '{type:\"m.login.password\",identifier:{type:\"m.id.user\",user:\$u},password:\$p}' | curl -s -X POST -H 'Content-Type: application/json' -d @- $MATRIX_URL/_matrix/client/v3/login")
echo "$BOT_LOGIN" | jq -r 'if .access_token then "BOT_LOGIN_OK" else "BOT_LOGIN_FAIL: " + (.errcode // "unknown") end' 2>/dev/null || echo "BOT_LOGIN_FAIL(raw)"
BOT_TOKEN=$(echo "$BOT_LOGIN" | jq -r '.access_token // empty' 2>/dev/null)
if [ -z "$BOT_TOKEN" ]; then
  echo "FAIL: 应急密码登录失败（可能该构建无 emergency_password 支持或机器人名不是 conduit）"
  echo "回滚配置并重启："
  docker exec $C sh -c "sed -i '/^emergency_password = /d' '$TOML'"
  docker exec $C sh -c 'supervisorctl restart tuwunel 2>/dev/null || supervisorctl -c /etc/supervisord.conf restart tuwunel'
  exit 1
fi

echo "=== [5/8] 解析 #admins 房间并发送 reset-password ==="
NEW_PW=$(docker exec $C printenv AGENTTEAMS_ADMIN_PASSWORD)
if [ -z "$NEW_PW" ]; then echo "FAIL: controller env 没有 AGENTTEAMS_ADMIN_PASSWORD"; exit 1; fi
docker exec -e BOT_TOKEN="$BOT_TOKEN" -e NEW_PW="$NEW_PW" $C sh -c '
  DOMAIN="'"$DOMAIN"'"; MATRIX_URL="'"$MATRIX_URL"'"
  ROOM=$(curl -s -H "Authorization: Bearer $BOT_TOKEN" "$MATRIX_URL/_matrix/client/v3/directory/room/%23admins%3A$DOMAIN" | jq -r ".room_id // empty")
  echo "admin_room=${ROOM:-NOT_FOUND}"
  [ -z "$ROOM" ] && exit 1
  CMD="!admin users reset-password @admin:$DOMAIN $NEW_PW"
  PAYLOAD=$(jq -cn --arg b "$CMD" "{msgtype:\"m.text\",body:\$b}")
  ROOM_ENC=$(jq -rn --arg r "$ROOM" "\$r|@uri")
  curl -s -X PUT -H "Authorization: Bearer $BOT_TOKEN" -H "Content-Type: application/json" -d "$PAYLOAD" "$MATRIX_URL/_matrix/client/v3/rooms/$ROOM_ENC/send/m.room.message/$(date +%s%N)" | jq -r "if .event_id then \"RESET_CMD_SENT\" else \"SEND_FAIL\" end"
  sleep 3
'
echo "=== [6/8] 验证 admin 新密码可登录 ==="
CODE=$(printf '%s' "$NEW_PW" | docker exec -i $C sh -c 'read -r PW; P=$(jq -cn --arg u admin --arg p "$PW" "{type:\"m.login.password\",identifier:{type:\"m.id.user\",user:\$u},password:\$p}"); curl -s -o /dev/null -w "%{http_code}" -X POST -H "Content-Type: application/json" -d "$P" "http://127.0.0.1:6167/_matrix/client/v3/login"')
echo "admin login => $CODE（200=恢复成功）"

echo "=== [7/8] 撤除应急配置并重启 Tuwunel ==="
docker exec $C sh -c "sed -i '/^emergency_password = /d' '$TOML'"
docker exec $C sh -c 'supervisorctl restart tuwunel 2>/dev/null || supervisorctl -c /etc/supervisord.conf restart tuwunel'
sleep 10

echo "=== [8/8] 复查 Team 状态 ==="
docker exec $C agt get teams juchang-change-control-v14 2>&1 | grep -E 'Phase|Message|LeaderReady|ReadyWorkers' || true
echo "=== FIX_ADMIN_V2_DONE ==="
echo "注意：Team Phase=Failed 可能需要一次 reconcile 才清（重启 controller 或等它重试）。admin 登录恢复是本次目标。"
