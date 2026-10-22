import { createServer } from 'node:http';
import { readFileSync } from 'node:fs';
import { isIP } from 'node:net';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { SyncStore, MAX_BYTES, validate } from './store.mjs';
import { WindowLimiter } from './limits.mjs';

export const ISSUE_BYTES = 4096;
const normalizeIP = value => value?.replace(/^::ffff:/, '') ?? '';
const pages = new Map(['index.html', 'app.js', 'style.css'].map(name =>
  [name, readFileSync(new URL('./public/' + name, import.meta.url))]));

function readJSON(req, limit, timeout) {
  if (!/^application\/json(?:;|$)/i.test(req.headers['content-type'] ?? '')) throw { status: 415 };
  if (req.headers['content-encoding'] && req.headers['content-encoding'] !== 'identity') throw { status: 415 };
  if (Number(req.headers['content-length'] ?? 0) > limit) throw { status: 413 };
  return new Promise((resolve, reject) => {
    let size = 0, finished = false; const chunks = [];
    const finish = (error, value) => {
      if (finished) return;
      finished = true; clearTimeout(timer);
      req.off('data', data); req.off('end', end); req.off('error', failed); req.off('aborted', failed);
      if (error) { req.pause(); reject(error); } else resolve(value);
    };
    const data = chunk => { size += chunk.length; if (size > limit) finish({ status: 413 }); else chunks.push(chunk); };
    const end = () => {
      try { finish(null, JSON.parse(Buffer.concat(chunks).toString('utf8'))); }
      catch { finish({ status: 400 }); }
    };
    const failed = () => finish({ status: 400 });
    const timer = setTimeout(() => finish({ status: 408 }), timeout);
    timer.unref();
    req.on('data', data); req.once('end', end); req.once('error', failed); req.once('aborted', failed);
  });
}

