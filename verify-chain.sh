#!/usr/bin/env bash
# goai-crisis-cloud-bridge · 原生链验收（Codex 七步清单，官方读回为准，只读）
# 用法：bash verify-chain.sh [projectId]（默认 cloud-crisis-2014-east-art-center-p4）
set -uo pipefail
PID="${1:-cloud-crisis-2014-east-art-center-p4}"
C=agentteams-controller
LEAD=agentteams-worker-juchang-v14-lead
echo "验收对象: $PID"

echo "=== [1/7] 官方 Project 读回（Controller API 经 agt） ==="
docker exec $C agt get projects 2>&1 | grep -E "$PID|PROJECT|ID|STATUS" | head -5 || docker exec $C agt get projects 2>&1 | tail -8

echo "=== [2/7] 官方任务清单与依赖（四任务 + dependsOn） ==="
docker exec $C agt get projects "$PID" 2>&1 | head -60

echo "=== [3/7] 委派通知送达证明（团队房间含 p4 任务信封的 Leader 消息） ==="
docker exec $C sh -c "
T=\$(curl -s -X POST -H 'Content-Type: application/json' -d '{\"type\":\"m.login.password\",\"identifier\":{\"type\":\"m.id.user\",\"user\":\"admin\"},\"password\":\"'\$AGENTTEAMS_ADMIN_PASSWORD'\"}' 'http://127.0.0.1:6167/_matrix/client/v3/login' | sed -E 's/.*\"access_token\":\"([^\"]+)\".*/\1/')
curl -s -H \"Authorization: Bearer \$T\" 'http://127.0.0.1:6167/_matrix/client/v3/rooms/%21S7Rk2N6pPUGg08VdXo%3Amatrix-local.agentteams.io%3A18080/messages?limit=30&dir=b' | tr ',' '\n' | grep -E '$PID|JUCHANG_DSH_TASK|TASK_COMPLETED|sender' | tail -20
curl -s -X POST -H \"Authorization: Bearer \$T\" 'http://127.0.0.1:6167/_matrix/client/v3/logout' >/dev/null 2>&1
"

echo "=== [4/7] Worker 侧：-01 工作区（ACK/执行/提交的落盘证据） ==="
docker exec $LEAD sh -c "ls -la \"\$AGENTTEAMS_SHARED_DIR/tasks/$PID-01/workspace/\" 2>/dev/null"

echo "=== [5/7] Worker 回执存在性 ==="
docker exec $LEAD sh -c "for i in 01 02 03 04; do f=\"\$AGENTTEAMS_SHARED_DIR/tasks/$PID-\$i/workspace/receipt.json\"; [ -f \"\$f\" ] && echo \"\$i receipt: YES\" || echo \"\$i receipt: no\"; done"

echo "=== [6/7] Leader 验收证据（leader 工作区 audit 与回执） ==="
docker exec $LEAD sh -c "ls \"\$AGENTTEAMS_SHARED_DIR/projects/$PID/workspace/\" 2>/dev/null; echo '---'; [ -f \"\$AGENTTEAMS_SHARED_DIR/projects/$PID/workspace/juchang-cloud-audit.json\" ] && echo 'audit.json: YES' || echo 'audit.json: no'"

echo "=== [7/7] 收口状态（Project 终态） ==="
docker exec $C agt get projects "$PID" 2>&1 | grep -iE 'status|state|phase' | head -5
echo "=== VERIFY_CHAIN_DONE ==="
echo "判读：1 有项目 + 2 四任务依赖正确 + 3 有委派消息 + 4/5 receipt 齐 + 6 audit 齐 + 7 completed = 原生闭环成立。"
echo "卡哪步贴哪步。缺 3 而 1/2 正常 = 通知层问题；缺 5 而 3 有 = Worker 执行层问题。"
