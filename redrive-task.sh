#!/usr/bin/env bash
# goai-crisis-cloud-bridge · 补发 -01 任务委派通知（操作员恢复动作）
# 场景：Leader 建了项目与任务输入，但 Matrix 委派通知未到达 Worker（crash 窗口期）。
# 做法：用 Leader 容器自己的 Matrix token（只读 env，不打印）按 taskSpec 原文格式补发通知到团队房间。
set -uo pipefail
LEAD=agentteams-worker-juchang-v14-lead
DOMAIN='matrix-local.agentteams.io:18080'
MATRIX_URL='http://agentteams-controller:6167'
PID='cloud-crisis-2014-east-art-center-p2'
TID='cloud-crisis-2014-east-art-center-p2-01'
TEAM_ROOM='!S7Rk2N6pPUGg08VdXo:matrix-local.agentteams.io:18080'
WORKER_ID="@juchang-v14-material-intake:$DOMAIN"
LEADER_ID="@juchang-v14-lead:$DOMAIN"

echo "=== [1/3] 构造任务信封（与 leader-runtime taskSpec 逐字段一致） ==="
docker exec $LEAD sh -c "
  jq -n \
    --arg pid '$PID' --arg tid '$TID' --arg leader '$LEADER_ID' --arg worker '$WORKER_ID' '
    {
      msgtype: \"m.text\",
      body: (\"JUCHANG_DSH_TASK: \" + ({
        schema: \"juchang-agentteams-dsh-task@1\",
        projectId: \$pid,
        taskId: \$tid,
        role: \"material_intake\",
        inputPath: (\"tasks/\" + \$tid + \"/workspace/input.json\"),
        workspacePath: (\"tasks/\" + \$tid + \"/workspace\"),
        publicWriteAllowed: false
      } | tojson) + \"\n\n# 现场事实与时间线\nRead the exact task envelope above. Use the official Taskflow lifecycle exposed by the DSH runtime.\nAfter submit_task succeeds, mention \" + \$leader + \" with TASK_COMPLETED: \" + \$tid + \".\nNever approve, publish, refund, send external messages, or write production data.\"),
      \"m.mentions\": {user_ids: [\$worker]}
    }' > /tmp/redrive-msg.json
  jq -r '.body[:100] + \"…\"' /tmp/redrive-msg.json
"
docker exec $LEAD sh -c 'cp /tmp/redrive-msg.json /tmp/redrive-msg-cp.json' 2>/dev/null || true

echo "=== [2/3] 用 Leader 自己的 token 发送（身份即 Leader，Worker 合同要求） ==="
docker exec $LEAD sh -c "
  T=\$AGENTTEAMS_WORKER_MATRIX_TOKEN
  [ -z \"\$T\" ] && { echo 'FAIL: leader 容器无 AGENTTEAMS_WORKER_MATRIX_TOKEN'; exit 1; }
  ROOM_ENC=\$(jq -rn --arg r '$TEAM_ROOM' '\$r|@uri')
  curl -s -X PUT -H \"Authorization: Bearer \$T\" -H 'Content-Type: application/json' -d @/tmp/redrive-msg.json \"$MATRIX_URL/_matrix/client/v3/rooms/\$ROOM_ENC/send/m.room.message/\$(date +%s%N)\" | jq -r 'if .event_id then \"REDRIVE_SENT event=\" + .event_id else \"SEND_FAIL\" end'
"

echo "=== [3/3] 验证与观察 ==="
echo "30-60 秒后跑 task-progress.sh：-01 工作区应出现 receipt.json / 新增文件。"
echo "若 Worker 报 BLOCKED 且 error 含 ack_task：说明 Taskflow 里该任务已是终态，需要 Leader 侧恢复（截图发我）。"
echo "=== REDRIVE_DONE ==="
