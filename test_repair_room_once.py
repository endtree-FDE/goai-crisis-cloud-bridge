"""Offline regression tests; all identities/materials are synthetic."""
import copy
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch
import urllib.error

HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("repair_room", HERE / "repair-room-once.py")
repair = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(repair)


class Fixture:
    def __init__(self):
        self.team = dict(name=repair.TEAM, phase="Active", leaderReady=True, readyWorkers=4,
                         teamRoomID="!team:test", leaderDMRoomID="!dm:test", leaderName="lead")
        self.snapshot = dict(
            request=dict(schema="juchang-agentteams-dsh-project@1", projectId=repair.OLD_ID,
                         projectRef="zhuantang-yixun", title="Synthetic rehearsal", intakeKind="retrospective",
                         roomId="!dm:test", publicWriteAllowed=False, inputPayload={"synthetic": True, "facts": ["原始材料"]},
                         tasks=[dict(role=role, taskId="{}-0{}".format(repair.OLD_ID, i + 1), title=role,
                                     assignedTo="@" + role + ":test", dependsOn=["{}-0{}".format(repair.OLD_ID, j + 1) for j in repair.DEPS[i]]) for i, role in enumerate(repair.ROLES)]),
            audit=dict(events=[dict(operation="create_project", success=True), dict(operation="plan_dag", success=True)]),
            failure=dict(message="assignee @material_intake:test is not a joined member of room !dm:test"))
        self.calls = []
        self.paused = False
        self.claimed = False
        self.new_exists = False
        self.nodes = [dict(id=t["taskId"], status="pending") for t in self.snapshot["request"]["tasks"]]
        self.io = SimpleNamespace(sender_id="@admin:test", team=lambda: self.team, leader=lambda _: "@lead:test",
                                  members=self.members, project=self.project, claim=self.claim, pause=self.pause,
                                  record=self.record, send=self.send, print=lambda _: None)

    def members(self, room):
        return ["@lead:test"] + (["@" + r + ":test" for r in repair.ROLES] if room == "!team:test" else ["@admin:test"])

    def project(self, project_id, optional=False):
        if project_id == repair.NEW_ID:
            return {"status": "active"} if self.new_exists else None
        return {"status": "paused" if self.paused else "active", "nodes": self.nodes}

    def claim(self, value):
        if self.claimed:
            raise repair.RepairError("ATTEMPT_EXISTS_NO_RESEND")
        self.claimed = True
        self.calls.append(("claim", value))

    def pause(self, project_id):
        self.paused = True
        self.calls.append(("pause", project_id))

    def record(self, name, value):
        self.calls.append(("record", name, value))

    def send(self, room, txn, body):
        self.calls.append(("send", room, txn, body))
        return {"event_id": "$synthetic-event-id"}


