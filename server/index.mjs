import { createServer } from 'node:http';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { SyncStore, MAX_BYTES, validate } from './store.mjs';

const site = name => readFileSync(new URL('./public/' + name, import.meta.url));
export function createSyncServer({ database = ':memory:', masterKey, maxSpaces = 200,
  origin = 'https://radio.myaichatbox.com', trustProxy = false, rateLimit = 240, now = Date.now } = {}) {
  const store = new SyncStore({ database, masterKey, maxSpaces });
  const limits = new Map(); let inFlight = 0;
  const allow = (key, limit, window) => {
    const time = now();
    if (limits.size > 10000) for (const [k, v] of limits) if (v.until <= time) limits.delete(k);
    if (!limits.has(key) && limits.size >= 10000) return false;
    let value = limits.get(key);
    if (!value || value.until <= time) { value = { until: time + window, count: 0 }; limits.set(key, value); }
    return ++value.count <= limit;
  };
  const respond = (res, status, data) => {
    res.writeHead(status, { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store',
      'X-Content-Type-Options': 'nosniff', 'Referrer-Policy': 'no-referrer', ...(status === 429 ? { 'Retry-After': '300' } : {}) });
    res.end(JSON.stringify(data));
  };
  const body = async req => {
    if (!/^application\/json(?:;|$)/i.test(req.headers['content-type'] ?? '')) throw { status: 415 };
    if (Number(req.headers['content-length'] ?? 0) > MAX_BYTES) throw { status: 413 };
    let size = 0; const chunks = [];
    for await (const chunk of req) {
      size += chunk.length; if (size > MAX_BYTES) throw { status: 413 };
      chunks.push(chunk);
    }
    try { return JSON.parse(Buffer.concat(chunks).toString('utf8')); } catch { throw { status: 400 }; }
  };
  const server = createServer(async (req, res) => {
    let reading = false;
    try {
      const path = req.url?.split('?')[0];
      if (req.method === 'GET' && ['/healthz', '/health'].includes(path)) { store.health(); return respond(res, 200, { status: 'ok', protocol: 1 }); }
      if (req.method === 'GET' && ['/', '/app.js', '/style.css'].includes(path)) {
        const name = path === '/' ? 'index.html' : path.slice(1);
        res.writeHead(200, { 'Content-Type': name.endsWith('.html') ? 'text/html; charset=utf-8' : name.endsWith('.js') ? 'text/javascript; charset=utf-8' : 'text/css; charset=utf-8',
          'Cache-Control': 'no-store', 'Content-Security-Policy': "default-src 'none'; script-src 'self'; style-src 'self'; connect-src 'self'; base-uri 'none'; frame-ancestors 'none'; form-action 'self'",
          'X-Content-Type-Options': 'nosniff', 'Referrer-Policy': 'no-referrer' });
        return res.end(site(name));
      }
      if (!['/v1/keys', '/v1/library/sync', '/v1/library'].includes(path)) return respond(res, 404, { error: 'not_found' });
      if (req.headers.origin && req.headers.origin !== origin) return respond(res, 403, { error: 'origin' });
      const ip = trustProxy ? (req.headers['x-forwarded-for']?.split(',').at(-1)?.trim() ?? req.socket.remoteAddress) : req.socket.remoteAddress;
      if (!allow('request:' + ip, rateLimit, 300000)) return respond(res, 429, { error: 'rate_limited' });
      const key = req.headers.authorization?.replace(/^Bearer /, '');
      if (path !== '/v1/keys') store.authorized(key); // Reject invalid credentials before reading a potentially large body.
      if (path === '/v1/library' && req.method === 'DELETE') { store.revoke(key); return respond(res, 200, { deleted: true }); }
      if (req.method !== 'POST' || path === '/v1/library') return respond(res, 405, { error: 'method_not_allowed' });
      if (inFlight >= 2) return respond(res, 503, { error: 'busy' });
      reading = true; inFlight++;
      if (path === '/v1/keys') {
        if (!allow('create:' + ip, 5, 3600000) || !allow('create:global', 30, 3600000)) return respond(res, 429, { error: 'rate_limited' });
        const input = await body(req);
        if (!input || Object.keys(input).length) return respond(res, 400, { error: 'invalid_request' });
        return respond(res, 201, { key: store.create() });
      }
      const document = validate(await body(req));
      return respond(res, 200, store.sync(key, document));
    } catch (error) {
      // No request headers, credentials, user data, or raw exception messages are logged.
      const status = error.status ?? 500;
      respond(res, status, { error: ({ 400: 'invalid_document', 401: 'unauthorized', 413: 'too_large', 415: 'content_type', 503: 'capacity' })[status] ?? 'internal_error' });
    } finally { if (reading) inFlight--; }
  });
  server.requestTimeout = 30000; server.headersTimeout = 10000; server.keepAliveTimeout = 5000; server.maxConnections = 32;
  server.on('close', () => store.close());
  return server;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  process.umask(0o077);
  if (!process.env.SYNC_MASTER_KEY_FILE || !process.env.SYNC_DATABASE) throw new Error('Private storage configuration is required');
  const key = readFileSync(process.env.SYNC_MASTER_KEY_FILE);
  const server = createSyncServer({ database: process.env.SYNC_DATABASE, masterKey: key,
    maxSpaces: Number(process.env.SYNC_MAX_SPACES ?? 200), trustProxy: process.env.SYNC_TRUST_PROXY === '1' });
  server.listen(Number(process.env.PORT ?? 8788), process.env.HOST ?? '127.0.0.1', () => console.log('Mini Radio sync ready'));
  for (const signal of ['SIGINT', 'SIGTERM']) process.on(signal, () => { server.close(); server.closeIdleConnections(); });
}
