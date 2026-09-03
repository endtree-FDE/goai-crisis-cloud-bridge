#!/usr/bin/env bash
# goai-crisis-cloud-bridge · 模型路由探针（只读，不打印密钥；模型 ID 不是机密）
set -uo pipefail
echo "=== [1/3] manifest 声明的模型路由 ==="
grep -rhoE '[a-z0-9._-]*(flash|k3|kimi|step|glm|deepseek|qwen)[a-z0-9._-]*' \
  /workspace/agentteams-dsh-runtime-v040/deploy /workspace/agentteams-dsh-runtime-v040/profiles 2>/dev/null \
  | grep -E '^[a-z]+' | sort -u | head -20
echo "=== [2/3] 运行时容器模型相关环境变量（仅名称与是否设置） ==="
for c in agentteams-manager agentteams-controller agentteams-worker-juchang-v14-lead; do
  echo "--- $c ---"
  docker exec "$c" env 2>/dev/null | grep -iE 'model' | sed 's/=.*$/=<set>/' || echo "(container not running or no match)"
done
echo "=== [3/3] 运行时 profiles 里的模型直写 ==="
grep -rn 'model' /workspace/agentteams-dsh-runtime-v040/profiles/*.yaml 2>/dev/null | grep -iE 'model|flash|k3|step' | head -20
echo "=== MODEL_PROBE_DONE ==="
