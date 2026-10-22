import { readFileSync, openSync, writeFileSync, closeSync } from 'node:fs';
import { SyncStore } from './store.mjs';

// Run locally with the service's private configuration. There is no HTTP administration endpoint.
process.umask(0o077);
let store, output;
try {
  if (!process.env.SYNC_DATABASE || !process.env.SYNC_MASTER_KEY_FILE) throw new Error('Private configuration required');
  const command = process.argv[2], args = process.argv.slice(3), options = new Map();
  for (let i = 0; i < args.length; i += 2) {
    if (!['--count', '--out', '--days'].includes(args[i]) || !args[i + 1]) throw new Error('Invalid arguments');
    options.set(args[i], args[i + 1]);
  }
  store = new SyncStore({ database: process.env.SYNC_DATABASE,
    masterKey: readFileSync(process.env.SYNC_MASTER_KEY_FILE), maxSpaces: Number(process.env.SYNC_MAX_SPACES ?? 200) });
  if (command === 'invite') {
    const count = Number(options.get('--count') ?? 1), days = Number(options.get('--days') ?? 7);
    if (!Number.isSafeInteger(count) || count < 1 || count > 20 || !Number.isFinite(days) || days <= 0 || days > 7 || !options.has('--out')) throw new Error('Invalid invitation options');
    output = openSync(options.get('--out'), 'wx', 0o600);
    const invitations = store.transaction(() => Array.from({ length: count }, () => store.issueInvitation(Math.round(days * 86400000))));
    writeFileSync(output, JSON.stringify({ invitations }, null, 2) + '\n');
    console.log('Invitations written to a private file; no credentials printed.');
  } else if (command === 'stats' && !args.length) {
    console.log(JSON.stringify({
      activeSpaces: store.db.prepare('SELECT count(*) AS total FROM spaces WHERE data IS NOT NULL').get().total,
      usableInvitations: store.db.prepare('SELECT count(*) AS total FROM invitations WHERE expires > ?').get(Date.now()).total,
      events: store.db.prepare('SELECT day, event, count FROM security_events ORDER BY day, event').all()
    }));
  } else throw new Error('Unknown command');
} catch {
  console.error('Administrative operation failed; check private configuration, arguments and output path.');
  process.exitCode = 1;
} finally {
  if (output !== undefined) closeSync(output);
  store?.close();
}
