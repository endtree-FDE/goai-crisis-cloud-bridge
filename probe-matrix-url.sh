#!/usr/bin/env bash
# goai-crisis-cloud-bridge · Worker 实际配置的 Matrix URL 实测（只读）
set -uo pipefail
W=agentteams-worker-juchang-v14-material-intake
echo "=== [1/3] Worker runtime.yaml 里的 matrixUrl（非密配置项） ==="
docker exec $W sh -c 'grep -iE "matrixurl|matrix_url|matrixUrl" /workspace/runtime.yaml 2>/dev/null || find / -maxdepth 3 -name "runtime.yaml" 2>/dev/null | head -3'
echo "=== [2/3] Worker 容器 env 里的 MATRIX_URL ==="
docker exec $W sh -c 'printenv | grep -iE "matrix.*url|url.*matrix"'
echo "=== [3/3] 用配置里的真实 URL 实测 fetch ==="
docker exec $W sh -c 'URL=$(printenv AGENTTEAMS_MATRIX_URL); echo "env_url=$URL"; curl -s -o /dev/null -w "cfg-url=%{http_code} err=%{errormsg}\n" --max-time 8 "$URL/_matrix/client/versions"; curl -s -o /dev/null -w "public-domain=%{http_code} err=%{errormsg}\n" --max-time 8 "http://matrix-local.agentteams.io:18080/_matrix/client/versions"'
echo "=== MATRIX_URL_PROBE_DONE ==="
