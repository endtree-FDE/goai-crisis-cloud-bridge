#!/usr/bin/env bash
# goai-crisis-cloud-bridge · 模型网关连通性 + fetch failed 全上下文侦察（只读，脱敏）
set -uo pipefail
LEAD=agentteams-worker-juchang-v14-lead
echo "=== [1/4] Leader 日志 fetch failed 完整上下文 ==="
docker logs $LEAD --tail 80 2>&1 | grep -B 8 'fetch failed' | tail -20 | sed -E 's/(key|token|password)["=: ]+[A-Za-z0-9._-]+/\1=<redacted>/gi'
echo "=== [2/4] Worker 模型网关环境与连通性（值脱敏） ==="
docker exec $LEAD sh -c 'env | grep -iE "gateway|openai|model" | sed -E "s/(KEY|TOKEN)=(.+)/\1=<set>/g"'
docker exec $LEAD sh -c 'BASE="${AGENTTEAMS_OPENAI_BASE_URL:-$AGENTTEAMS_AI_GATEWAY_URL}"; echo "base=$BASE"; curl -s -o /dev/null -w "gateway-models=%{http_code}\n" --max-time 8 -H "Authorization: Bearer $AGENTTEAMS_WORKER_GATEWAY_KEY" "$BASE/models"'
echo "=== [3/4] 模型调用实测（chat completions 空载探测） ==="
docker exec $LEAD sh -c 'BASE="${AGENTTEAMS_OPENAI_BASE_URL:-$AGENTTEAMS_AI_GATEWAY_URL}"; curl -s -o /tmp/modelprobe.json -w "chat-probe=%{http_code}\n" --max-time 15 -H "Authorization: Bearer $AGENTTEAMS_WORKER_GATEWAY_KEY" -H "Content-Type: application/json" -d "{\"model\":\"$AGENTTEAMS_DEFAULT_MODEL\",\"messages\":[{\"role\":\"user\",\"content\":\"ping\"}],\"max_tokens\":1}" "$BASE/chat/completions"; head -c 200 /tmp/modelprobe.json | sed -E "s/(key|token)[\": ]+[A-Za-z0-9._-]+/\1=<redacted>/gi"'
echo ""
echo "=== [4/4] 任务 -01 工作区状态 ==="
docker exec $LEAD sh -c 'ls -la "$AGENTTEAMS_SHARED_DIR/tasks/cloud-crisis-2014-east-art-center-p2-01/workspace/" 2>/dev/null || echo "(任务工作区尚未创建)"'
echo "=== MODEL_GW_PROBE_DONE ==="
