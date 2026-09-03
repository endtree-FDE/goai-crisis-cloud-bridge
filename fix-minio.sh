#!/usr/bin/env bash
# goai-crisis-cloud-bridge · 修复 MinIO 只监听 127.0.0.1 导致 Worker 跨容器无法访问
set -uo pipefail
C=agentteams-controller
W=agentteams-worker-juchang-v14-material-intake
FRAG='/etc/supervisor/conf.d/supervisord.conf'

echo "=== [1/5] MinIO 当前监听与启动配置 ==="
docker exec $C sh -c 'ss -tlnp 2>/dev/null | grep 9000 || netstat -tlnp 2>/dev/null | grep 9000'
docker exec $C sh -c "grep -A 8 'program:minio' '$FRAG'"

echo "=== [2/5] 修正监听地址为 0.0.0.0:9000 ==="
docker exec $C sh -c "sed -i -E 's/--address[= ]+127\\.0\\.0\\.1:9000/--address 0.0.0.0:9000/g; s/--address[= ]+localhost:9000/--address 0.0.0.0:9000/g' '$FRAG'"
docker exec $C sh -c "grep -A 8 'program:minio' '$FRAG' | grep -E 'command|address'"

echo "=== [3/5] SIGHUP 全量重载 ==="
docker exec $C sh -c 'kill -HUP $(pgrep -f supervisord | head -1) && echo SIGHUP_SENT'
sleep 25
i=0
until docker exec $C sh -c 'curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:9000/minio/health/live' 2>/dev/null | grep -q 200; do
  i=$((i+1)); [ $i -gt 12 ] && { echo "FAIL: MinIO 60 秒未恢复"; exit 1; }
  sleep 5
done
echo "minio-up"

echo "=== [4/5] 验证网络面监听 ==="
docker exec $C sh -c 'ss -tlnp 2>/dev/null | grep 9000 || netstat -tlnp 2>/dev/null | grep 9000'

echo "=== [5/5] 从 Worker 实测 mc 连通 ==="
docker exec $W sh -c 'mc alias set agentteams http://agentteams-controller:9000 "$AGENTTEAMS_FS_ACCESS_KEY" "$AGENTTEAMS_FS_SECRET_KEY" 2>&1 | tail -2'
echo "=== FIX_MINIO_DONE ==="
echo "若 [5/5] 无 connection refused：Worker 下次重试即恢复；随后跑 watch-run.sh 看 -01 是否出 receipt。"
