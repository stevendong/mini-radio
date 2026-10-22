import { test } from 'node:test';
import assert from 'node:assert/strict';
import { randomBytes } from 'node:crypto';
import { mkdtempSync, rmSync, readFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { createSyncServer } from './index.mjs';
import { empty, merge, MAX_BYTES } from './store.mjs';

const station = id => ({ stationuuid: id, name: 'Fixture ' + id, url: 'https://example.com/' + id,
  url_resolved: '', countrycode: '', state: '', language: '', tags: '', codec: '', bitrate: 0 });
const favorite = (id, modifiedAt, removed = false, revision = 'revision-a') => ({ station: station(id), modifiedAt, removed, revision });
function document(favorites = {}, history = {}) { return { ...empty(), state: { favorites, history } }; }
async function start(options = {}) {
  const masterKey = options.masterKey ?? randomBytes(32);
  const server = createSyncServer({ ...options, masterKey });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const base = `http://127.0.0.1:${server.address().port}`;
  const request = (path, key, body, method = 'POST', extra = {}) => fetch(base + path, {
    method, headers: { 'Content-Type': 'application/json', ...(key ? { Authorization: 'Bearer ' + key } : {}), ...extra },
    ...(body === undefined ? {} : { body: JSON.stringify(body) })
  });
  return { base, request, masterKey,
    create: async () => (await (await request('/v1/keys', undefined, {})).json()).key,
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
    assert.equal((await app.request('/v1/keys', undefined, {})).status, 503);
    const health = await fetch(app.base + '/healthz'); assert.equal(health.status, 200);
  } finally { await app.close(); }
  const limited = await start({ rateLimit: 1 });
  try {
    await limited.create();
    const response = await limited.request('/v1/keys', undefined, {});
    assert.equal(response.status, 429); assert.ok(response.headers.get('Retry-After'));
  } finally { await limited.close(); }
});
