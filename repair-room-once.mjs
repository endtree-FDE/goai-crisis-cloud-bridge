// Bounded operator repair, not AgentTeams runtime evidence.
// Only: read team/membership -> pause p5 with readback -> send one corrected p6.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { pathToFileURL } from 'node:url';

export const OLD_ID = 'cloud-crisis-2014-east-art-center-p5';
export const NEW_ID = 'cloud-crisis-2014-east-art-center-p6';
export const TEAM = 'juchang-change-control-v14';
const roles = ['material_intake', 'evidence_guard', 'entity_matcher', 'approval_guard'];
const deps = [[], [0], [0], [1, 2]];
const digest = value => crypto.createHash('sha256').update(JSON.stringify(value)).digest('hex');
const ensure = (ok, code) => { if (!ok) throw new Error(code); };

export function correctedEnvelope(snapshot, team) {
  const old = snapshot.request;
  ensure(old?.schema === 'juchang-agentteams-dsh-project@1' && old.projectId === OLD_ID, 'OLD_REQUEST_ID_MISMATCH');
  ensure(old.publicWriteAllowed === false && old.inputPayload && typeof old.inputPayload === 'object', 'OLD_INPUT_OR_AUTHORITY_INVALID');
  ensure(!old.studio && !old.failureDrill, 'UNSUPPORTED_OLD_RUN_CONTEXT');
  ensure(team.name === TEAM && team.phase === 'Active' && team.leaderReady === true && team.readyWorkers === 4, 'TEAM_NOT_READY');
  ensure(/^![^:\s]+:.+$/.test(team.teamRoomID || '') && /^![^:\s]+:.+$/.test(team.leaderDMRoomID || ''), 'ROOM_FIELDS_MISSING');
  ensure(team.teamRoomID !== team.leaderDMRoomID && old.roomId === team.leaderDMRoomID, 'ROOM_REPAIR_SCOPE_MISMATCH');
  ensure(snapshot.failure?.message?.includes('is not a joined member of room') && snapshot.failure.message.includes(old.roomId), 'OLD_FAILURE_MISMATCH');
  const audit = snapshot.audit?.events || [];
  ensure(audit.some(e => e.operation === 'create_project' && e.success === true) && audit.some(e => e.operation === 'plan_dag' && e.success === true), 'OLD_PLAN_NOT_OBSERVED');
  ensure(!audit.some(e => ['delegate_task', 'accept_task_result', 'complete_project'].includes(e.operation) && e.success === true), 'OLD_RUN_ADVANCED_STOP');
  ensure(Array.isArray(old.tasks) && old.tasks.length === 4, 'OLD_TASK_COUNT_INVALID');
  const tasks = old.tasks.map((task, i) => {
    ensure(task.role === roles[i] && task.taskId === `${OLD_ID}-0${i + 1}`, 'OLD_TASK_IDENTITY_INVALID');
    ensure(/^@[^:\s]+:.+$/.test(task.assignedTo || ''), 'FULL_ASSIGNEE_ID_REQUIRED');
    ensure(JSON.stringify(task.dependsOn) === JSON.stringify(deps[i].map(j => `${OLD_ID}-0${j + 1}`)), 'OLD_DAG_INVALID');
    return { taskId: `${NEW_ID}-0${i + 1}`, role: task.role, title: task.title, assignedTo: task.assignedTo,
      dependsOn: deps[i].map(j => `${NEW_ID}-0${j + 1}`) };
  });
  return {
    schema: old.schema, dispatchId: NEW_ID, projectRef: old.projectRef, title: old.title,
    intakeKind: old.intakeKind, sourceUrl: old.sourceUrl, sourceAuthor: old.sourceAuthor,
    sourceHash: old.sourceHash, roomId: team.teamRoomID, publicWriteAllowed: false,
    inputPayload: old.inputPayload, tasks,
  };
}

