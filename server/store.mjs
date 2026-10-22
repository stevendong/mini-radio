import { Database } from 'node:sqlite';
import { randomBytes, createHash, createHmac, createCipheriv, createDecipheriv } from 'node:crypto';
import { mkdirSync } from 'node:fs';
import { dirname, resolve } from 'node:path';

export const MAX_BYTES = 8 * 1024 * 1024;
export const empty = () => ({ format: 'mini-radio-library', version: 1, state: { favorites: {}, history: {} } });
export const keyHash = key => createHash('sha256').update(key).digest('hex');
const object = x => x !== null && typeof x === 'object' && !Array.isArray(x);
const text = (x, max) => typeof x === 'string' && x.length > 0 && x.length <= max;
const compare = (a, b) => a < b ? -1 : a > b ? 1 : 0;
const stream = value => {
  try {
    const u = new URL(value);
    return ['http:', 'https:'].includes(u.protocol) && !!u.hostname && !u.username && !u.password;
  } catch { return false; }
};
export function validate(document) {
  if (!object(document) || document.format !== 'mini-radio-library' || document.version !== 1
    || !object(document.state) || !object(document.state.favorites) || !object(document.state.history)) throw { status: 400 };
  for (const [kind, records] of Object.entries({ favorites: document.state.favorites, history: document.state.history })) {
    for (const [id, record] of Object.entries(records)) {
      if (!text(id, 1024) || !object(record) || !object(record.station) || record.station.stationuuid !== id
        || !text(record.revision, 1024) || !Number.isFinite(record[kind === 'favorites' ? 'modifiedAt' : 'listenedAt'])
        || (kind === 'favorites' && typeof record.removed !== 'boolean')
        || ![record.station.url_resolved, record.station.url].some(stream)) throw { status: 400 };
      // Reject ambiguous payloads and preserve exactly the fields understood by the Swift client.
      const station = record.station;
      for (const field of ['name', 'url', 'url_resolved', 'countrycode', 'state', 'language', 'tags', 'codec']) {
        if (typeof station[field] !== 'string') throw { status: 400 };
      }
      if (!Number.isSafeInteger(station.bitrate)) throw { status: 400 };
    }
  }
  if (Buffer.byteLength(JSON.stringify(document)) > MAX_BYTES) throw { status: 413 };
  return document;
}

export function merge(current, incoming) {
  const result = empty();
  for (const kind of ['favorites', 'history']) {
    const records = new Map(Object.entries(current.state[kind]));
    const time = kind === 'favorites' ? 'modifiedAt' : 'listenedAt';
    for (const [id, next] of Object.entries(incoming.state[kind])) {
      const old = records.get(id);
      if (old) {
        if (next[time] < old[time]) continue;
        if (next[time] === old[time]) {
          if (kind === 'favorites' && old.removed && !next.removed) continue;
          if ((kind === 'history' || next.removed === old.removed) && compare(next.revision, old.revision) <= 0) continue;
        }
      }
      records.set(id, next);
    }
    const entries = [...records];
    if (kind === 'history') entries.sort((a, b) => b[1].listenedAt - a[1].listenedAt || compare(a[0], b[0]));
    result.state[kind] = Object.fromEntries(kind === 'history' ? entries.slice(0, 50) : entries);
  }
  if (Buffer.byteLength(JSON.stringify(result)) > MAX_BYTES) throw { status: 413 };
  return result;
}

