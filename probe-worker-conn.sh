#!/usr/bin/env bash
# goai-crisis-cloud-bridge · Worker 侧 Matrix/网关连通性实测（只读，token 脱敏）
set -uo pipefail
W=agentteams-worker-juchang-v14-material-intake
echo "=== [1/4] Worker → Tuwunel 连通 ==="
docker exec $W sh -c 'curl -s -o /dev/null -w "matrix-versions=%{http_code}\n" --max-time 8 http://agentteams-controller:6167/_matrix/client/versions'
echo "=== [2/4] Worker Matrix token 是否仍有效（sync 探测，不显示 token） ==="
docker exec $W sh -c 'curl -s -o /tmp/syncprobe.json -w "matrix-sync=%{http_code}\n" --max-time 10 -H "Authorization: Bearer $AGENTTEAMS_WORKER_MATRIX_TOKEN" "http://agentteams-controller:6167/_matrix/client/v3/sync?timeout=0"; jq -r ".errcode // \"ok\"" /tmp/syncprobe.json 2>/dev/null'
echo "=== [3/4] Worker → AI 网关 ==="
docker exec $W sh -c 'BASE="${AGENTTEAMS_OPENAI_BASE_URL:-$AGENTTEAMS_AI_GATEWAY_URL}"; echo "base=$BASE"; curl -s -o /dev/null -w "gateway-models=%{http_code}\n" --max-time 8 -H "Authorization: Bearer $AGENTTEAMS_WORKER_GATEWAY_KEY" "$BASE/models"'
echo "=== [4/4] Worker → MinIO 实测 ==="
docker exec $W sh -c 'curl -s -o /dev/null -w "minio=%{http_code}\n" --max-time 8 http://agentteams-controller:9000/minio/health/live'
echo "=== WORKER_CONN_PROBE_DONE ==="
