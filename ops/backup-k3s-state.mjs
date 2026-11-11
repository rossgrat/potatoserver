import fs from 'node:fs';
import { DatabaseSync, backup } from 'node:sqlite';

process.umask(0o077);
const root = '/backup/root';
const databaseDirectory = `${root}/var/lib/rancher/k3s/server/db`;
fs.mkdirSync(databaseDirectory, { recursive: true });
const source = new DatabaseSync('/source/db/state.db', { readOnly: true });
await backup(source, `${databaseDirectory}/state.db`);
source.close();
const restored = new DatabaseSync(`${databaseDirectory}/state.db`, { readOnly: true });
if (restored.prepare('PRAGMA integrity_check').get().integrity_check !== 'ok') throw new Error('Cluster database integrity failed');
if (!restored.prepare('SELECT count(*) AS count FROM kine').get().count) throw new Error('Cluster database is empty');
restored.close();
if (!fs.statSync('/source/token').size) throw new Error('Server token is empty');
fs.copyFileSync('/source/token', `${root}/var/lib/rancher/k3s/server/token`);
fs.cpSync('/configuration', `${root}/etc/rancher/k3s`, { recursive: true });
console.log('Consistent cluster database, token, and configuration backup PASS');
