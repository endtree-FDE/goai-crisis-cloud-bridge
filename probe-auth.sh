#!/usr/bin/env bash
# goai-crisis-cloud-bridge · Matrix 管理员凭据失配诊断（只读；绝不打印密码/token 值）
set -uo pipefail
echo "=== [1/7] controller 的 Matrix 连接参数（用户名/URL 非密） ==="
docker exec agentteams-controller printenv AGENTTEAMS_ADMIN_USER 2>/dev/null
docker exec agentteams-controller printenv AGENTTEAMS_MATRIX_URL 2>/dev/null
docker exec agentteams-controller printenv AGENTTEAMS_MATRIX_DOMAIN 2>/dev/null

echo "=== [2/7] 实际模型路由（模型 ID 非密） ==="
docker exec agentteams-controller printenv AGENTTEAMS_DEFAULT_MODEL 2>/dev/null
docker exec agentteams-manager printenv AGENTTEAMS_DEFAULT_MODEL 2>/dev/null

echo "=== [3/7] 容器列表（含 Matrix 服务器） ==="
docker ps --format '{{.Names}} | {{.Image}} | {{.Status}}'

echo "=== [4/7] 凭据来源文件（路径清单，不打印内容） ==="
grep -rl 'AGENTTEAMS_ADMIN_PASSWORD' /workspace --include='*.yml' --include='*.yaml' --include='*.env' --include='*.sh' 2>/dev/null | head -10
ls /workspace/.env /workspace/*.env 2>/dev/null

echo "=== [5/7] 今日 provision 脚本（决定密码轮换时点） ==="
ls -la /workspace/cloudstudio-provision-kimi-k3.sh /workspace/k3*.sh 2>/dev/null | awk '{print $6, $7, $8, $9}'

echo "=== [6/7] controller 内 homeserver 配置位置（路径 only） ==="
docker exec agentteams-controller sh -c 'find / -name "homeserver.yaml" -o -name "*.signing.key" 2>/dev/null | head -5' 2>/dev/null

echo "=== [7/7] Matrix 服务器数据卷（判断密码是否随卷持久） ==="
docker inspect agentteams-controller --format '{{json .Mounts}}' 2>/dev/null | head -c 600
echo ""
echo "=== AUTH_PROBE_DONE ==="