export class SyncStore {
  constructor({ database = ':memory:', masterKey, maxSpaces = 200, now = Date.now,
    attemptLimit = 10, issuanceLimit = 30, syncLimit = 120, syncBytes = 32 * 1024 * 1024 } = {}) {
    if (!Buffer.isBuffer(masterKey) || masterKey.length !== 32) throw new Error('A 32-byte storage key is required');
    this.key = masterKey; this.maxSpaces = maxSpaces; this.now = now;
    this.attemptLimit = attemptLimit; this.issuanceLimit = issuanceLimit;
    this.syncLimit = syncLimit; this.syncBytes = syncBytes;
    this.events = new Map(); this.nextPrune = 0;
    if (database !== ':memory:') mkdirSync(dirname(resolve(database)), { recursive: true, mode: 0o700 });
    this.db = new Database(database);
    this.db.exec(`PRAGMA journal_mode=WAL; PRAGMA synchronous=FULL; PRAGMA secure_delete=ON; PRAGMA busy_timeout=5000;
      CREATE TABLE IF NOT EXISTS spaces (id TEXT PRIMARY KEY, data BLOB, created INTEGER NOT NULL) STRICT;
      CREATE TABLE IF NOT EXISTS settings (name TEXT PRIMARY KEY, value BLOB NOT NULL) STRICT;
      CREATE TABLE IF NOT EXISTS invitations (id TEXT PRIMARY KEY, expires INTEGER NOT NULL) STRICT;
      CREATE TABLE IF NOT EXISTS budgets (name TEXT PRIMARY KEY, used INTEGER NOT NULL, until INTEGER NOT NULL) STRICT;
      CREATE INDEX IF NOT EXISTS budgets_expiry ON budgets(until);
      CREATE TABLE IF NOT EXISTS security_events (day TEXT NOT NULL, event TEXT NOT NULL, count INTEGER NOT NULL,
        PRIMARY KEY(day, event)) STRICT;`);
    // Refuse a changed storage key at startup, before accepting any writes.
    const check = this.db.prepare("SELECT value FROM settings WHERE name = 'key-check'").get();
    if (check) {
      try { this.decrypt('key-check', check.value); }
      catch (error) { this.db.close(); throw error; }
    }
    else this.db.prepare('INSERT INTO settings VALUES (?, ?)').run('key-check', this.encrypt('key-check', empty()));
  }
  encrypt(id, document) {
    const nonce = randomBytes(12), cipher = createCipheriv('aes-256-gcm', this.key, nonce);
    cipher.setAAD(Buffer.from('mini-radio-sync/v1/' + id));
    return Buffer.concat([nonce, cipher.update(JSON.stringify(document)), cipher.final(), cipher.getAuthTag()]);
  }
  decrypt(id, bytes) {
    const data = Buffer.from(bytes), decipher = createDecipheriv('aes-256-gcm', this.key, data.subarray(0, 12));
    decipher.setAAD(Buffer.from('mini-radio-sync/v1/' + id)); decipher.setAuthTag(data.subarray(-16));
    return JSON.parse(Buffer.concat([decipher.update(data.subarray(12, -16)), decipher.final()]).toString('utf8'));
  }
  create() {
    if (this.db.prepare('SELECT count(*) AS total FROM spaces').get().total >= this.maxSpaces) throw { status: 503 };
    const key = 'MR1_' + randomBytes(32).toString('base64url'), id = keyHash(key);
    this.db.prepare('INSERT INTO spaces VALUES (?, ?, ?)').run(id, this.encrypt(id, empty()), this.now());
    return key;
  }
  transaction(action) {
    this.prune();
    this.db.exec('BEGIN IMMEDIATE');
    try { const result = action(); this.db.exec('COMMIT'); return result; }
    catch (error) { this.db.exec('ROLLBACK'); throw error; }
  }
  prune() {
    const time = this.now();
    if (time < this.nextPrune) return;
    this.db.prepare('DELETE FROM budgets WHERE until <= ?').run(time);
    this.db.prepare('DELETE FROM invitations WHERE expires <= ?').run(time);
    this.nextPrune = time + 30000;
  }
  sourceID(ip) {
    return createHmac('sha256', this.key).update('mini-radio/limiter/v1:' + ip).digest('hex');
  }
  applyBudgets(specs) {
    this.prune();
    const time = this.now(), writes = [];
    for (const { name, limit, window, amount = 1, category = 'trusted:' } of specs) {
      const existing = this.db.prepare('SELECT used, until FROM budgets WHERE name = ?').get(name);
      const used = existing?.until > time ? existing.used : 0;
      if (used + amount > limit) throw { status: 429 };
      // Anonymous attempts have their own bounded namespace and cannot consume authenticated budgets.
      if (!existing && this.db.prepare('SELECT count(*) AS total FROM budgets WHERE name >= ? AND name < ?')
        .get(category, category + '~').total >= (category === 'attempt:' ? 10000 : 1000)) throw { status: 429 };
      writes.push([name, used + amount, existing?.until > time ? existing.until : time + window]);
    }
    for (const values of writes) this.db.prepare(`INSERT INTO budgets VALUES (?, ?, ?)
      ON CONFLICT(name) DO UPDATE SET used=excluded.used, until=excluded.until`).run(...values);
  }
  attemptIssuance(ip) {
    this.transaction(() => this.applyBudgets([{ name: 'attempt:' + this.sourceID(ip), category: 'attempt:',
      limit: this.attemptLimit, window: 3600000 }]));
  }
  issueInvitation(ttl = 7 * 86400000) {
    if (!Number.isSafeInteger(ttl) || ttl < 1000 || ttl > 7 * 86400000) throw new Error('Invalid invitation lifetime');
    this.prune();
    if (this.db.prepare('SELECT count(*) AS total FROM invitations').get().total >= 128) throw new Error('Invitation capacity reached');
    const code = 'MRI_' + randomBytes(32).toString('base64url'), expires = this.now() + ttl;
    this.db.prepare('INSERT INTO invitations VALUES (?, ?)').run(keyHash(code), expires);
    return { code, expires };
  }
  redeemInvitation(code, ip) {
    return this.transaction(() => {
      if (typeof code !== 'string' || !/^MRI_[A-Za-z0-9_-]{43}$/.test(code)) throw { status: 403, code: 'invitation_required' };
      const row = this.db.prepare('SELECT expires FROM invitations WHERE id = ?').get(keyHash(code));
      if (!row || row.expires <= this.now()) throw { status: 403, code: 'invitation_required' };
      // Invalid bodies and invitations never consume successful issuance quotas.
      this.applyBudgets([
        { name: 'trusted:issue:' + this.sourceID(ip), limit: 5, window: 3600000 },
        { name: 'trusted:issue:global', limit: this.issuanceLimit, window: 3600000 }
      ]);
      const key = this.create();
      this.db.prepare('DELETE FROM invitations WHERE id = ?').run(keyHash(code));
      return key;
    });
  }
  reserveSync(id, bytes) {
    this.transaction(() => this.applyBudgets([
      { name: 'trusted:sync:' + id, limit: this.syncLimit, window: 300000 },
      { name: 'trusted:bytes:' + id, limit: this.syncBytes, window: 300000, amount: bytes }
    ]));
  }
  recordEvent(event) {
    if (!['key_issued', 'invitation_rejected', 'rate_limited', 'request_rejected', 'sync_ok', 'revoked'].includes(event)) return;
    const day = new Date(this.now()).toISOString().slice(0, 10), key = day + '/' + event;
    this.events.set(key, (this.events.get(key) ?? 0) + 1);
  }
  flushEvents() {
    if (!this.events.size) return;
    this.transaction(() => {
      for (const [name, count] of this.events) {
        const [day, event] = name.split('/');
        this.db.prepare(`INSERT INTO security_events VALUES (?, ?, ?)
          ON CONFLICT(day, event) DO UPDATE SET count=count+excluded.count`).run(day, event, count);
      }
      this.db.prepare('DELETE FROM security_events WHERE day < ?')
        .run(new Date(this.now() - 7 * 86400000).toISOString().slice(0, 10));
    });
    this.events.clear();
  }
  authorized(key) {
    if (typeof key !== 'string' || !/^MR1_[A-Za-z0-9_-]{43}$/.test(key)) throw { status: 401 };
    const id = keyHash(key), row = this.db.prepare('SELECT id, length(data) AS bytes FROM spaces WHERE id = ? AND data IS NOT NULL').get(id);
    if (!row) throw { status: 401 };
    return { id, row };
  }
  sync(key, incoming) {
    // Synchronous SQLite transaction: concurrent clients always merge against the latest committed state.
    this.db.exec('BEGIN IMMEDIATE');
    try {
      const { id } = this.authorized(key);
      const row = this.db.prepare('SELECT data FROM spaces WHERE id = ?').get(id);
      const result = merge(this.decrypt(id, row.data), incoming);
      this.db.prepare('UPDATE spaces SET data = ? WHERE id = ?').run(this.encrypt(id, result), id);
      this.db.exec('COMMIT');
      return result;
    } catch (error) { this.db.exec('ROLLBACK'); throw error; }
  }
  revoke(key) {
    const { id } = this.authorized(key);
    // Keys can only be issued randomly by create(); an unknown key can never recreate a deleted space.
    this.db.prepare('DELETE FROM spaces WHERE id = ?').run(id);
    this.db.prepare("DELETE FROM budgets WHERE name IN (?, ?)").run('trusted:sync:' + id, 'trusted:bytes:' + id);
  }
  health() { this.db.prepare('SELECT 1').get(); }
  close() { try { this.flushEvents(); } finally { this.db.close(); } }
}