class RepairTests(unittest.TestCase):
    def test_rooms_payload_and_single_send(self):
        f = Fixture()
        original = copy.deepcopy(f.snapshot)
        repair.repair_once(f.io, f.snapshot, True)
        sent = [c for c in f.calls if c[0] == "send"]
        self.assertEqual(len(sent), 1)
        self.assertEqual(sent[0][1], "!dm:test")
        body = sent[0][3]
        envelope = json.loads(body["body"].split("JUCHANG_DSH_PROJECT: ")[1])
        self.assertEqual(envelope["roomId"], "!team:test")
        self.assertEqual(envelope["dispatchId"], repair.NEW_ID)
        self.assertEqual(envelope["inputPayload"], original["request"]["inputPayload"])
        self.assertEqual(f.snapshot, original)
        self.assertIs(envelope["publicWriteAllowed"], False)
        self.assertEqual(body["m.mentions"]["user_ids"], ["@lead:test"])
        self.assertEqual([c[0] for c in f.calls[:2]], ["claim", "pause"])

    def test_plan_zero_mutations(self):
        f = Fixture()
        repair.repair_once(f.io, f.snapshot)
        self.assertEqual(f.calls, [])

    def test_bad_scope_or_membership_stops(self):
        changes = [
            (lambda f: f.team.update(teamRoomID="!dm:test"), "ROOM_REPAIR_SCOPE"),
            (lambda f: setattr(f.io, "members", lambda _: ["@lead:test"]), "TEAM_JOINED"),
            (lambda f: setattr(f.io, "members", lambda room: ["@lead:test"] if room == "!dm:test" else f.members(room)), "DM_MEMBERSHIP"),
            (lambda f: setattr(f, "new_exists", True), "NEW_PROJECT_ALREADY_EXISTS"),
            (lambda f: f.nodes[0].update(status="in_progress"), "OLD_OFFICIAL_RUN_ADVANCED"),
            (lambda f: f.nodes[0].update(id=f.nodes[1]["id"]), "OLD_OFFICIAL_TASKS_MISMATCH"),
            (lambda f: f.snapshot["audit"]["events"].append(dict(operation="delegate_task", success=True)), "OLD_RUN_ADVANCED"),
            (lambda f: f.snapshot["request"]["tasks"][0].update(assignedTo="material_intake"), "FULL_ASSIGNEE"),
            (lambda f: f.snapshot["request"]["tasks"][1].update(dependsOn=[]), "OLD_DAG_INVALID"),
            (lambda f: f.snapshot["request"].update(publicWriteAllowed=True), "OLD_INPUT_OR_AUTHORITY"),
        ]
        for change, error in changes:
            with self.subTest(error=error):
                f = Fixture()
                change(f)
                with self.assertRaisesRegex(repair.RepairError, error):
                    repair.repair_once(f.io, f.snapshot, True)
                self.assertEqual(f.calls, [])

    def test_pause_without_readback_never_sends(self):
        f = Fixture()
        f.io.pause = lambda _: None
        with self.assertRaisesRegex(repair.RepairError, "P5_PAUSE_READBACK_FAILED"):
            repair.repair_once(f.io, f.snapshot, True)
        self.assertEqual([c[0] for c in f.calls], ["claim"])

    def test_already_paused_does_not_pause_again(self):
        f = Fixture()
        f.paused = True
        repair.repair_once(f.io, f.snapshot, True)
        self.assertFalse(any(c[0] == "pause" for c in f.calls))

    def test_uncertain_send_is_single_and_claim_survives(self):
        f = Fixture()
        f.io.send = Mock(side_effect=repair.RepairError("MATRIX_REQUEST_UNCERTAIN_DO_NOT_REPEAT"))
        with self.assertRaisesRegex(repair.RepairError, "UNCERTAIN"):
            repair.repair_once(f.io, f.snapshot, True)
        self.assertEqual(f.io.send.call_count, 1)
        self.assertTrue(f.claimed)
        self.assertFalse(any(c[:2] == ("record", "sent.json") for c in f.calls))
        with self.assertRaisesRegex(repair.RepairError, "ATTEMPT_EXISTS"):
            repair.repair_once(f.io, f.snapshot, True)
        self.assertEqual(f.io.send.call_count, 1)

    def test_operator_records_not_receipts(self):
        f = Fixture()
        repair.repair_once(f.io, f.snapshot, True)
        records = [c for c in f.calls if c[0] == "record"]
        self.assertEqual([c[1] for c in records], ["prepared-envelope.json", "sent.json"])
        self.assertEqual(records[1][2]["state"], "sent_not_completed")
        self.assertEqual(records[1][2]["schema"], "juchang-room-repair-plan@1")

    def test_python_envelope_matches_existing_js_contract(self):
        f = Fixture()
        result = subprocess.run(["node", "--input-type=module", "-e",
            "import fs from 'node:fs'; import {correctedEnvelope} from './repair-room-once.mjs'; const f=JSON.parse(fs.readFileSync(0,'utf8')); console.log(JSON.stringify(correctedEnvelope(f.snapshot,f.team)));"],
            input=json.dumps(dict(snapshot=f.snapshot, team=f.team)), cwd=HERE,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, encoding="utf-8", check=True)
        self.assertEqual(repair.corrected_envelope(f.snapshot, f.team), json.loads(result.stdout))