export async function repairOnce(io, snapshot, apply = false) {
  const team = await io.team();
  const envelope = correctedEnvelope(snapshot, team);
  const leader = await io.leader(team.leaderName);
  ensure(/^@[^:\s]+:.+$/.test(leader || ''), 'LEADER_ID_INVALID');
  const members = new Set(await io.members(team.teamRoomID));
  ensure([leader, ...envelope.tasks.map(t => t.assignedTo)].every(id => members.has(id)), 'TEAM_JOINED_MEMBERSHIP_FAILED');
  const dm = new Set(await io.members(team.leaderDMRoomID));
  ensure(dm.has(leader) && dm.has(io.senderId), 'DM_MEMBERSHIP_FAILED');
  ensure(await io.project(NEW_ID, true) === null, 'NEW_PROJECT_ALREADY_EXISTS_NO_RESEND');
  const old = await io.project(OLD_ID);
  ensure(['active', 'paused'].includes(old.status), 'OLD_PROJECT_STATE_UNSUPPORTED');
  const nodes = old.nodes || old.tasks || [];
  ensure(Array.isArray(nodes) && nodes.length === 4, 'OLD_OFFICIAL_DAG_UNEXPECTED');
  const expectedIds = new Set(snapshot.request.tasks.map(t => t.taskId));
  ensure(nodes.every(n => expectedIds.has(n.id || n.task_id || n.taskId)), 'OLD_OFFICIAL_TASKS_MISMATCH');
  ensure(!nodes.some(n => ['in_progress', 'submitted', 'completed'].includes(n.status)), 'OLD_OFFICIAL_RUN_ADVANCED_STOP');
  const plan = { schema: 'juchang-room-repair-plan@1', oldId: OLD_ID, newId: NEW_ID,
    roomsSeparated: true, joinedWorkers: 4, payloadSha256: digest(envelope.inputPayload),
    envelopeSha256: digest(envelope), productionWrites: 0, publicPublishes: 0, realRefunds: 0, externalBusinessMessages: 0 };
  io.print('PRECHECK_OK rooms_separated=true joined_workers=4');
  if (!apply) return plan;
  // A durable attempt marker is claimed BEFORE any mutation. Uncertain attempts never auto-repeat.
  io.claim(plan);
  if (old.status !== 'paused') await io.pause(OLD_ID);
  ensure((await io.project(OLD_ID)).status === 'paused', 'P5_PAUSE_READBACK_FAILED');
  io.print('P5_PAUSED_READBACK_OK');
  io.record('prepared-envelope.json', envelope);
  const body = {
    msgtype: 'm.text',
    body: `JUCHANG room-corrected run. Preserve p5 failure; no business writes.\n${leader}\nJUCHANG_DSH_PROJECT: ${JSON.stringify(envelope)}`,
    'm.mentions': { user_ids: [leader] },
  };
  const sent = await io.send(team.leaderDMRoomID, `juchang-roomfix-${NEW_ID}-once`, body);
  ensure(typeof sent.event_id === 'string' && sent.event_id.startsWith('$'), 'SEND_RESULT_UNKNOWN_DO_NOT_REPEAT');
  io.record('sent.json', { ...plan, sentAt: new Date().toISOString(), eventId: sent.event_id,
    state: 'sent_not_completed', instruction: 'Read exact p6 Project/Taskflow; never infer completion from this record.' });
  io.print(`DISPATCH_SENT project=${NEW_ID} event_prefix=${sent.event_id.slice(0, 12)}`);
  io.print('NOT_COMPLETED: wait for official four-task and Leader terminal readback.');
  return plan;
}

function cli(args, token, allow404 = false) {
  try {
    const out = execFileSync('agt', args, { encoding: 'utf8', timeout: 35000,
      env: { ...process.env, ...(token ? { AGENTTEAMS_AUTH_TOKEN: token } : {}) },
      stdio: ['ignore', 'pipe', 'pipe'], maxBuffer: 2 * 1024 * 1024 });
    return JSON.parse(out);
  } catch (e) {
    if (allow404 && /HTTP 404\b/.test(String(e.stderr || ''))) return null;
    throw new Error(`AGT_${args[0].toUpperCase()}_${args[1].toUpperCase()}_FAILED`);
  }
}

