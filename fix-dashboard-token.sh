#!/usr/bin/env bash
# goai-crisis-cloud-bridge · 修复 dashboard 的 M_UNKNOWN_TOKEN：铸新 admin token 并替换 dashboard 存储的旧 token
# 全程不打印任何 token 值（只显示定位路径与成败）。
set -uo pipefail
C=agentteams-controller
D=agentteams-dashboard
MATRIX_URL='http://127.0.0.1:6167'

echo "=== [1/5] 铸新 admin Matrix token（控制器内，不显示） ==="
TOKEN=$(docker exec $C sh -c 'P=$(jq -cn --arg u admin --arg p "$AGENTTEAMS_ADMIN_PASSWORD" "{type:\"m.login.password\",identifier:{type:\"m.id.user\",user:\$u},password:\$p}"); curl -s -X POST -H "Content-Type: application/json" -d "$P" "http://127.0.0.1:6167/_matrix/client/v3/login" | jq -r ".access_token // empty"')
[ -z "$TOKEN" ] && { echo "FAIL: admin 登录失败（fix-admin-v33 未跑通？）"; exit 1; }
echo "NEW_TOKEN_MINTED (length=${#TOKEN})"

echo "=== [2/5] 定位 dashboard 存储的旧 token ==="
HITS=$(docker exec $D sh -c 'grep -rl "syt_" /data /app /config /srv /var 2>/dev/null | grep -v node_modules | head -5')
echo "$HITS"
[ -z "$HITS" ] && { echo "FAIL: dashboard 容器内没找到 syt_ token 存储；截图发回，改查 controller 数据卷"; exit 1; }

echo "=== [3/5] 替换为新 token ==="
for f in $HITS; do
  docker exec -e NEWTOKEN="$TOKEN" $D sh -c "cp '$f' '$f.bak-agentteams' && sed -E -i \"s/syt_[A-Za-z0-9_\\-]+/$(printf '%s' "\$NEWTOKEN")/g\" '$f' && echo patched:$f"
done

echo "=== [4/5] 重启 dashboard ==="
docker restart $D
sleep 12

echo "=== [5/5] 验证：新 token 直接读团队房间消息 ==="
docker exec -e T="$TOKEN" $C sh -c 'curl -s -H "Authorization: Bearer $T" "http://127.0.0.1:6167/_matrix/client/v3/rooms/!S7Rk2N6pPUGg08VdXo:matrix-local.agentteams.io:18080/messages?limit=1&dir=b" | jq -r "if .chunk then \"TOKEN_READ_OK messages=\" + (.chunk|length|tostring) else \"TOKEN_READ_FAIL: \" + (.errcode // \"?\") end"'
echo "=== FIX_DASHBOARD_TOKEN_DONE ==="
echo "回到 dashboard 页面刷新，Matrix 聊天应能加载。不行就把本输出截图发我。"
