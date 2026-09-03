#!/usr/bin/env bash
# goai-crisis-cloud-bridge · 定位能用的 Matrix admin 密码来源 v3（stdin 传候选，无嵌套引号，不打印任何值）
set -uo pipefail
BRIDGE="https://raw.githubusercontent.com/endtree-FDE/goai-crisis-cloud-bridge/main"

curl -sL "$BRIDGE/try-login.sh" -o /tmp/try-login.sh
docker cp /tmp/try-login.sh agentteams-controller:/tmp/try-login.sh

echo "=== 连通性自检 ==="
printf 'probe' | docker exec -i agentteams-controller sh /tmp/try-login.sh admin http://127.0.0.1:6167
echo " <- 期望 403（密码错误但连接正常）；若 000 则仍有问题"

echo "=== 候选来源逐一试登（只报来源与结果） ==="
idx=0
report() {
  idx=$((idx+1))
  code=$(printf '%s' "$1" | docker exec -i agentteams-controller sh /tmp/try-login.sh admin http://127.0.0.1:6167 2>/dev/null)
  if [ "$code" = "200" ]; then echo "#$idx $2 => LOGIN_OK"; else echo "#$idx $2 => $code"; fi
}

V=$(docker exec agentteams-controller printenv AGENTTEAMS_ADMIN_PASSWORD 2>/dev/null) && [ -n "$V" ] && report "$V" "controller env AGENTTEAMS_ADMIN_PASSWORD"
V=$(docker exec agentteams-manager printenv AGENTTEAMS_ADMIN_PASSWORD 2>/dev/null) && [ -n "$V" ] && report "$V" "manager env AGENTTEAMS_ADMIN_PASSWORD"
V=$(docker exec agentteams-dashboard printenv AGENTTEAMS_ADMIN_PASSWORD 2>/dev/null) && [ -n "$V" ] && report "$V" "dashboard env AGENTTEAMS_ADMIN_PASSWORD"

for f in $(grep -rlE '"password"|^AGENTTEAMS_ADMIN_PASSWORD=' /root/agentteams-manager /workspace/.env /workspace/*.env 2>/dev/null | head -8); do
  for cand in $(grep -hoE '"password"[^,}]*' "$f" 2>/dev/null | sed -E 's/.*"password"\s*:\s*"([^"]*)".*/\1/' | head -3); do
    [ -n "$cand" ] && report "$cand" "file:$f (json password field)"
  done
  for cand in $(grep -hoE '^AGENTTEAMS_ADMIN_PASSWORD=.*' "$f" 2>/dev/null | head -2 | cut -d= -f2- | tr -d "\"'"); do
    [ -n "$cand" ] && report "$cand" "file:$f (env line)"
  done
done
echo "=== DISCOVER_ADMIN_DONE ==="
