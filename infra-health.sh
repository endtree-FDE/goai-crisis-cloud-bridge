#!/usr/bin/env bash
# goai-crisis-cloud-bridge · 嵌入式基础设施体检（controller 容器内全栈：Tuwunel/MinIO/Higress/controller API）
set -uo pipefail
C=agentteams-controller
echo "=== 容器内各服务进程 ==="
docker exec $C sh -c 'ps aux | grep -iE "tuwunel|minio|higress|envoy|controller|nginx" | grep -v grep | awk "{print \$11, \$12}" | head -12'
echo "=== 端口存活（容器内） ==="
for p in 6167 9000 8080 8001 8088; do
  CODE=$(docker exec $C sh -c "curl -s -o /dev/null -w '%{http_code}' --max-time 5 http://127.0.0.1:$p/" 2>/dev/null)
  echo "port $p => ${CODE:-down}"
done
echo "=== MinIO 深查（9000 应 200/403，minio health） ==="
docker exec $C sh -c 'curl -s -o /dev/null -w "minio-live=%{http_code}\n" --max-time 5 http://127.0.0.1:9000/minio/health/live'
echo "=== Higress 深查 ==="
docker exec $C sh -c 'curl -s -o /dev/null -w "higress-8080=%{http_code}\n" --max-time 5 http://127.0.0.1:8080/; curl -s -o /dev/null -w "higress-console-8001=%{http_code}\n" --max-time 5 http://127.0.0.1:8001/'
echo "=== Worker 日志里的 fetch 失败对象（Leader 尾部 20 行找上下文） ==="
docker logs agentteams-worker-juchang-v14-lead --tail 20 2>&1 | grep -B 2 'fetch failed' | tail -12 | sed -E 's/(token|password|key)=([^ &]+)/\1=<redacted>/gi'
echo "=== INFRA_PROBE_DONE ==="
