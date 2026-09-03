#!/usr/bin/env bash
# goai-crisis-cloud-bridge · 重启四岗+Leader（清 stale IP）并重发 DSH 项目派单
# 背景：controller 重启换 IP 后，Worker 对 agentteams-controller:9000 的引用过期（mc alias connection refused）。
set -uo pipefail
C=agentteams-controller
LEAD=agentteams-worker-juchang-v14-lead
BRIDGE="https://raw.githubusercontent.com/endtree-FDE/goai-crisis-cloud-bridge/main"

echo "=== [1/5] 重启四岗 + Leader（stateless 设计，状态在共享存储） ==="
docker restart agentteams-worker-juchang-v14-material-intake agentteams-worker-juchang-v14-evidence-guard agentteams-worker-juchang-v14-entity-matcher agentteams-worker-juchang-v14-approval-guard $LEAD 2>&1
echo "等待 35 秒让运行时起来..."
sleep 35

echo "=== [2/5] 验证 MinIO 引用恢复 ==="
BAD=$(docker logs $LEAD --since 2m 2>&1 | grep -c 'connection refused' || true)
echo "leader_recent_connection_refused=$BAD"
docker logs $LEAD --tail 4 2>&1 | sed -E 's/(token|password|key)=[^ ]+/\1=<redacted>/gi'
READY=$(docker logs $LEAD --since 2m 2>&1 | grep -c 'DSH_LEADER_READY' || true)
echo "leader_ready_markers=$READY"

echo "=== [3/5] Team 状态 ==="
docker exec $C agt get teams juchang-change-control-v14 2>&1 | grep -E 'Phase|LeaderReady|ReadyWorkers'

echo "=== [4/5] 重发项目派单（若 Leader 已处理过旧消息则 create_project 幂等拒绝，属预期） ==="
bash <(curl -sL "$BRIDGE/dispatch-project.sh") 2>&1 | grep -E '===|SENT|FAIL|OK|MISMATCH'

echo "=== [5/5] 完成。2-3 分钟后跑 watch-run.sh 应见 latest_project=cloud-crisis-2014-east-art-center-p2 ==="
echo "=== BOUNCE_REDISPATCH_DONE ==="
