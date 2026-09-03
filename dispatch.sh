#!/usr/bin/env bash
# goai-crisis-cloud-bridge · 东艺危机云端派单一键执行
# 流程：Team 就绪校验 → Leader DM 房间三方核对 → 经 controller 容器 Matrix API 发送派单 → 观察指引
set -uo pipefail
cd /workspace 2>/dev/null || cd ~

BRIDGE="https://raw.githubusercontent.com/endtree-FDE/goai-crisis-cloud-bridge/main"
EXPECTED_ROOM='!GKL4XFzVKBFE6bqGad:matrix-local.agentteams.io:18080'
TEAM='juchang-change-control-v14'

echo "=== [1/5] agt 定位 ==="
AGT="agt"
if ! command -v agt >/dev/null 2>&1; then
  AGT="docker exec agentteams-controller agt"
fi
echo "AGT=$AGT"

echo "=== [2/5] Team 就绪 ==="
$AGT get teams "$TEAM" 2>&1 | tee /tmp/juchang-team.txt | head -50
if grep -qE "LeaderReady:\s*true" /tmp/juchang-team.txt && grep -qE "ReadyWorkers:\s*4/4" /tmp/juchang-team.txt; then
  echo "TEAM_READY_OK"
else
  echo "TEAM_NOT_READY — 把上面输出截图发回；不要继续。"
  exit 1
fi

echo "=== [3/5] 房间三方核对 ==="
ROOM=$(grep 'LeaderDMRoomID' /tmp/juchang-team.txt | grep -oE '\![A-Za-z0-9]+:[A-Za-z0-9._-]+:[0-9]+' | head -1)
echo "LeaderDMRoomID(from agt)=$ROOM"
if [ "$ROOM" != "$EXPECTED_ROOM" ]; then
  echo "ROOM_TARGET_MISMATCH: 派单目标是 $EXPECTED_ROOM，当前 Team 是 $ROOM"
  exit 1
fi
echo "ROOM_TARGET_OK"

echo "=== [4/5] 派单落盘并送入 controller ==="
curl -sL "$BRIDGE/dispatch.txt" -o /tmp/juchang-dispatch.txt
curl -sL "$BRIDGE/send-room-message.sh" -o /tmp/send-room-message.sh
wc -c /tmp/juchang-dispatch.txt
docker cp /tmp/juchang-dispatch.txt agentteams-controller:/tmp/juchang-dispatch.txt
docker cp /tmp/send-room-message.sh agentteams-controller:/tmp/send-room-message.sh

echo "=== [5/5] 发送（operator 触发 = 人工确认点） ==="
docker exec agentteams-controller bash /tmp/send-room-message.sh "$ROOM" /tmp/juchang-dispatch.txt

echo ""
echo "=== 已发送。观察方式： ==="
echo "1) dashboard（13000 转发地址）Matrix 聊天 → juchang-change-control-v14 团队房间应有四岗活动"
echo "2) 完成后应出现 JUCHANG_CLOUD_TEAM_FINAL: READY_FOR_HUMAN_REVIEW"
echo "3) 回收证据：shared/projects/<project_id>/workspace/juchang-cloud-runtime-evidence.json"
