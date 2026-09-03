import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import crypto from 'node:crypto';
import { correctedEnvelope, repairOnce, OLD_ID, NEW_ID, TEAM } from './repair-room-once.mjs';

function setup() {
  const roles = ['material_intake', 'evidence_guard', 'entity_matcher', 'approval_guard'];
  const dep = [[], [0], [0], [1, 2]];
  const team = { name: TEAM, phase: 'Active', leaderReady: true, readyWorkers: 4,
    teamRoomID: '!team:test', leaderDMRoomID: '!dm:test', leaderName: 'lead' };
  const snapshot = {
    request: { schema: 'juchang-agentteams-dsh-project@1', projectId: OLD_ID,
      projectRef: 'zhuantang-yixun', title: 'Synthetic rehearsal', intakeKind: 'retrospective',
      roomId: '!dm:test', publicWriteAllowed: false, inputPayload: { synthetic: true, facts: ['original'] },
      tasks: roles.map((role, i) => ({ role, taskId: `${OLD_ID}-0${i + 1}`, title: role,
        assignedTo: `@${role}:test`, dependsOn: dep[i].map(j => `${OLD_ID}-0${j + 1}`) })) },
    audit: { events: [{ operation: 'create_project', success: true }, { operation: 'plan_dag', success: true }] },
    failure: { message: 'assignee @material_intake:test is not a joined member of room !dm:test' },
  };
  const calls = [];
  let paused = false;
  let claimed = false;
  const io = {
    senderId: '@admin:test',
    team: async () => team,
    leader: async () => '@lead:test',
    members: async room => room === '!team:test' ? ['@lead:test', ...roles.map(x => `@${x}:test`)] : ['@lead:test', '@admin:test'],
    project: async id => id === NEW_ID ? null : { status: paused ? 'paused' : 'active', nodes: snapshot.request.tasks.map(t => ({ id: t.taskId, status: 'pending' })) },
    claim: () => { assert.equal(claimed, false, 'duplicate claim'); claimed = true; calls.push('claim'); },
    pause: async id => { assert.equal(id, OLD_ID); paused = true; calls.push('pause'); },
    record: (name, value) => { calls.push(['record', name, value]); },
    send: async (room, txn, body) => { calls.push(['send', room, txn, body]); return { event_id: '$event-test-1234567890' }; },
    print: () => {},
  };
  return { io, team, snapshot, calls };
}