export function createSyncServer({ database = ':memory:', masterKey, maxSpaces = 200, store: providedStore,
  origin = 'https://radio.myaichatbox.com', trustProxy = false, trustedProxies = [], rateLimit = 240,
  now = Date.now, creationTimeout = 5000, syncTimeout = 20000 } = {}) {
  if (trustProxy && !trustedProxies.length) throw new Error('Explicit trusted proxy addresses are required');
  const store = providedStore ?? new SyncStore({ database, masterKey, maxSpaces, now });
  const pageLimiter = new WindowLimiter({ now });
  const issueLimiter = new WindowLimiter({ now });
  const authLimiter = new WindowLimiter({ now });
  let creating = 0, syncing = 0; const activeKeys = new Set();
  const audit = setInterval(() => { try { store.flushEvents(); } catch { console.error('Security counters could not be saved'); } }, 60000);
  audit.unref();
  const source = req => {
    const peer = normalizeIP(req.socket.remoteAddress);
    if (trustProxy && trustedProxies.map(normalizeIP).includes(peer)) {
      const forwarded = req.headers['x-forwarded-for']?.split(',').at(-1)?.trim();
      if (forwarded && isIP(forwarded)) return normalizeIP(forwarded);
    }
    return peer;
  };
  const respond = (res, status, data) => {
    if (res.destroyed || res.writableEnded) return;
    const incomplete = !res.req.complete;
    res.writeHead(status, { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store',
      'X-Content-Type-Options': 'nosniff', 'Referrer-Policy': 'no-referrer',
      ...(incomplete ? { Connection: 'close' } : {}), ...(status === 429 ? { 'Retry-After': '60' } : {}) });
    // Early rejections must not drain an untrusted body or keep its connection alive.
    if (incomplete) res.once('finish', () => { const timer = setTimeout(() => res.req.destroy(), 100); timer.unref(); });
    res.end(JSON.stringify(data));
  };
  const server = createServer({ maxHeaderSize: 8192, connectionsCheckingInterval: 1000 }, async (req, res) => {
    req.on('error', () => {}); // A disconnected upload must not become an unhandled stream error.
    let pool, keyID;
    try {
      const path = req.url?.split('?')[0], ip = source(req);
      if (req.method === 'GET' && ['/', '/app.js', '/style.css', '/healthz', '/health'].includes(path)) {
        if (!pageLimiter.allow('page:' + ip, 120, 60000)) throw { status: 429 };
        if (['/healthz', '/health'].includes(path)) { store.health(); return respond(res, 200, { status: 'ok', protocol: 1 }); }
        const name = path === '/' ? 'index.html' : path.slice(1);
        res.writeHead(200, { 'Content-Type': name.endsWith('.html') ? 'text/html; charset=utf-8' : name.endsWith('.js') ? 'text/javascript; charset=utf-8' : 'text/css; charset=utf-8',
          'Cache-Control': 'no-store', 'Content-Security-Policy': "default-src 'none'; script-src 'self'; style-src 'self'; connect-src 'self'; base-uri 'none'; frame-ancestors 'none'; form-action 'self'",
          'X-Content-Type-Options': 'nosniff', 'Referrer-Policy': 'no-referrer' });
        return res.end(pages.get(name));
      }
      if (!['/v1/keys', '/v1/library/sync', '/v1/library'].includes(path)) throw { status: 404 };
      if (req.headers.origin && req.headers.origin !== origin) throw { status: 403 };
      if (path === '/v1/keys') {
        if (req.method !== 'POST') throw { status: 405 };
        if (!issueLimiter.allow('issue-attempt:' + ip, 10, 3600000) || !issueLimiter.allow('issue-global', 120, 60000)) throw { status: 429 };
        store.attemptIssuance(ip);
        if (creating >= 2) throw { status: 503, code: 'busy' };
        creating++; pool = 'create';
        const input = await readJSON(req, ISSUE_BYTES, creationTimeout);
        if (!input || Array.isArray(input) || typeof input !== 'object'
          || Object.keys(input).length !== 1 || typeof input.invitation !== 'string') throw { status: 403, code: 'invitation_required' };
        const key = store.redeemInvitation(input.invitation, ip);
        store.recordEvent('key_issued');
        return respond(res, 201, { key });
      }
      if (!authLimiter.allow('auth-attempt:' + ip, rateLimit, 300000)) throw { status: 429 };
      const key = /^Bearer (MR1_[A-Za-z0-9_-]{43})$/.exec(req.headers.authorization ?? '')?.[1];
      const { id, row } = store.authorized(key);
      if (path === '/v1/library' && req.method === 'DELETE') {
        store.revoke(key); store.recordEvent('revoked'); return respond(res, 200, { deleted: true });
      }
      if (req.method !== 'POST' || path !== '/v1/library/sync') throw { status: 405 };
      if (syncing >= 2) throw { status: 503, code: 'busy' };
      if (activeKeys.has(id)) throw { status: 429 };
      // Charge before parsing or decrypting; chunked uploads reserve the full bounded body size.
      const declared = req.headers['content-length'];
      if (declared !== undefined && Number(declared) > MAX_BYTES) throw { status: 413 };
      store.reserveSync(id, Math.max(row.bytes, declared === undefined ? MAX_BYTES : Number(declared)));
      syncing++; pool = 'sync'; keyID = id; activeKeys.add(id);
      const document = validate(await readJSON(req, MAX_BYTES, syncTimeout));
      const result = store.sync(key, document);
      store.recordEvent('sync_ok'); return respond(res, 200, result);
    } catch (error) {
      const status = error.status ?? 500;
      store.recordEvent(status === 429 ? 'rate_limited' : error.code === 'invitation_required' ? 'invitation_rejected' : 'request_rejected');
      respond(res, status, { error: error.code ?? ({ 400: 'invalid_document', 401: 'unauthorized', 403: 'forbidden',
        404: 'not_found', 405: 'method_not_allowed', 408: 'request_timeout', 413: 'too_large',
        415: 'content_type', 429: 'rate_limited', 503: 'capacity' })[status] ?? 'internal_error' });
    } finally {
      if (pool === 'create') creating--;
      if (pool === 'sync') { syncing--; activeKeys.delete(keyID); }
    }
  });
  server.requestTimeout = 30000; server.headersTimeout = 5000; server.keepAliveTimeout = 2000;
  server.maxConnections = 64; server.maxHeadersCount = 40; server.maxRequestsPerSocket = 100;
  server.setTimeout(15000, socket => socket.destroy());
  server.on('close', () => { clearInterval(audit); store.close(); });
  return server;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  process.umask(0o077);
  if (!process.env.SYNC_MASTER_KEY_FILE || !process.env.SYNC_DATABASE) throw new Error('Private storage configuration is required');
  const key = readFileSync(process.env.SYNC_MASTER_KEY_FILE);
  const server = createSyncServer({ database: process.env.SYNC_DATABASE, masterKey: key,
    maxSpaces: Number(process.env.SYNC_MAX_SPACES ?? 200), trustProxy: process.env.SYNC_TRUST_PROXY === '1',
    trustedProxies: (process.env.SYNC_TRUSTED_PROXIES ?? '').split(',').filter(Boolean) });
  server.listen(Number(process.env.PORT ?? 8788), process.env.HOST ?? '127.0.0.1', () => console.log('Mini Radio sync ready'));
  for (const signal of ['SIGINT', 'SIGTERM']) process.on(signal, () => { server.close(); server.closeIdleConnections(); });
}
