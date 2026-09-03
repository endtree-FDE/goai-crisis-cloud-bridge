#!/usr/bin/env bash
# goai-crisis-cloud-bridge · dashboard Matrix token 存储位置侦察（只读，不打印 token 值）
set -uo pipefail
D=agentteams-dashboard
C=agentteams-controller

echo "=== [1/4] dashboard 容器内近期写入的文件 ==="
docker exec $D sh -c 'find / -newer /etc/hostname -type f -not -path "*/node_modules/*" -not -path "/proc/*" -not -path "/sys/*" -not -path "/dev/*" 2>/dev/null | head -20'

echo "=== [2/4] dashboard 内含 access_token 字段的文件 ==="
docker exec $D sh -c 'grep -rl "access_token" /data /root /home /app /srv /var/lib 2>/dev/null | grep -v node_modules | head -10'

echo "=== [3/4] controller 数据卷内含 access_token 的文件 ==="
docker exec $C sh -c 'grep -rl "access_token" /data 2>/dev/null | head -10'

echo "=== [4/4] dashboard 进程与启动命令 ==="
docker exec $D sh -c 'ps aux | head -8'
echo "=== PROBE_DASH_TOKEN_DONE ==="
