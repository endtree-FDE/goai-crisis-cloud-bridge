#!/usr/bin/env bash
# goai-crisis-cloud-bridge · 一键武装租约（自动定位迁移包，不依赖固定路径）
set -uo pipefail
cd /workspace 2>/dev/null || cd ~

LEASE=$(find /workspace /root /home -name 'dispatch-lifecycle-lease.sh' -type f 2>/dev/null | head -1)
if [ -z "$LEASE" ]; then
  echo "ERROR: dispatch-lifecycle-lease.sh not found in /workspace /root /home"
  echo "Hint: run 'find / -name dispatch-lifecycle-lease.sh 2>/dev/null | head' and paste output"
  exit 1
fi
echo "LEASE=$LEASE"
cd "$(dirname "$LEASE")" || exit 1
echo "CWD=$(pwd)"
bash dispatch-lifecycle-lease.sh arm 1800
