import fs from 'node:fs';
import { DatabaseSync, backup } from 'node:sqlite';

process.umask(0o077);
const root = `${process.argv[2]}/root`;
const databaseDirectory = `${root}/var/lib/rancher/k3s/server/db`;
fs.mkdirSync(databaseDirectory, { recursive: true });
const source = new DatabaseSync('/var/lib/rancher/k3s/server/db/state.db', { readOnly: true });
await backup(source, `${databaseDirectory}/state.db`);
source.close();
const restored = new DatabaseSync(`${databaseDirectory}/state.db`, { readOnly: true });
if (restored.prepare('PRAGMA integrity_check').get().integrity_check !== 'ok') throw new Error('Cluster database integrity failed');
if (!restored.prepare('SELECT count(*) AS count FROM kine').get().count) throw new Error('Cluster database is empty');
restored.close();
const token = '/var/lib/rancher/k3s/server/token';
if (!fs.statSync(token).size) throw new Error('Server token is empty');
fs.copyFileSync(token, `${root}/var/lib/rancher/k3s/server/token`);
fs.cpSync('/etc/rancher/k3s', `${root}/etc/rancher/k3s`, { recursive: true });
console.log('Consistent cluster database, token, and configuration backup PASS');
