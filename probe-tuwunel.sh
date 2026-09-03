#!/usr/bin/env bash
# goai-crisis-cloud-bridge · Tuwunel 编排方式侦察（只读）
set -uo pipefail
C=agentteams-controller
echo "=== [1] Tuwunel 进程命令行 ==="
docker exec $C sh -c 'tr "\0" " " < /proc/62/cmdline; echo'
echo "=== [2] Tuwunel 进程 CONDUWUIT_ 环境变量（名称与值—配置项非密；含密钥项只显示<set>） ==="
docker exec $C sh -c 'tr "\0" "\n" < /proc/62/environ | grep "^CONDUWUIT_" | sed -E "s/(TOKEN|SECRET|PASSWORD|KEY)=.*/\1=<set>/g"'
echo "=== [3] supervisord 配置文件 ==="
docker exec $C sh -c 'find /etc /opt /usr/local -maxdepth 4 \( -name "supervisord*.conf" -o -name "*.ini" -o -name "*.conf" \) 2>/dev/null | xargs grep -l "tuwunel" 2>/dev/null'
echo "=== [4] supervisord 中 tuwunel 段落（原文） ==="
docker exec $C sh -c 'for f in $(find /etc /opt /usr/local -maxdepth 4 \( -name "supervisord*.conf" -o -name "*.ini" -o -name "*.conf" \) 2>/dev/null | xargs grep -l "tuwunel" 2>/dev/null); do echo "--- $f ---"; grep -A 12 -i "program.*tuwunel" "$f"; done'
echo "=== PROBE_TUWUNEL_DONE ==="