test('envelope targets team; root message targets DM; input is unchanged', async () => {
  const f = setup(); const original = JSON.stringify(f.snapshot);
  await repairOnce(f.io, f.snapshot, true);
  const sent = f.calls.find(c => Array.isArray(c) && c[0] === 'send');
  assert.equal(sent[1], '!dm:test');
  const envelope = JSON.parse(sent[3].body.split('JUCHANG_DSH_PROJECT: ')[1]);
  assert.equal(envelope.roomId, '!team:test');
  assert.equal(envelope.dispatchId, NEW_ID);
  assert.deepEqual(envelope.inputPayload, f.snapshot.request.inputPayload);
  assert.equal(envelope.publicWriteAllowed, false);
  assert.equal(JSON.stringify(f.snapshot), original);
  assert.deepEqual(f.calls.slice(0, 2), ['claim', 'pause']);
  assert.equal(f.calls.filter(c => c[0] === 'send').length, 1);
});
test('plan mode never pauses, claims or sends', async () => {
  const f = setup(); await repairOnce(f.io, f.snapshot, false); assert.deepEqual(f.calls, []);
});
test('same DM/team fails before mutation', async () => {
  const f = setup(); f.team.teamRoomID = f.team.leaderDMRoomID;
  await assert.rejects(repairOnce(f.io, f.snapshot, true), /ROOM_REPAIR_SCOPE_MISMATCH/); assert.deepEqual(f.calls, []);
});
test('missing joined Worker stops before mutation', async () => {
  const f = setup(); f.io.members = async () => ['@lead:test'];
  await assert.rejects(repairOnce(f.io, f.snapshot, true), /TEAM_JOINED_MEMBERSHIP_FAILED/); assert.deepEqual(f.calls, []);
});
test('leader DM membership is checked', async () => {
  const f = setup(); const previous = f.io.members;
  f.io.members = async r => r === '!dm:test' ? ['@lead:test'] : previous(r);
  await assert.rejects(repairOnce(f.io, f.snapshot, true), /DM_MEMBERSHIP_FAILED/); assert.deepEqual(f.calls, []);
});
test('existing new project cannot be redispatched', async () => {
  const f = setup(); f.io.project = async () => ({ status: 'active' });
  await assert.rejects(repairOnce(f.io, f.snapshot, true), /NEW_PROJECT_ALREADY_EXISTS/); assert.deepEqual(f.calls, []);
});
test('failed pause readback prevents send', async () => {
  const f = setup(); f.io.pause = async () => f.calls.push('pause-no-effect');
  await assert.rejects(repairOnce(f.io, f.snapshot, true), /P5_PAUSE_READBACK_FAILED/);
  assert.equal(f.calls.some(c => c[0] === 'send'), false);
});
test('uncertain send is not retried and attempt stays claimed', async () => {
  const f = setup(); let attempts = 0;
  f.io.send = async () => { attempts++; throw new Error('network uncertain'); };
  await assert.rejects(repairOnce(f.io, f.snapshot, true), /network uncertain/);
  assert.equal(attempts, 1); assert.equal(f.calls[0], 'claim');
  assert.equal(f.calls.some(c => c[0] === 'record' && c[1] === 'sent.json'), false);
});
test('old run with progress is protected', async () => {
  const f = setup(); f.snapshot.audit.events.push({ operation: 'delegate_task', success: true });
  await assert.rejects(repairOnce(f.io, f.snapshot, true), /OLD_RUN_ADVANCED_STOP/); assert.deepEqual(f.calls, []);
});
test('official running task stops correction even if local audit is stale', async () => {
  const f = setup(); const previous = f.io.project;
  f.io.project = async id => { const p = await previous(id); if (p) p.nodes[0].status = 'in_progress'; return p; };
  await assert.rejects(repairOnce(f.io, f.snapshot, true), /OLD_OFFICIAL_RUN_ADVANCED_STOP/); assert.deepEqual(f.calls, []);
});
test('short assignee names cannot bypass membership', () => {
  const f = setup(); f.snapshot.request.tasks[0].assignedTo = 'material_intake';
  assert.throws(() => correctedEnvelope(f.snapshot, f.team), /FULL_ASSIGNEE_ID_REQUIRED/);
});
test('wrong old ID, DAG and production permissions fail closed', () => {
  const a = setup(); a.snapshot.request.projectId = 'other'; assert.throws(() => correctedEnvelope(a.snapshot, a.team), /OLD_REQUEST_ID_MISMATCH/);
  const b = setup(); b.snapshot.request.tasks[1].dependsOn = []; assert.throws(() => correctedEnvelope(b.snapshot, b.team), /OLD_DAG_INVALID/);
  const c = setup(); c.snapshot.request.publicWriteAllowed = true; assert.throws(() => correctedEnvelope(c.snapshot, c.team), /OLD_INPUT_OR_AUTHORITY_INVALID/);
});
test('shell pins the exact module hash and never restarts or cancels', () => {
  const shell = fs.readFileSync(new URL('./repair-room-once.sh', import.meta.url), 'utf8');
  const code = fs.readFileSync(new URL('./repair-room-once.py', import.meta.url));
  assert.ok(shell.includes(crypto.createHash('sha256').update(code).digest('hex')));
  assert.doesNotMatch(shell, /docker (?:restart|rm|stop)|agt project cancel|kill -HUP/);
  assert.match(shell, /--plan/);
  assert.match(shell, /noclobber/);
});
test('repair writes only operator records, not fake runtime evidence', async () => {
  const f = setup(); await repairOnce(f.io, f.snapshot, true);
  const records = f.calls.filter(c => c[0] === 'record');
  assert.deepEqual(records.map(c => c[1]), ['prepared-envelope.json', 'sent.json']);
  assert.equal(records[1][2].schema, 'juchang-room-repair-plan@1');
  assert.equal(records[1][2].state, 'sent_not_completed');
});
