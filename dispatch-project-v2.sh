#!/usr/bin/env bash
# goai-crisis-cloud-bridge · DSH 格式云端派单（juchang-agentteams-dsh-project@1 信封 · v2: p3 全新 dispatchId，绕开 p2 丢失的 Taskflow 注册）
# 前置：admin Matrix 密码已恢复（fix-admin-v33 跑过）。全程不打印密码/token。
set -uo pipefail
C=agentteams-controller
LEAD=agentteams-worker-juchang-v14-lead
TEAM='juchang-change-control-v14'
DOMAIN='matrix-local.agentteams.io:18080'
MATRIX_URL='http://127.0.0.1:6167'
DISPATCH_ID='cloud-crisis-2014-east-art-center-p3'
BRIDGE="https://raw.githubusercontent.com/endtree-FDE/goai-crisis-cloud-bridge/main"

echo "=== [1/6] Team 就绪 ==="
docker exec $C agt get teams "$TEAM" > /tmp/juchang-team.txt 2>&1
grep -E 'Phase|LeaderReady|ReadyWorkers|LeaderDMRoomID' /tmp/juchang-team.txt
grep -qE 'Phase:[[:space:]]*Active' /tmp/juchang-team.txt || { echo 'FAIL: Team 非 Active'; exit 1; }
grep -qE 'LeaderReady:[[:space:]]*true' /tmp/juchang-team.txt || { echo 'FAIL: Leader 未就绪'; exit 1; }
grep -qE 'ReadyWorkers:[[:space:]]*4/4' /tmp/juchang-team.txt || { echo 'FAIL: Workers 未 4/4'; exit 1; }
ROOM=$(grep 'LeaderDMRoomID' /tmp/juchang-team.txt | grep -oE '\![A-Za-z0-9]+:[A-Za-z0-9._-]+:[0-9]+' | head -1)
echo "LEADER_DM=$ROOM"
[ "$ROOM" = '!GKL4XFzVKBFE6bqGad:matrix-local.agentteams.io:18080' ] && echo "ROOM_TARGET_OK" || { echo "ROOM_TARGET_MISMATCH"; exit 1; }

echo "=== [2/6] 读取权威 roleBindings（Leader 配置，含四岗 Matrix 身份） ==="
RB_JSON=$(docker exec $LEAD printenv JUCHANG_ROLE_BINDINGS_JSON 2>/dev/null)
if [ -n "$RB_JSON" ]; then
  echo "$RB_JSON" > /tmp/role-bindings.json
  echo "source=JUCHANG_ROLE_BINDINGS_JSON"
else
  echo "env 无 roleBindings，按命名约定构造并校验..."
  jq -n --arg d "$DOMAIN" '{
    material_intake: {runtimeName:"juchang-v14-material-intake", matrixUserId:("@juchang-v14-material-intake:" + $d)},
    evidence_guard: {runtimeName:"juchang-v14-evidence-guard", matrixUserId:("@juchang-v14-evidence-guard:" + $d)},
    entity_matcher: {runtimeName:"juchang-v14-entity-matcher", matrixUserId:("@juchang-v14-entity-matcher:" + $d)},
    approval_guard: {runtimeName:"juchang-v14-approval-guard", matrixUserId:("@juchang-v14-approval-guard:" + $d)}
  }' > /tmp/role-bindings.json
  echo "source=naming-convention"
fi
jq -r 'to_entries[] | .key + " => " + .value.matrixUserId' /tmp/role-bindings.json

MI=$(jq -r '.material_intake.matrixUserId' /tmp/role-bindings.json)
EG=$(jq -r '.evidence_guard.matrixUserId' /tmp/role-bindings.json)
EM=$(jq -r '.entity_matcher.matrixUserId' /tmp/role-bindings.json)
AG=$(jq -r '.approval_guard.matrixUserId' /tmp/role-bindings.json)
LEADER_ID="@juchang-v14-lead:$DOMAIN"

