#!/usr/bin/env bash
# goai-crisis-cloud-bridge · 观察云端派单运行状态（只读，可反复跑）
set -uo pipefail
echo "=== [1/3] 最新项目与工作区 ==="
LEAD=agentteams-worker-juchang-v14-lead
SHARED=$(docker exec $LEAD sh -c 'printf %s "$AGENTTEAMS_SHARED_DIR"')
docker exec $LEAD sh -c "ls -t '$SHARED'/projects/ 2>/dev/null | head -3"
PROJ=$(docker exec $LEAD sh -c "ls -t '$SHARED'/projects/ 2>/dev/null | head -1")
echo "latest_project=${PROJ:-none}"
if [ -n "$PROJ" ]; then
  echo "--- 工作区文件 ---"
  docker exec $LEAD sh -c "ls '$SHARED'/projects/'$PROJ'/workspace/ 2>/dev/null"
  echo "--- 任务目录 ---"
  docker exec $LEAD sh -c "ls -t '$SHARED'/tasks/ 2>/dev/null | head -6"
fi
echo "=== [2/3] Worker 容器近况（最近 5 行日志尾部标记） ==="
for w in material-intake evidence-guard entity-matcher approval-guard; do
  echo "--- $w ---"
  docker logs "agentteams-worker-juchang-v14-$w" --tail 3 2>&1 | sed -E 's/(token|password|key)=[^ ]+/\1=<redacted>/gi'
done
echo "=== [3/3] Leader 日志尾部 ==="
docker logs $LEAD --tail 6 2>&1 | sed -E 's/(token|password|key)=[^ ]+/\1=<redacted>/gi'
echo "=== WATCH_DONE $(date +%H:%M:%S) ==="
