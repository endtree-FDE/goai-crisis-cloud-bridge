#!/usr/bin/env python3
"""Bounded operator repair. Not AgentTeams runtime evidence. Stdlib only."""
import copy
import datetime
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

OLD_ID = "cloud-crisis-2014-east-art-center-p5"
NEW_ID = "cloud-crisis-2014-east-art-center-p6"
TEAM = "juchang-change-control-v14"
ROLES = ["material_intake", "evidence_guard", "entity_matcher", "approval_guard"]
DEPS = [[], [0], [0], [1, 2]]


class RepairError(Exception):
    """Only safe constant codes may reach stdout/stderr."""


def ensure(ok, code):
    if not ok:
        raise RepairError(code)


def encode(value):
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"), allow_nan=False)


def digest(value):
    return hashlib.sha256(encode(value).encode("utf-8")).hexdigest()


def now():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def corrected_envelope(snapshot, team):
    old = snapshot.get("request", {})
    ensure(old.get("schema") == "juchang-agentteams-dsh-project@1" and old.get("projectId") == OLD_ID, "OLD_REQUEST_ID_MISMATCH")
    ensure(old.get("publicWriteAllowed") is False and isinstance(old.get("inputPayload"), dict), "OLD_INPUT_OR_AUTHORITY_INVALID")
    ensure(not old.get("studio") and not old.get("failureDrill"), "UNSUPPORTED_OLD_RUN_CONTEXT")
    ensure(team.get("name") == TEAM and team.get("phase") == "Active" and team.get("leaderReady") is True and team.get("readyWorkers") == 4, "TEAM_NOT_READY")
    ensure(all(re.fullmatch(r"![^:\s]+:.+", team.get(k, "")) for k in ("teamRoomID", "leaderDMRoomID")), "ROOM_FIELDS_MISSING")
    ensure(team["teamRoomID"] != team["leaderDMRoomID"] and old.get("roomId") == team["leaderDMRoomID"], "ROOM_REPAIR_SCOPE_MISMATCH")
    message = snapshot.get("failure", {}).get("message", "")
    ensure("is not a joined member of room" in message and old["roomId"] in message, "OLD_FAILURE_MISMATCH")
    audit = snapshot.get("audit", {}).get("events", [])
    ensure(all(any(e.get("operation") == op and e.get("success") is True for e in audit) for op in ("create_project", "plan_dag")), "OLD_PLAN_NOT_OBSERVED")
    ensure(not any(e.get("operation") in ("delegate_task", "accept_task_result", "complete_project") and e.get("success") is True for e in audit), "OLD_RUN_ADVANCED_STOP")
    ensure(isinstance(old.get("tasks"), list) and len(old["tasks"]) == 4, "OLD_TASK_COUNT_INVALID")
    tasks = []
    for i, task in enumerate(old["tasks"]):
        ensure(task.get("role") == ROLES[i] and task.get("taskId") == "{}-0{}".format(OLD_ID, i + 1), "OLD_TASK_IDENTITY_INVALID")
        ensure(re.fullmatch(r"@[^:\s]+:.+", task.get("assignedTo", "")), "FULL_ASSIGNEE_ID_REQUIRED")
        ensure(task.get("dependsOn") == ["{}-0{}".format(OLD_ID, j + 1) for j in DEPS[i]], "OLD_DAG_INVALID")
        replacement = {k: task[k] for k in ("role", "title", "assignedTo") if k in task}
        replacement.update(taskId="{}-0{}".format(NEW_ID, i + 1), dependsOn=["{}-0{}".format(NEW_ID, j + 1) for j in DEPS[i]])
        tasks.append(replacement)
    envelope = {k: copy.deepcopy(old[k]) for k in ("schema", "projectRef", "title", "intakeKind", "sourceUrl", "sourceAuthor", "sourceHash", "inputPayload") if k in old}
    envelope.update(dispatchId=NEW_ID, roomId=team["teamRoomID"], publicWriteAllowed=False, tasks=tasks)
    return envelope


