#!/usr/bin/env bash
# goai-crisis-cloud-bridge · 阶跃模型额度实测（真实最小调用；key 不回显）
set -uo pipefail
W=agentteams-worker-juchang-v14-material-intake
echo "=== [1/2] 网关模型列表（确认路由存在） ==="
docker exec $W sh -c 'curl -s --max-time 8 -H "Authorization: Bearer $AGENTTEAMS_WORKER_GATEWAY_KEY" "http://agentteams-controller:8080/v1/models" | head -c 400'
echo ""
echo "=== [2/2] 真实最小对话调用（max_tokens=1） ==="
docker exec $W sh -c 'curl -s --max-time 20 -X POST -H "Authorization: Bearer $AGENTTEAMS_WORKER_GATEWAY_KEY" -H "Content-Type: application/json" -d "{\"model\":\"step-3.5-flash-2603\",\"messages\":[{\"role\":\"user\",\"content\":\"ping\"}],\"max_tokens\":1}" "http://agentteams-controller:8080/v1/chat/completions" | head -c 600'
echo ""
echo "=== QUOTA_PROBE_DONE ==="
echo "判读：正常 JSON 含 choices = 有额度；insufficient_quota/余额/quota/limit 字样 = 没额度了；401/403 = key 问题；其他错误贴给我。"
