#!/usr/bin/env bash
# Explicitly authorized p5 -> p6 room correction. No restart, invite or deletion.
set -euo pipefail
umask 077
MODE=${1:---plan}
REV=${2:-}
if [[ "$MODE" != '--plan' && "$MODE" != '--apply' ]]; then echo 'STOP: USE_PLAN_OR_APPLY'; exit 1; fi
if [[ ! "$REV" =~ ^[a-f0-9]{40}$ ]]; then echo 'STOP: EXACT_SOURCE_COMMIT_REQUIRED'; exit 1; fi
for tool in docker curl sha256sum; do command -v "$tool" >/dev/null || { echo "STOP: TOOL_MISSING_$tool"; exit 1; }; done
test -d /workspace || { echo 'STOP: EXPECTED_WORKSPACE_MISSING'; exit 1; }
C=agentteams-controller
LEAD=agentteams-worker-juchang-v14-lead
STATE=/workspace/.juchang-roomfix-p5-p6-20260903
if [[ "$MODE" == '--apply' && -e "$STATE/apply-attempt" ]]; then
  echo 'STOP: PRIOR_APPLY_ATTEMPT_EXISTS_DO_NOT_RESEND'; exit 1
fi
mkdir -p "$STATE"
WORK=$(mktemp -d /tmp/juchang-roomfix.XXXXXX)
trap 'printf "Stopped or finished. Repair records: %s\n" "$STATE"' EXIT

echo '=== 0/5 CHECK CONTROLLER INTERPRETER BEFORE ANY REPAIR ==='
if ! docker exec "$C" python3 -c 'import sys,json,urllib.request,subprocess,hashlib,pathlib,datetime; assert sys.version_info >= (3,8); print("CONTROLLER_PYTHON_STDLIB_OK")'; then
  echo 'STOP: CONTROLLER_PYTHON3_UNAVAILABLE_NO_PAUSE_NO_DISPATCH'; exit 1
fi

echo '=== 1/5 READ CURRENT CONTAINER HEALTH ==='
for role in lead material-intake evidence-guard entity-matcher approval-guard; do
  printf '%s ' "$role"
  docker exec "agentteams-worker-juchang-v14-$role" node -e '
    fetch("http://agentteams-controller:9000/minio/health/ready", {signal:AbortSignal.timeout(5000)})
    .then(r=>{console.log("minio_ready="+r.status);if(r.status!==200)process.exitCode=1})
    .catch(()=>{console.log("MINIO_UNREACHABLE");process.exitCode=1})'
done

echo '=== 2/5 PRESERVE EXACT P5 REQUEST AND FAILURE ==='
docker exec "$LEAD" node -e '
  const fs=require("node:fs"), path=require("node:path");
  const root=process.env.AGENTTEAMS_SHARED_DIR;
  if(!root)throw new Error("SHARED_DIR_MISSING");
  const dir=path.join(root,"projects","cloud-crisis-2014-east-art-center-p5","workspace");
  const read=n=>JSON.parse(fs.readFileSync(path.join(dir,n),"utf8"));
  const trace=read("skill-trace.json");
  const failure=[...(trace.records||[])].reverse().find(r=>r.skill?.id==="juchang-lifecycle-control"&&r.error)?.error;
  if(!failure?.message?.includes("is not a joined member of room"))throw new Error("P5_FAILURE_CHANGED_STOP");
  process.stdout.write(JSON.stringify({request:read("request.json"),audit:read("audit.json"),failure}));
' > "$WORK/p5-snapshot.json"
cp "$WORK/p5-snapshot.json" "$STATE/latest-preflight-p5-snapshot.json"

echo '=== 3/5 FETCH FIXED, HASH-CHECKED REPAIR MODULE ==='
curl -fsSL --max-time 30 "https://raw.githubusercontent.com/endtree-FDE/goai-crisis-cloud-bridge/$REV/repair-room-once.py" -o "$WORK/repair-room-once.py"
printf '%s  %s\n' '9199d561eb5eb0d62560895bd72e57a7aba2941de1182be0ff06e469b06fb9ef' "$WORK/repair-room-once.py" | sha256sum -c -
REMOTE="/tmp/$(basename "$WORK")"
docker cp "$WORK" "$C:/tmp/" >/dev/null

echo '=== 4/5 OFFICIAL PREFLIGHT: ROOMS, JOINED MEMBERS, P5/P6 STATES ==='
docker exec "$C" python3 "$REMOTE/repair-room-once.py" --plan "$REMOTE/p5-snapshot.json" /tmp/juchang-roomfix-p5-p6-20260903
if [[ "$MODE" == '--plan' ]]; then echo 'PLAN_ONLY_NO_PAUSE_NO_DISPATCH'; exit 0; fi

echo '=== 5/5 PAUSE P5 WITH READBACK, SEND P6 ONCE ==='
( set -o noclobber; printf 'authorized-roomfix-p5-p6\n' > "$STATE/apply-attempt" ) || { echo 'STOP: CONCURRENT_OR_PRIOR_APPLY'; exit 1; }
cp "$WORK/p5-snapshot.json" "$STATE/p5-snapshot-before-apply.json"
if docker exec "$C" python3 "$REMOTE/repair-room-once.py" --apply "$REMOTE/p5-snapshot.json" /tmp/juchang-roomfix-p5-p6-20260903; then
  docker cp "$C:/tmp/juchang-roomfix-p5-p6-20260903/sent.json" "$STATE/sent.json" >/dev/null
  echo 'REPAIR_DISPATCH_FINISHED_NOT_AGENTTEAMS_COMPLETION'
else
  echo 'STOP: APPLY_FAILED_OR_UNCERTAIN_NO_AUTOMATIC_RETRY'
  exit 1
fi
