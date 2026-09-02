#!/usr/bin/env bash
# goai-crisis-cloud-bridge · 云端只读探针（第一轮：不写、不发、不改任何状态）
set -uo pipefail
cd /workspace 2>/dev/null || cd ~
echo "=== [1/5] workspace runtime dirs ==="
ls -d agentteams-dsh-runtime-* AgentTeams-* dispatch-* fresh-run-* fresh0028-* competition 2>/dev/null | head -30
echo "=== [2/5] agt cli ==="
command -v agt && agt --version 2>&1 | head -3
echo "=== [3/5] team readiness ==="
agt get teams juchang-change-control-v14 2>&1 | head -40
echo "=== [4/5] containers ==="
docker ps --format '{{.Names}} | {{.Status}}' 2>/dev/null | head -20
echo "=== [5/5] env presence (counts only, no values) ==="
env | grep -c '^AGENTTEAMS_' || true
echo "=== BRIDGE_PROBE_DONE ==="
