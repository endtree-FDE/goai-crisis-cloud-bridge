#!/usr/bin/env bash
# goai-crisis-cloud-bridge · 重启 controller 触发 registerAdmin 自愈（EnsureUser 孤儿恢复链）
# 原理：Initializer.Run → registerAdmin → EnsureUser(admin)：register 失败(已存在) → login 失败 → 自动 !admin users reset-password → 重试登录
set -uo pipefail
echo "=== [1/3] 重启 controller（自愈触发点） ==="
docker restart agentteams-controller
echo "restarted; 等待 25s 让 Initializer 跑完..."
sleep 25
echo "=== [2/3] init 日志关键行 ==="
docker logs agentteams-controller --since 3m 2>&1 | grep -iE 'admin|matrix|initializ|error|fail' | tail -25
echo "=== [3/3] Team 状态复查 ==="
docker exec agentteams-controller agt get teams juchang-change-control-v14 2>&1 | grep -E 'Phase|LeaderReady|ReadyWorkers|Message|LeaderDMRoomID'
echo ""
echo "判读：Phase 不再是 Failed 且 Message 清空 = 自愈成功，可以跑 dispatch.sh"
echo "若 Message 仍报 login admin 403 = 把上面三段输出截图发回"
echo "=== FIX_ADMIN_DONE ==="