class TransportTests(unittest.TestCase):
    def test_all_agt_calls_preserve_native_auth_never_use_matrix_token(self):
        io = repair.ControllerIO("unused")
        io.token = "SYNTHETIC_MATRIX_TOKEN"
        for native in ({"AGENTTEAMS_AUTH_TOKEN_FILE": "/synthetic/cli-token"},
                       {"AGENTTEAMS_AUTH_TOKEN": "SYNTHETIC_CONTROLLER_TOKEN"}):
            with self.subTest(native=list(native)), patch.dict(repair.os.environ, native, clear=True):
                reply = SimpleNamespace(returncode=0, stdout='{"matrixUserID":"@lead:test","status":"active"}', stderr="")
                with patch.object(repair.subprocess, "run", return_value=reply) as run:
                    io.team()
                    io.leader("lead")
                    io.project(repair.OLD_ID)
                    io.pause(repair.OLD_ID)
                self.assertEqual(run.call_count, 4)
                for args, kwargs in run.call_args_list:
                    self.assertEqual(args[0][0], "agt")
                    self.assertEqual(kwargs["env"], native)
                    self.assertNotIn(io.token, str(args) + str(kwargs))
                    self.assertEqual(kwargs["timeout"], 35)

    def test_only_real_404_means_project_absent(self):
        for code in (404, 401, 500):
            with self.subTest(code=code), patch.object(repair.subprocess, "run", return_value=SimpleNamespace(returncode=1, stdout="", stderr="HTTP " + str(code) + ": SYNTHETIC_SECRET")):
                if code == 404:
                    self.assertIsNone(repair.cli(["get", "projects", repair.NEW_ID], optional=True))
                else:
                    with self.assertRaisesRegex(repair.RepairError, "^AGT_GET_PROJECTS_HTTP_" + str(code) + "$"):
                        repair.cli(["get", "projects", repair.NEW_ID], optional=True)

    def test_team_auth_failure_retains_http_code_but_not_body(self):
        with patch.object(repair.subprocess, "run", return_value=SimpleNamespace(returncode=1, stdout="", stderr="Error: HTTP 401: SYNTHETIC_SECRET")):
            with self.assertRaisesRegex(repair.RepairError, "^AGT_GET_TEAMS_HTTP_401$"):
                repair.cli(["get", "teams", repair.TEAM, "-o", "json"])

    def test_plain_ok_pause_is_supported(self):
        with patch.object(repair.subprocess, "run", return_value=SimpleNamespace(returncode=0, stdout="ok\n", stderr="")):
            self.assertEqual(repair.cli(["project", "pause", repair.OLD_ID]), {})

    def test_network_error_single_attempt_no_secret_in_error(self):
        io = repair.ControllerIO("unused")
        io.token = "SYNTHETIC_TEST_TOKEN"
        io.opener = Mock()
        io.opener.open.side_effect = urllib.error.URLError("SYNTHETIC_SECRET")
        with self.assertRaisesRegex(repair.RepairError, "^MATRIX_REQUEST_UNCERTAIN_DO_NOT_REPEAT$"):
            io.send("!dm:test", "one", {"body": "synthetic"})
        self.assertEqual(io.opener.open.call_count, 1)
        request = io.opener.open.call_args[0][0]
        self.assertEqual(request.get_method(), "PUT")
        self.assertIn("/rooms/%21dm%3Atest/", request.full_url)

    def test_no_redirect_or_token_forwarding(self):
        handler = repair.NoRedirect()
        self.assertIsNone(handler.redirect_request(None, None, 302, "", {}, "https://example.test"))

    def test_record_is_exclusive_preserves_attempt(self):
        with tempfile.TemporaryDirectory() as directory:
            io = repair.ControllerIO(directory)
            io.claim({"synthetic": True})
            before = (Path(directory) / "attempt.json").read_bytes()
            with self.assertRaises(FileExistsError):
                io.claim({"synthetic": False})
            self.assertEqual((Path(directory) / "attempt.json").read_bytes(), before)

    def test_main_existing_attempt_stops_before_login(self):
        with tempfile.TemporaryDirectory() as directory:
            state = Path(directory)
            snapshot = state / "snapshot.json"
            snapshot.write_text(json.dumps(Fixture().snapshot), encoding="utf-8")
            (state / "attempt.json").write_text("{}", encoding="utf-8")
            with patch.object(repair.ControllerIO, "login") as login:
                with self.assertRaisesRegex(repair.RepairError, "ATTEMPT_EXISTS"):
                    repair.main(["--apply", str(snapshot), directory])
                login.assert_not_called()

    def test_controller_never_invokes_node_and_probe_precedes_apply(self):
        shell = (HERE / "repair-room-once.sh").read_text(encoding="utf-8")
        self.assertNotIn('docker exec "$C" node', shell)
        self.assertIn('docker exec "$C" python3 -c', shell)
        self.assertLess(shell.index('python3 -c'), shell.index("set -o noclobber"))
        self.assertLess(shell.index('python3 -c'), shell.index("FETCH FIXED"))
        self.assertIn("CONTROLLER_PYTHON3_UNAVAILABLE_NO_PAUSE_NO_DISPATCH", shell)
        self.assertIn("exit 1", shell[shell.index('python3 -c'):shell.index("=== 1/5")])


if __name__ == "__main__":
    unittest.main(verbosity=2)
