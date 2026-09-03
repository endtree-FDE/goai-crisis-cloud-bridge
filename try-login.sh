#!/bin/sh
# 容器内登录探针：从 stdin 读密码（不进 argv、不落盘），只输出 HTTP 状态码
# 用法：printf '%s' '<密码>' | docker exec -i agentteams-controller sh /tmp/try-login.sh <user> <matrix_url>
USER="$1"
URL="$2"
read -r PW
payload=$(jq -cn --arg user "$USER" --arg password "$PW" '{"type":"m.login.password","identifier":{"type":"m.id.user","user":$user},"password":$password}')
curl -s -o /dev/null -w '%{http_code}' -X POST -H 'Content-Type: application/json' -d "$payload" "$URL/_matrix/client/v3/login"
