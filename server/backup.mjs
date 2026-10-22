import { Database, backup } from 'node:sqlite';
import { mkdirSync, readdirSync, rmSync, statSync, chmodSync } from 'node:fs';
import { join, resolve } from 'node:path';

process.umask(0o077);
if (!process.env.SYNC_DATABASE || !process.env.SYNC_BACKUP_DIRECTORY) throw new Error('Backup configuration is required');
const folder = resolve(process.env.SYNC_BACKUP_DIRECTORY);
mkdirSync(folder, { recursive: true, mode: 0o700 });
const target = join(folder, 'sync-' + new Date().toISOString().slice(0, 10) + '.sqlite');
const source = new Database(process.env.SYNC_DATABASE, { readOnly: true });
await backup(source, target);
source.close(); chmodSync(target, 0o600);
const check = new Database(target, { readOnly: true });
const result = check.prepare('PRAGMA integrity_check').get(); check.close();
if (result.integrity_check !== 'ok') throw new Error('Backup integrity check failed');
for (const name of readdirSync(folder)) {
  if (/^sync-\d{4}-\d{2}-\d{2}\.sqlite$/.test(name) && Date.now() - statSync(join(folder, name)).mtimeMs > 7 * 86400000) {
    rmSync(join(folder, name));
  }
}
console.log('Encrypted database backup verified');
