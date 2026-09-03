#!/usr/bin/env bash
# goai-crisis-cloud-bridge · 云端运行证据回收（运行结束后执行）
# 把 juchang-cloud-runtime-evidence.json / receipt / audit 从 leader 容器共享目录拷到 /workspace/cloud-evidence/，
# 然后在 IDE 文件树里右键下载这三个文件到本地仓库 output/crisis-sim/ 即可完成回收。
set -uo pipefail
LEAD=agentteams-worker-juchang-v14-lead
OUT=/workspace/cloud-evidence

echo "=== [1/4] 在 leader 容器定位证据 ==="
SHARED=$(docker exec $LEAD sh -c 'printf %s "$AGENTTEAMS_SHARED_DIR"')
echo "shared_dir=$SHARED"
docker exec $LEAD sh -c "ls -t '$SHARED'/projects/ 2>/dev/null | head -5"
PROJ=$(docker exec $LEAD sh -c "ls -t '$SHARED'/projects/ 2>/dev/null | head -1")
echo "latest_project=$PROJ"
if [ -z "$PROJ" ]; then echo "FAIL: 还没有项目目录——运行可能还在进行，等几分钟再跑"; exit 1; fi

echo "=== [2/4] 检查关键证据文件 ==="
docker exec $LEAD sh -c "ls -la '$SHARED'/projects/'$PROJ'/workspace/ 2>/dev/null | grep -E 'runtime-evidence|receipt|audit'"
EVIDENCE_OK=$(docker exec $LEAD sh -c "test -f '$SHARED'/projects/'$PROJ'/workspace/juchang-cloud-runtime-evidence.json && echo yes || echo no")
echo "runtime_evidence_present=$EVIDENCE_OK"
if [ "$EVIDENCE_OK" != "yes" ]; then
  echo "运行未收口（或未到 evidence 生成阶段）。若 Leader 聊天里已报 READY_FOR_HUMAN_REVIEW 但缺文件，截图发我。"
  exit 1
fi

echo "=== [3/4] 拷贝到 /workspace/cloud-evidence/ ==="
mkdir -p "$OUT"
docker cp "$LEAD:$SHARED/projects/$PROJ/workspace/juchang-cloud-runtime-evidence.json" "$OUT/runtime-evidence.json"
docker cp "$LEAD:$SHARED/projects/$PROJ/workspace/juchang-cloud-receipt.json" "$OUT/cloud-receipt.json" 2>/dev/null || true
docker cp "$LEAD:$SHARED/projects/$PROJ/workspace/juchang-cloud-audit.json" "$OUT/cloud-audit.json" 2>/dev/null || true
docker cp "$LEAD:$SHARED/projects/$PROJ/workspace/human-decision-brief.md" "$OUT/human-decision-brief.md" 2>/dev/null || true
ls -la "$OUT"

echo "=== [4/4] 本地校验指引 ==="
echo "在 IDE 左侧文件树找到 cloud-evidence/ 目录，逐个右键 → 下载，放到本地仓库 output/crisis-sim/ 下，然后告诉我『证据已下载』。"
echo "我会用 export-verified-replay.mjs 冻结第三份（云端权威）Verified Replay。"
echo "=== COLLECT_DONE ==="
