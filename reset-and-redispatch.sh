#!/usr/bin/env bash
# goai-crisis-cloud-bridge · 清场重发（根因修复版）：
# Leader 的长轮询在基础设施重启窗口内挂死成僵尸（存活但失聪），且历史信封毒化同步窗口。
# 步骤：官方取消 p2/p3/p4 半成品 → 重启 Leader → 发全新 p5。
set -uo pipefail
C=agentteams-controller
LEAD=agentteams-worker-juchang-v14-lead
BRIDGE="https://raw.githubusercontent.com/endtree-FDE/goai-crisis-cloud-bridge/main"

echo "=== [1/4] 官方取消半成品项目（agt project cancel，走 Controller 写端点） ==="
for p in cloud-crisis-2014-east-art-center-p2 cloud-crisis-2014-east-art-center-p3 cloud-crisis-2014-east-art-center-p4; do
  docker exec $C agt project cancel "$p" 2>&1 | tail -2
done

echo "=== [2/4] 重启 Leader（僵尸长轮询清除） ==="
docker restart $LEAD
sleep 30
docker logs $LEAD --tail 3 2>&1 | sed -E 's/(token|password|key)[":= ]+[A-Za-z0-9._-]+/\1=<redacted>/gi'
echo "（重同步时会对 p2/p3/p4 旧信封报 BLOCKED/create 失败——属预期噪声，说明它看到并拒绝了过期信封）"

echo "=== [3/4] 等 Leader 就绪标志 ==="
i=0
until docker logs $LEAD --since 2m 2>&1 | grep -q 'DSH_LEADER_READY'; do
  i=$((i+1)); [ $i -gt 12 ] && { echo "FAIL: Leader 60 秒未就绪"; exit 1; }
  sleep 5
done
echo "LEADER_READY"

echo "=== [4/4] 发送 p5 全新派单 ==="
bash <(curl -sL "$BRIDGE/dispatch-project-v4.sh") 2>&1 | grep -E '===|SENT|FAIL|OK|MISMATCH'

echo ""
echo "=== 观察：2 分钟后跑 watch-run.sh；latest_project=cloud-crisis-2014-east-art-center-p5 且 -01 出 receipt 即成。"
echo "=== RESET_REDISPATCH_DONE ==="