def repair_once(io, snapshot, apply=False):
    team = io.team()
    envelope = corrected_envelope(snapshot, team)
    leader = io.leader(team["leaderName"])
    ensure(isinstance(leader, str) and re.fullmatch(r"@[^:\s]+:.+", leader), "LEADER_ID_INVALID")
    members = set(io.members(team["teamRoomID"]))
    ensure(all(mxid in members for mxid in [leader] + [t["assignedTo"] for t in envelope["tasks"]]), "TEAM_JOINED_MEMBERSHIP_FAILED")
    dm = set(io.members(team["leaderDMRoomID"]))
    ensure(leader in dm and io.sender_id in dm, "DM_MEMBERSHIP_FAILED")
    ensure(io.project(NEW_ID, optional=True) is None, "NEW_PROJECT_ALREADY_EXISTS_NO_RESEND")
    old = io.project(OLD_ID)
    ensure(old.get("status") in ("active", "paused"), "OLD_PROJECT_STATE_UNSUPPORTED")
    nodes = old.get("nodes", old.get("tasks", []))
    ensure(isinstance(nodes, list) and len(nodes) == 4, "OLD_OFFICIAL_DAG_UNEXPECTED")
    expected = {t["taskId"] for t in snapshot["request"]["tasks"]}
    ensure({n.get("id", n.get("task_id", n.get("taskId"))) for n in nodes} == expected, "OLD_OFFICIAL_TASKS_MISMATCH")
    ensure(not any(n.get("status") in ("in_progress", "submitted", "completed") for n in nodes), "OLD_OFFICIAL_RUN_ADVANCED_STOP")
    plan = dict(schema="juchang-room-repair-plan@1", oldId=OLD_ID, newId=NEW_ID,
                roomsSeparated=True, joinedWorkers=4, payloadSha256=digest(envelope["inputPayload"]),
                envelopeSha256=digest(envelope), productionWrites=0, publicPublishes=0,
                realRefunds=0, externalBusinessMessages=0)
    io.print("PRECHECK_OK rooms_separated=true joined_workers=4")
    if not apply:
        return plan
    io.claim(plan)  # Durable exclusive marker BEFORE any mutation; never auto-repeat.
    if old["status"] != "paused":
        io.pause(OLD_ID)
    ensure(io.project(OLD_ID).get("status") == "paused", "P5_PAUSE_READBACK_FAILED")
    io.print("P5_PAUSED_READBACK_OK")
    io.record("prepared-envelope.json", envelope)
    body = {"msgtype": "m.text", "body": "JUCHANG room-corrected run. Preserve p5 failure; no business writes.\n" + leader + "\nJUCHANG_DSH_PROJECT: " + encode(envelope), "m.mentions": {"user_ids": [leader]}}
    sent = io.send(team["leaderDMRoomID"], "juchang-roomfix-" + NEW_ID + "-once", body)
    ensure(isinstance(sent.get("event_id"), str) and sent["event_id"].startswith("$"), "SEND_RESULT_UNKNOWN_DO_NOT_REPEAT")
    record = dict(plan, sentAt=now(), eventId=sent["event_id"], state="sent_not_completed", instruction="Read exact p6 Project/Taskflow; never infer completion from this record.")
    io.record("sent.json", record)
    io.print("DISPATCH_SENT project=" + NEW_ID + " event_prefix=" + sent["event_id"][:12])
    io.print("NOT_COMPLETED: wait for official four-task and Leader terminal readback.")
    return plan


def cli(args, token, optional=False):
    env = dict(os.environ, AGENTTEAMS_AUTH_TOKEN=token)
    try:
        result = subprocess.run(["agt"] + args, env=env, stdin=subprocess.DEVNULL,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                timeout=35, encoding="utf-8", errors="replace", check=False)
    except (OSError, subprocess.TimeoutExpired):
        raise RepairError("AGT_EXECUTION_FAILED") from None
    if result.returncode:
        if optional and re.search(r"HTTP 404\b", result.stderr):
            return None
        raise RepairError("AGT_" + "_".join(args[:2]).upper() + "_FAILED")
    # Official projectWrite can return plain 'ok'. Pause still requires JSON readback.
    if args[:2] == ["project", "pause"] and result.stdout.strip() == "ok":
        return {}
    try:
        return json.loads(result.stdout)
    except (TypeError, ValueError):
        raise RepairError("AGT_RESPONSE_INVALID") from None


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None  # Never forward credentials or repeat a PUT after redirects.