async function main() {
  const [mode, snapshotFile, stateDir] = process.argv.slice(2);
  ensure(['--plan', '--apply'].includes(mode) && snapshotFile && stateDir, 'USAGE_PLAN_OR_APPLY_SNAPSHOT_STATE_DIR');
  const snapshot = JSON.parse(fs.readFileSync(snapshotFile, 'utf8'));
  fs.mkdirSync(stateDir, { recursive: true, mode: 0o700 });
  if (mode === '--apply' && fs.existsSync(path.join(stateDir, 'attempt.json'))) throw new Error('ATTEMPT_EXISTS_NO_RESEND');
  const base = 'http://127.0.0.1:6167';
  let token = '';
  async function api(method, endpoint, body, auth = true) {
    let response;
    try {
      response = await fetch(base + endpoint, { method,
        headers: { 'Content-Type': 'application/json', ...(auth ? { Authorization: `Bearer ${token}` } : {}) },
        ...(body === undefined ? {} : { body: JSON.stringify(body) }), signal: AbortSignal.timeout(15000) });
    } catch { throw new Error('MATRIX_REQUEST_UNCERTAIN_DO_NOT_REPEAT'); }
    ensure(response.ok, `MATRIX_HTTP_${response.status}`);
    try { return await response.json(); } catch { throw new Error('MATRIX_RESPONSE_INVALID'); }
  }
  try {
    ensure(Boolean(process.env.AGENTTEAMS_ADMIN_PASSWORD), 'SERVER_ADMIN_CREDENTIAL_UNAVAILABLE');
    const login = await api('POST', '/_matrix/client/v3/login', { type: 'm.login.password',
      identifier: { type: 'm.id.user', user: 'admin' }, password: process.env.AGENTTEAMS_ADMIN_PASSWORD }, false);
    token = login.access_token;
    ensure(typeof token === 'string' && token.length > 0, 'MATRIX_LOGIN_FAILED');
    const who = await api('GET', '/_matrix/client/v3/account/whoami');
    ensure(/^@admin:/.test(who.user_id || ''), 'SENDER_NOT_ADMIN');
    const io = {
      senderId: who.user_id,
      team: async () => cli(['get', 'teams', TEAM, '-o', 'json'], token),
      leader: async name => cli(['get', 'workers', name, '-o', 'json'], token).matrixUserID,
      members: async room => (await api('GET', `/_matrix/client/v3/rooms/${encodeURIComponent(room)}/members?membership=join`)).chunk
        .filter(e => e.type === 'm.room.member' && e.content?.membership === 'join').map(e => e.state_key),
      project: async (id, optional = false) => cli(['get', 'projects', id, '-o', 'json'], token, optional),
      pause: async id => cli(['project', 'pause', id, '--reason', 'Authorized room mismatch repair; preserve p5 evidence'], token),
      claim: value => fs.writeFileSync(path.join(stateDir, 'attempt.json'), JSON.stringify({ ...value, at: new Date().toISOString() }), { flag: 'wx', mode: 0o600 }),
      record: (name, value) => fs.writeFileSync(path.join(stateDir, name), JSON.stringify(value, null, 2), { flag: 'wx', mode: 0o600 }),
      send: (room, txn, body) => api('PUT', `/_matrix/client/v3/rooms/${encodeURIComponent(room)}/send/m.room.message/${encodeURIComponent(txn)}`, body),
      print: line => console.log(line),
    };
    await repairOnce(io, snapshot, mode === '--apply');
    if (mode === '--apply') {
      for (let i = 0; i < 6; i++) {
        await new Promise(resolve => setTimeout(resolve, 3000));
        let project;
        try { project = await io.project(NEW_ID, true); }
        catch { console.log('READBACK_UNAVAILABLE_SENT_NOT_RETRIED'); break; }
        if (!project) continue;
        const nodes = project.nodes || project.tasks || [];
        const states = nodes.map(n => ({ task: String(n.id || n.task_id || n.taskId || '').slice(-2), status: n.status }));
        console.log('P6_OFFICIAL_READBACK ' + JSON.stringify({ status: project.status, tasks: states }));
        if (nodes.some(n => ['assigned', 'in_progress', 'submitted', 'completed'].includes(n.status))) break;
      }
    }
  } finally {
    if (token) { try { await api('POST', '/_matrix/client/v3/logout', {}); } catch { console.log('SESSION_LOGOUT_UNCONFIRMED'); } }
    token = '';
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
  main().catch(e => {
    const message = String(e.message || '');
    console.error('STOP: ' + (/^[A-Z0-9_]+$/.test(message) ? message : 'LOCAL_OPERATION_FAILED'));
    process.exitCode = 1;
  });
}
