#!/usr/bin/env bash
# goai-crisis-cloud-bridge · p3 委派链终诊（带时间戳，只读）
set -uo pipefail
C=agentteams-controller
LEAD=agentteams-worker-juchang-v14-lead
W=agentteams-worker-juchang-v14-material-intake
echo "=== [1/5] Leader 日志：p3 委派动作（带时间戳） ==="
docker logs $LEAD -t --since 2h 2>&1 | grep -iE 'p3|delegate|assign|decision|create_project|plan_dag|BLOCKED|FAILED' | tail -20 | sed -E 's/(token|password|key)[":= ]+[A-Za-z0-9._-]+/\1=<redacted>/gi'
echo "=== [2/5] 团队房间最近 8 条消息（admin 视角，时间戳） ==="
docker exec $C sh -c '
T=$(curl -s -X POST -H "Content-Type: application/json" -d "{\"type\":\"m.login.password\",\"identifier\":{\"type\":\"m.id.user\",\"user\":\"admin\"},\"password\":\"$AGENTTEAMS_ADMIN_PASSWORD\"}" "http://127.0.0.1:6167/_matrix/client/v3/login" | sed -E "s/.*\"access_token\":\"([^\"]+)\".*/\1/")
curl -s -H "Authorization: Bearer $T" "http://127.0.0.1:6167/_matrix/client/v3/rooms/%21S7Rk2N6pPUGg08VdXo%3Amatrix-local.agentteams.io%3A18080/messages?limit=8&dir=b" | node -e "let d=\"\";process.stdin.on(\"data\",c=>d+=c).on(\"end\",()=>{const j=JSON.parse(d);for(const e of (j.chunk||[]).reverse()){if(e.type!==\"m.room.message\")continue;const t=new Date(e.origin_server_ts).toISOString().slice(11,19);console.log(t,(e.sender||\"\").split(\":\")[0],String(e.content?.body||\"\").slice(0,110).replace(/\n/g,\" ⏎ \"))}})"
curl -s -X POST -H "Authorization: Bearer $T" "http://127.0.0.1:6167/_matrix/client/v3/logout" >/dev/null 2>&1
'
echo "=== [3/5] p3 全部任务目录与工作区 ==="
docker exec $LEAD sh -c 'ls -t "$AGENTTEAMS_SHARED_DIR/tasks/" | grep p3; for t in $(ls "$AGENTTEAMS_SHARED_DIR/tasks/" | grep p3); do echo "--- $t"; ls "$AGENTTEAMS_SHARED_DIR/tasks/$t/workspace/" 2>/dev/null; done'
echo "=== [4/5] Worker 当前是否在长轮询（/proc 进程列表） ==="
docker exec $W sh -c 'for p in /proc/[0-9]*/cmdline; do tr "\0" " " < $p 2>/dev/null | grep -qE "node|dsh" && basename $(dirname $p); done | head -5'
echo "=== [5/5] Worker 最新 3 条日志（带时间戳） ==="
docker logs $W -t --tail 3 2>&1 | sed -E 's/(token|password|key)[":= ]+[A-Za-z0-9._-]+/\1=<redacted>/gi'
echo "=== FINAL_DIAG_DONE ==="
