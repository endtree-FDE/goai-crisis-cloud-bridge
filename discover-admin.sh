#!/usr/bin/env bash
# goai-crisis-cloud-bridge · 定位能用的 Matrix admin 密码来源（绝不打印任何候选值；只报告来源与是否可登录）
set -uo pipefail
MATRIX_URL="http://127.0.0.1:6167"
ADMIN_USER="admin"

try_login() { # $1=candidate password (never echoed)
  docker exec agentteams-controller sh -c '
    payload=$(printf "{\"type\":\"m.login.password\",\"identifier\":{\"type\":\"m.id.user\",\"user\":\"%s\"},\"password\":\"%s\"}" "$1" "$2")
    code=$(curl -s -o /dev/null -w "%{http_code}" -X POST -H "Content-Type: application/json" -d "$payload" "$3/_matrix/client/v3/login")
    printf "%s" "$code"
  ' sh "$1" "$MATRIX_URL" 2>/dev/null
}

echo "=== 候选来源逐一试登（只报来源与结果） ==="
idx=0
report() { idx=$((idx+1)); code=$(try_login "$1"); if [ "$code" = "200" ]; then echo "#$idx $2 => LOGIN_OK"; else echo "#$idx $2 => $code"; fi; }

V=$(docker exec agentteams-controller printenv AGENTTEAMS_ADMIN_PASSWORD 2>/dev/null) && [ -n "$V" ] && report "$V" "controller env AGENTTEAMS_ADMIN_PASSWORD"
V=$(docker exec agentteams-manager printenv AGENTTEAMS_ADMIN_PASSWORD 2>/dev/null) && [ -n "$V" ] && report "$V" "manager env AGENTTEAMS_ADMIN_PASSWORD"
V=$(docker exec agentteams-dashboard printenv AGENTTEAMS_ADMIN_PASSWORD 2>/dev/null) && [ -n "$V" ] && report "$V" "dashboard env AGENTTEAMS_ADMIN_PASSWORD"

# 配置文件里的 password 字段（manager fs、workspace env 文件）
for f in $(grep -rlE '"password"|^AGENTTEAMS_ADMIN_PASSWORD=' /root/agentteams-manager /workspace/.env /workspace/*.env 2>/dev/null | head -8); do
  for cand in $(grep -hoE '"password"[^,}]*' "$f" 2>/dev/null | sed -E 's/.*"password"\s*:\s*"([^"]*)".*/\1/' | head -3); do
    [ -n "$cand" ] && report "$cand" "file:$f (json password field)"
  done
  for cand in $(grep -hoE '^AGENTTEAMS_ADMIN_PASSWORD=.*' "$f" 2>/dev/null | head -2 | cut -d= -f2- | tr -d "\"'"); do
    [ -n "$cand" ] && report "$cand" "file:$f (env line)"
  done
done
echo "=== DISCOVER_ADMIN_DONE ==="
echo "说明：出现 LOGIN_OK 的来源 = 可用密码来源；dispatch 会改从该来源取密码（全程不显示值）。"
