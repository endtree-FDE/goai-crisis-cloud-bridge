#!/usr/bin/env bash
# goai-crisis-cloud-bridge · 补发 -01 任务委派通知 v2（node 版，Leader 容器无 jq）
# 用 Leader 容器自己的 Matrix token（env 直读，不打印）按 taskSpec 原文格式补发通知到团队房间。
set -uo pipefail
LEAD=agentteams-worker-juchang-v14-lead
DOMAIN='matrix-local.agentteams.io:18080'
MATRIX_URL='http://agentteams-controller:6167'
PID='cloud-crisis-2014-east-art-center-p2'
TID='cloud-crisis-2014-east-art-center-p2-01'
TEAM_ROOM='!S7Rk2N6pPUGg08VdXo:matrix-local.agentteams.io:18080'
WORKER_ID="@juchang-v14-material-intake:$DOMAIN"
LEADER_ID="@juchang-v14-lead:$DOMAIN"

echo "=== [1/3] 构造任务信封（node，逐字段对齐 leader-runtime taskSpec） ==="
docker exec -e PID="$PID" -e TID="$TID" -e LEADER_ID="$LEADER_ID" -e WORKER_ID="$WORKER_ID" $LEAD sh -c '
node -e "
const pid = process.env.PID, tid = process.env.TID;
const envelope = {
  schema: \"juchang-agentteams-dsh-task@1\",
  projectId: pid,
  taskId: tid,
  role: \"material_intake\",
  inputPath: \"tasks/\" + tid + \"/workspace/input.json\",
  workspacePath: \"tasks/\" + tid + \"/workspace\",
  publicWriteAllowed: false
};
const body = \"JUCHANG_DSH_TASK: \" + JSON.stringify(envelope) + \"\n\n# 现场事实与时间线\nRead the exact task envelope above. Use the official Taskflow lifecycle exposed by the DSH runtime.\nAfter submit_task succeeds, mention \" + process.env.LEADER_ID + \" with TASK_COMPLETED: \" + tid + \".\nNever approve, publish, refund, send external messages, or write production data.\";
const msg = { msgtype: \"m.text\", body, \"m.mentions\": { user_ids: [process.env.WORKER_ID] } };
require(\"fs\").writeFileSync(\"/tmp/redrive-msg.json\", JSON.stringify(msg));
console.log(\"envelope_bytes=\" + body.length);
"'

echo "=== [2/3] 用 Leader 自己的 token 发送 ==="
docker exec -e TEAM_ROOM="$TEAM_ROOM" -e MATRIX_URL="$MATRIX_URL" $LEAD sh -c '
node -e "
const fs = require(\"fs\");
const token = process.env.AGENTTEAMS_WORKER_MATRIX_TOKEN || \"\";
if (!token) { console.log(\"FAIL: leader 容器无 AGENTTEAMS_WORKER_MATRIX_TOKEN\"); process.exit(1); }
const msg = fs.readFileSync(\"/tmp/redrive-msg.json\", \"utf8\");
const room = encodeURIComponent(process.env.TEAM_ROOM);
const url = process.env.MATRIX_URL + \"/_matrix/client/v3/rooms/\" + room + \"/send/m.room.message/\" + Date.now();
fetch(url, { method: \"PUT\", headers: { Authorization: \"Bearer \" + token, \"Content-Type\": \"application/json\" }, body: msg })
  .then(async (r) => { const j = await r.json().catch(() => ({})); console.log(r.ok ? \"REDRIVE_SENT event=\" + j.event_id : \"SEND_FAIL \" + r.status + \" \" + (j.errcode || \"\")); })
  .catch((e) => { console.log(\"SEND_FAIL \" + e.message); process.exit(1); });
"'

echo "=== [3/3] 观察 ==="
echo "60 秒后跑 task-progress.sh：-01 应出现 receipt.json 或新文件；Worker 若报 ack_task BLOCKED 则截图发我。"
echo "=== REDRIVE_DONE ==="
