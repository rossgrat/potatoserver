import fs from 'node:fs';
import { DatabaseSync, backup } from 'node:sqlite';

process.umask(0o077);
const backupRoot = `${process.argv[2]}/root`;
const databaseDirectory = `${backupRoot}/var/lib/rancher/k3s/server/db`;
fs.mkdirSync(databaseDirectory, { recursive: true });
const sourceDatabase = new DatabaseSync('/var/lib/rancher/k3s/server/db/state.db', {
  readOnly: true,
});
await backup(sourceDatabase, `${databaseDirectory}/state.db`);
sourceDatabase.close();
const backupDatabase = new DatabaseSync(`${databaseDirectory}/state.db`, { readOnly: true });
if (backupDatabase.prepare('PRAGMA integrity_check').get().integrity_check !== 'ok') {
  throw new Error('Cluster database integrity failed');
}
if (!backupDatabase.prepare('SELECT count(*) AS count FROM kine').get().count) {
  throw new Error('Cluster database is empty');
}
backupDatabase.close();
const tokenPath = '/var/lib/rancher/k3s/server/token';
if (!fs.statSync(tokenPath).size) {
  throw new Error('Server token is empty');
}
fs.copyFileSync(tokenPath, `${backupRoot}/var/lib/rancher/k3s/server/token`);
fs.cpSync('/etc/rancher/k3s', `${backupRoot}/etc/rancher/k3s`, { recursive: true });
console.log('Consistent cluster database, token, and configuration backup PASS');
