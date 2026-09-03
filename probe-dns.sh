#!/usr/bin/env bash
# goai-crisis-cloud-bridge · Worker 到 controller 的名字解析侦察（只读）
set -uo pipefail
C=agentteams-controller
W=agentteams-worker-juchang-v14-material-intake
echo "=== [1] controller 当前真实 IP ==="
docker inspect $C --format '{{range $k,$v := .NetworkSettings.Networks}}{{$k}}={{$v.IPAddress}} {{end}}'
echo "=== [2] worker 内名字解析结果 ==="
docker exec $W sh -c 'getent hosts agentteams-controller || nslookup agentteams-controller 2>/dev/null | tail -4 || cat /etc/hosts | grep controller'
echo "=== [3] worker /etc/hosts 里的静态条目 ==="
docker exec $W sh -c 'grep -n "agentteams-controller" /etc/hosts || echo "(无静态条目)"'
echo "=== [4] worker 所属网络 ==="
docker inspect $W --format '{{range $k,$v := .NetworkSettings.Networks}}{{$k}} {{end}}'
echo "=== [5] controller 所属网络 ==="
docker inspect $C --format '{{range $k,$v := .NetworkSettings.Networks}}{{$k}} {{end}}'
echo "=== PROBE_DNS_DONE ==="
