#!/usr/bin/env bash
# goai-crisis-cloud-bridge · 任务级进度细查（只读）
set -uo pipefail
W=agentteams-worker-juchang-v14-material-intake
LEAD=agentteams-worker-juchang-v14-lead
echo "=== [1/3] 任务 -01 工作区现状 ==="
docker exec $LEAD sh -c 'ls -la "$AGENTTEAMS_SHARED_DIR/tasks/cloud-crisis-2014-east-art-center-p3-01/workspace/" 2>/dev/null'
echo "=== [2/3] material-intake 容器内是否有活的 DSH 任务进程 ==="
docker exec $W sh -c 'ps aux | grep -iE "dsh|node" | grep -v grep | head -5'
echo "=== [3/3] material-intake 最近日志（脱敏） ==="
docker logs $W --tail 15 2>&1 | sed -E 's/(key|token|password)[":= ]+[A-Za-z0-9._-]+/\1=<redacted>/gi'
echo "=== TASK_PROGRESS_DONE ==="
