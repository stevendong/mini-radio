import { test } from 'node:test';
import assert from 'node:assert/strict';
import { randomBytes } from 'node:crypto';
import { mkdtempSync, rmSync, readFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { createSyncServer, ISSUE_BYTES } from './index.mjs';
import { empty, merge, MAX_BYTES, SyncStore } from './store.mjs';
import { WindowLimiter } from './limits.mjs';
import { request as httpRequest } from 'node:http';
import { setTimeout as pause } from 'node:timers/promises';

const station = id => ({ stationuuid: id, name: 'Fixture ' + id, url: 'https://example.com/' + id,
  url_resolved: '', countrycode: '', state: '', language: '', tags: '', codec: '', bitrate: 0 });
const favorite = (id, modifiedAt, removed = false, revision = 'revision-a') => ({ station: station(id), modifiedAt, removed, revision });
function document(favorites = {}, history = {}) { return { ...empty(), state: { favorites, history } }; }
async function start(options = {}) {
  const masterKey = options.masterKey ?? randomBytes(32);
  const store = new SyncStore({ ...options, masterKey });
  const server = createSyncServer({ ...options, masterKey, store });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const base = `http://127.0.0.1:${server.address().port}`;
  const request = (path, key, body, method = 'POST', extra = {}) => fetch(base + path, {
    method, headers: { 'Content-Type': 'application/json', ...(key ? { Authorization: 'Bearer ' + key } : {}), ...extra },
    ...(body === undefined ? {} : { body: JSON.stringify(body) })
  });
  return { base, request, masterKey, store,
    invite: (ttl) => store.issueInvitation(ttl).code,
    create: async () => {
      const response = await request('/v1/keys', undefined, { invitation: store.issueInvitation().code });
      assert.equal(response.status, 201); return (await response.json()).key;
    },
    sync: (key, body) => request('/v1/library/sync', key, body),
    close: () => new Promise(resolve => { server.close(resolve); server.closeAllConnections(); }) };
}
test('two devices merge additions, removals, stale replay and histories exactly as Swift', async () => {
  const app = await start();
  try {
    const key = await app.create();
    assert.match(key, /^MR1_[A-Za-z0-9_-]{43}$/);
    const a = document({ jazz: favorite('jazz', 10.123) });
    assert.deepEqual(await (await app.sync(key, a)).json(), a);
    const b = document({ news: favorite('news', 20), jazz: favorite('jazz', 30, true) });
    const merged = await (await app.sync(key, b)).json();
    assert.deepEqual(merged, merge(a, b));
    assert.equal((await (await app.sync(key, a)).json()).state.favorites.jazz.removed, true);
    const history = Object.fromEntries(Array.from({ length: 70 }, (_, n) => [String(n), { station: station(String(n)), listenedAt: n, revision: 'event-' + n }]));
    const response = await app.sync(key, document({}, history));
    assert.equal(response.status, 200);
    const state = (await response.json()).state;
    assert.equal(Object.keys(state.history).length, 50);
    assert.ok(state.history['69']); assert.ok(!state.history['19']);
    assert.equal(response.headers.get('Cache-Control'), 'no-store');
  } finally { await app.close(); }
});
test('same timestamp resolves removal before revision; history and favorite tie orders converge', () => {
  const a = document({ x: favorite('x', -978307200, false, 'z') });
  const b = document({ x: favorite('x', -978307200, true, 'a') });
  assert.deepEqual(merge(a, b), merge(b, a));
  assert.equal(merge(a, b).state.favorites.x.removed, true);
  const c = document({ x: favorite('x', -978307200, true, 'z') });
  assert.equal(merge(b, c).state.favorites.x.revision, 'z');
});
test('concurrent clients never lose additions', async () => {
  const app = await start();
  try {
    const key = await app.create();
    const responses = await Promise.all(['a', 'b'].map(id => app.sync(key, document({ [id]: favorite(id, 1) }))));
    assert.ok(responses.every(r => r.status === 200));
    const result = await (await app.sync(key, empty())).json();
    assert.deepEqual(Object.keys(result.state.favorites).sort(), ['a', 'b']);
  } finally { await app.close(); }
});
test('keys isolate data, unknown keys cannot register, revocation cannot be undone by old devices', async () => {
  const app = await start();
  try {
    const a = await app.create(), b = await app.create();
    await app.sync(a, document({ secret: favorite('secret', 1) }));
    assert.deepEqual(await (await app.sync(b, empty())).json(), empty());
    for (const invalid of [undefined, 'weak-password', 'MR1_' + randomBytes(32).toString('base64url')]) {
      assert.equal((await app.sync(invalid, empty())).status, 401);
    }
    assert.equal((await app.request('/v1/library', a, undefined, 'DELETE')).status, 200);
    assert.equal((await app.sync(a, empty())).status, 401);
  } finally { await app.close(); }
});
test('encrypted database survives restart; wrong master key fails closed and plaintext is absent', async () => {
  const folder = mkdtempSync(join(tmpdir(), 'radio-sync-')), database = join(folder, 'sync.sqlite');
  let app = await start({ database }); const masterKey = app.masterKey;
  try {
    const a = await app.create(), b = await app.create();
    const doc = document({ confidential: favorite('confidential', 1) });
    await app.sync(a, doc); await app.request('/v1/library', b, undefined, 'DELETE');
    await app.close();
    const backupFolder = join(folder, 'backups');
    const copied = spawnSync(process.execPath, [new URL('./backup.mjs', import.meta.url).pathname], {
      env: { ...process.env, SYNC_DATABASE: database, SYNC_BACKUP_DIRECTORY: backupFolder }
    });
    assert.equal(copied.status, 0);
    const bytes = readFileSync(database);
    assert.ok(!bytes.includes(Buffer.from('confidential'))); assert.ok(!bytes.includes(Buffer.from(a)));
    assert.throws(() => createSyncServer({ database, masterKey: randomBytes(32) }));
    const restored = join(backupFolder, 'sync-' + new Date().toISOString().slice(0, 10) + '.sqlite');
    app = await start({ database: restored, masterKey });
    assert.deepEqual(await (await app.sync(a, empty())).json(), doc);
    assert.equal((await app.sync(b, empty())).status, 401);
  } finally { await app.close(); rmSync(folder, { recursive: true }); }
});
test('malformed payloads, unsupported versions, invalid stations, size, origins and quotas', async () => {
  const app = await start({ maxSpaces: 1 });
  try {
    const key = await app.create();
    for (const bad of [{}, { ...empty(), version: 2 }, document({ wrongID: favorite('other', 1) }),
      document({ x: { ...favorite('x', 1), modifiedAt: null } }),
      document({ x: { ...favorite('x', 1), station: { ...station('x'), url: 'file:///tmp/bad' } } })]) {
      assert.equal((await app.sync(key, bad)).status, 400);
    }
    assert.equal((await app.sync(key, { oversized: 'x'.repeat(MAX_BYTES) })).status, 413);
    assert.equal((await app.request('/v1/library/sync', key, empty(), 'POST', { 'Content-Type': 'text/plain' })).status, 415);
    assert.equal((await app.request('/v1/keys', undefined, {}, 'POST', { Origin: 'https://untrusted.example' })).status, 403);
    assert.equal((await app.request('/v1/keys', undefined, { invitation: app.invite() })).status, 503);
    const health = await fetch(app.base + '/healthz'); assert.equal(health.status, 200);
  } finally { await app.close(); }
  const limited = await start({ attemptLimit: 1 });
  try {
    await limited.create();
    const response = await limited.request('/v1/keys', undefined, {});
    assert.equal(response.status, 429); assert.ok(response.headers.get('Retry-After'));
  } finally { await limited.close(); }
});

test('invitation is mandatory, single use, time bounded and atomically redeemed', async () => {
  let time = Date.now(); const app = await start({ now: () => time });
  try {
    for (const body of [{}, [], 1, { invitation: 'bad' }, { invitation: 'MRI_' + randomBytes(32).toString('base64url') }]) {
      assert.equal((await app.request('/v1/keys', undefined, body)).status, 403);
    }
    const invitation = app.invite();
    const responses = await Promise.all([1, 2].map(() => app.request('/v1/keys', undefined, { invitation })));
    assert.deepEqual(responses.map(r => r.status).sort(), [201, 403]);
    const expiring = app.invite(1000); time += 1001;
    assert.equal((await app.request('/v1/keys', undefined, { invitation: expiring })).status, 403);
    assert.equal(app.store.db.prepare('SELECT count(*) AS total FROM spaces').get().total, 1);
  } finally { await app.close(); }
});

test('anonymous slow creation requests cannot occupy sync slots; body deadline releases creation slots', async () => {
  const app = await start({ creationTimeout: 120 }); const pending = [];
  try {
    const key = await app.create();
    for (let i = 0; i < 2; i++) {
      const result = new Promise((resolve, reject) => {
        const request = httpRequest(app.base + '/v1/keys', { method: 'POST', headers: {
          'Content-Type': 'application/json', 'Content-Length': '100' } }, response => {
          response.resume(); response.on('end', () => resolve(response.statusCode));
        });
        request.on('error', reject); request.write('{');
        pending.push(request);
      });
      pending[i].result = result;
    }
    await pause(25);
    assert.equal((await app.sync(key, empty())).status, 200);
    assert.deepEqual(await Promise.all(pending.map(p => p.result)), [408, 408]);
    const issued = await app.request('/v1/keys', undefined, { invitation: app.invite() });
    assert.equal(issued.status, 201);
  } finally { for (const request of pending) request.destroy(); await app.close(); }
});

test('creation body limit applies to fixed and chunked uploads; aborted reads do not exhaust capacity', async () => {
  const app = await start();
  try {
    assert.equal((await app.request('/v1/keys', undefined, { invitation: 'x'.repeat(ISSUE_BYTES) })).status, 413);
    const status = await new Promise((resolve, reject) => {
      const request = httpRequest(app.base + '/v1/keys', { method: 'POST', headers: { 'Content-Type': 'application/json' } }, response => {
        response.resume(); response.on('end', () => resolve(response.statusCode));
      });
      request.on('error', reject); request.write('x'.repeat(ISSUE_BYTES + 1)); request.end();
    });
    assert.equal(status, 413);
    const request = httpRequest(app.base + '/v1/keys', { method: 'POST', headers: { 'Content-Type': 'application/json' } });
    request.on('error', () => {}); request.write('{'); await pause(10); request.destroy(); await pause(10);
    await app.create();
  } finally { await app.close(); }
});

test('expired network limiter entries release capacity rather than permanently refusing new clients', () => {
  let time = 0; const limiter = new WindowLimiter({ now: () => time, capacity: 10000 });
  for (let n = 0; n < 10000; n++) assert.ok(limiter.allow('source-' + n, 1, 300000));
  assert.equal(limiter.allow('new-source', 1, 300000), false);
  time = 300001;
  assert.equal(limiter.allow('new-source', 1, 300000), true);
  assert.equal(limiter.entries.size, 1);
});

test('bad invitations do not consume successful issuance budget; success quotas roll back atomically', async () => {
  const app = await start({ issuanceLimit: 1 });
  try {
    assert.equal((await app.request('/v1/keys', undefined, {})).status, 403);
    await app.create();
    const invitation = app.invite();
    assert.equal((await app.request('/v1/keys', undefined, { invitation })).status, 429);
    assert.ok(app.store.db.prepare('SELECT id FROM invitations').get());
    assert.equal(app.store.db.prepare('SELECT count(*) AS total FROM spaces').get().total, 1);
  } finally { await app.close(); }
});

test('issuance attempts and per-key budgets persist across restart without persisting raw IPs', async () => {
  const folder = mkdtempSync(join(tmpdir(), 'radio-budgets-')), database = join(folder, 'sync.sqlite');
  const masterKey = randomBytes(32); let app = await start({ database, masterKey, attemptLimit: 1, syncLimit: 1 });
  try {
    const key = await app.create();
    assert.equal((await app.sync(key, empty())).status, 200);
    await app.close(); app = await start({ database, masterKey, attemptLimit: 1, syncLimit: 1 });
    assert.equal((await app.request('/v1/keys', undefined, { invitation: app.invite() })).status, 429);
    assert.equal((await app.sync(key, empty())).status, 429);
    const names = app.store.db.prepare('SELECT name FROM budgets').all().map(row => row.name);
    assert.ok(names.every(name => !name.includes('127.0.0.1')));
    const events = app.store.db.prepare('SELECT event FROM security_events').all();
    assert.ok(events.some(row => row.event === 'key_issued'));
  } finally { await app.close(); rmSync(folder, { recursive: true }); }
});

test('only explicitly trusted proxies affect source identity and keyed traffic has its own budget', async () => {
  assert.throws(() => createSyncServer({ masterKey: randomBytes(32), trustProxy: true }));
  const app = await start({ attemptLimit: 1 });
  try {
    const key = await app.create();
    assert.equal((await app.request('/v1/keys', undefined, {}, 'POST', { 'X-Forwarded-For': '192.0.2.10' })).status, 429);
    assert.equal((await app.sync(key, empty())).status, 200);
  } finally { await app.close(); }
  const proxy = await start({ attemptLimit: 1, trustProxy: true, trustedProxies: ['127.0.0.1'] });
  try {
    for (const ip of ['192.0.2.1', '192.0.2.2']) {
      assert.equal((await proxy.request('/v1/keys', undefined, { invitation: proxy.invite() }, 'POST', { 'X-Forwarded-For': ip })).status, 201);
    }
  } finally { await proxy.close(); }
});

test('large snapshots consume per-key work budgets and cannot be repeatedly decrypted for free', async () => {
  const app = await start({ syncBytes: 800 });
  try {
    const key = await app.create(), doc = document({ station: favorite('station', 1) });
    assert.equal((await app.sync(key, doc)).status, 200);
    assert.equal((await app.sync(key, empty())).status, 200);
    assert.equal((await app.sync(key, empty())).status, 429);
  } finally { await app.close(); }
});