class ControllerIO:
    def __init__(self, state_dir):
        self.state_dir = Path(state_dir)
        self.token = ""
        self.sender_id = ""
        self.opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), NoRedirect())

    def api(self, method, endpoint, body=None, auth=True):
        headers = {"Content-Type": "application/json"}
        if auth:
            headers["Authorization"] = "Bearer " + self.token
        request = urllib.request.Request("http://127.0.0.1:6167" + endpoint,
                                         data=None if body is None else encode(body).encode("utf-8"),
                                         headers=headers, method=method)
        try:
            with self.opener.open(request, timeout=15) as response:
                return json.load(response)
        except urllib.error.HTTPError as error:
            raise RepairError("MATRIX_HTTP_" + str(error.code)) from None
        except (OSError, urllib.error.URLError):
            raise RepairError("MATRIX_REQUEST_UNCERTAIN_DO_NOT_REPEAT") from None
        except ValueError:
            raise RepairError("MATRIX_RESPONSE_INVALID") from None

    def login(self):
        password = os.environ.get("AGENTTEAMS_ADMIN_PASSWORD", "")
        ensure(bool(password), "SERVER_ADMIN_CREDENTIAL_UNAVAILABLE")
        login = self.api("POST", "/_matrix/client/v3/login", {"type": "m.login.password", "identifier": {"type": "m.id.user", "user": "admin"}, "password": password}, auth=False)
        self.token = login.get("access_token", "")
        ensure(isinstance(self.token, str) and bool(self.token), "MATRIX_LOGIN_FAILED")
        who = self.api("GET", "/_matrix/client/v3/account/whoami")
        self.sender_id = who.get("user_id", "")
        ensure(self.sender_id.startswith("@admin:"), "SENDER_NOT_ADMIN")

    def logout(self):
        if self.token:
            try:
                self.api("POST", "/_matrix/client/v3/logout", {})
            except Exception:
                self.print("SESSION_LOGOUT_UNCONFIRMED")
        self.token = ""

    def team(self):
        return cli(["get", "teams", TEAM, "-o", "json"], self.token)

    def leader(self, name):
        return cli(["get", "workers", name, "-o", "json"], self.token).get("matrixUserID")

    def members(self, room):
        data = self.api("GET", "/_matrix/client/v3/rooms/" + urllib.parse.quote(room, safe="") + "/members?membership=join")
        ensure(isinstance(data.get("chunk"), list), "MEMBERSHIP_RESPONSE_INVALID")
        return [e["state_key"] for e in data["chunk"] if e.get("type") == "m.room.member" and e.get("content", {}).get("membership") == "join"]

    def project(self, project_id, optional=False):
        return cli(["get", "projects", project_id, "-o", "json"], self.token, optional)

    def pause(self, project_id):
        return cli(["project", "pause", project_id, "--reason", "Authorized room mismatch repair; preserve p5 evidence"], self.token)

    def claim(self, value):
        self.record("attempt.json", dict(value, at=now()))

    def record(self, name, value):
        # Do not overwrite attempt, failed-run artifacts, or uncertain-send records.
        with open(self.state_dir / name, "x", encoding="utf-8") as file:
            file.write(encode(value))
            file.flush()
            os.fsync(file.fileno())

    def send(self, room, txn, body):
        endpoint = "/_matrix/client/v3/rooms/" + urllib.parse.quote(room, safe="") + "/send/m.room.message/" + urllib.parse.quote(txn, safe="")
        return self.api("PUT", endpoint, body)

    @staticmethod
    def print(line):
        print(line, flush=True)


def main(args):
    ensure(len(args) == 3 and args[0] in ("--plan", "--apply"), "USAGE_PLAN_OR_APPLY_SNAPSHOT_STATE_DIR")
    mode, snapshot_file, state_dir = args
    os.umask(0o077)
    with open(snapshot_file, encoding="utf-8") as file:
        snapshot = json.load(file)
    state = Path(state_dir)
    state.mkdir(parents=True, exist_ok=True, mode=0o700)
    ensure(mode != "--apply" or not (state / "attempt.json").exists(), "ATTEMPT_EXISTS_NO_RESEND")
    io = ControllerIO(state)
    try:
        io.login()
        repair_once(io, snapshot, mode == "--apply")
        if mode == "--apply":
            for _ in range(6):
                time.sleep(3)
                try:
                    project = io.project(NEW_ID, optional=True)
                except RepairError:
                    io.print("READBACK_UNAVAILABLE_SENT_NOT_RETRIED")
                    break
                if project is None:
                    continue
                nodes = project.get("nodes", project.get("tasks", []))
                states = [{"task": str(n.get("id", n.get("task_id", n.get("taskId", ""))))[-2:], "status": n.get("status")} for n in nodes]
                io.print("P6_OFFICIAL_READBACK " + encode({"status": project.get("status"), "tasks": states}))
                if any(n.get("status") in ("assigned", "in_progress", "submitted", "completed") for n in nodes):
                    break
    finally:
        io.logout()


if __name__ == "__main__":
    try:
        main(sys.argv[1:])
    except Exception as error:
        code = str(error) if isinstance(error, RepairError) and re.fullmatch(r"[A-Z0-9_]+", str(error)) else "LOCAL_OPERATION_FAILED"
        print("STOP: " + code, file=sys.stderr)
        sys.exit(1)