echo "=== [3/6] 构造项目信封（juchang-agentteams-dsh-project@1） ==="
curl -sL "$BRIDGE/crisis-input.json" -o /tmp/crisis-input.json
jq -n \
  --arg dispatchId "$DISPATCH_ID" \
  --arg room "$ROOM" \
  --arg mi "$MI" --arg eg "$EG" --arg em "$EM" --arg ag "$AG" \
  --slurpfile input /tmp/crisis-input.json \
  '{
    schema: "juchang-agentteams-dsh-project@1",
    dispatchId: $dispatchId,
    projectRef: "zhuantang-yixun",
    title: "2014·3·15 东艺演出危机反事实推演（云端权威运行）",
    intakeKind: "retrospective",
    sourceUrl: "http://xmwb.xinmin.cn/html/2014-03/16/content_9_1.htm",
    sourceAuthor: "新民晚报",
    sourceHash: "6b1bf92525dc88517219865b8e2c481307fc4f40c593a7862b1de29f1b3c56f3",
    roomId: $room,
    publicWriteAllowed: false,
    inputPayload: $input[0],
    tasks: [
      {taskId: ($dispatchId + "-01"), role: "material_intake", title: "现场事实与时间线", assignedTo: $mi, dependsOn: []},
      {taskId: ($dispatchId + "-02"), role: "evidence_guard", title: "方案约束与艺术可行性", assignedTo: $eg, dependsOn: [($dispatchId + "-01")]},
      {taskId: ($dispatchId + "-03"), role: "entity_matcher", title: "资源关系合同与授权", assignedTo: $em, dependsOn: [($dispatchId + "-01")]},
      {taskId: ($dispatchId + "-04"), role: "approval_guard", title: "观众沟通与执行门禁", assignedTo: $ag, dependsOn: [($dispatchId + "-02"), ($dispatchId + "-03")]}
    ]
  }' > /tmp/project-envelope.json
jq -c '{schema, dispatchId, roomId, publicWriteAllowed, taskCount: (.tasks|length)}' /tmp/project-envelope.json

echo "=== [4/6] 组装消息（含 Leader mention） ==="
jq -n \
  --arg line "JUCHANG_DSH_PROJECT: $(jq -c . /tmp/project-envelope.json)" \
  --arg leader "$LEADER_ID" \
  '{
    msgtype: "m.text",
    body: ("据场危机处置 · 云端权威派单\n\n" + $leader + " 请接收本项目派单。四岗按 DAG 执行：事实→（可行性∥权责）→门禁；禁止批准/退款/发布/外联/写生产。全部停在人工复核。\n\n" + $line),
    "m.mentions": {user_ids: [$leader]}
  }' > /tmp/project-message.json
jq -r '.body[:120] + "…"' /tmp/project-message.json

echo "=== [5/6] 经 Matrix API 以 admin 身份发送 ==="
docker cp /tmp/project-message.json $C:/tmp/project-message.json
docker cp /tmp/project-envelope.json $C:/tmp/project-envelope.json
docker exec $C sh -c "
  P=\$(jq -cn --arg u admin --arg p \"\$AGENTTEAMS_ADMIN_PASSWORD\" '{type:\"m.login.password\",identifier:{type:\"m.id.user\",user:\$u},password:\$p}')
  T=\$(curl -s -X POST -H 'Content-Type: application/json' -d \"\$P\" '$MATRIX_URL/_matrix/client/v3/login' | jq -r '.access_token // empty')
  [ -z \"\$T\" ] && { echo 'ADMIN_LOGIN_FAIL'; exit 1; }
  ROOM_ENC=\$(jq -rn --arg r '$ROOM' '\$r|@uri')
  curl -s -X PUT -H \"Authorization: Bearer \$T\" -H 'Content-Type: application/json' -d @/tmp/project-message.json \"$MATRIX_URL/_matrix/client/v3/rooms/\$ROOM_ENC/send/m.room.message/\$(date +%s%N)\" | jq -r 'if .event_id then \"PROJECT_DISPATCH_SENT event=\" + .event_id else \"SEND_FAIL\" end'
  curl -s -X POST -H \"Authorization: Bearer \$T\" '$MATRIX_URL/_matrix/client/v3/logout' >/dev/null 2>&1 || true
"

echo "=== [6/6] 观察指引 ==="
echo "发送后 Leader 会创建项目并委派四岗。观察：bash <(curl -sL $BRIDGE/watch-run.sh)"
echo "latest_project 应为 $DISPATCH_ID；四份 receipt 落盘后跑 collect-evidence.sh 回收。"
