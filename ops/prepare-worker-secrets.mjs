import fs from 'node:fs';
import crypto from 'node:crypto';

const [namespace, evidence] = process.argv.slice(2);
const containers = JSON.parse(fs.readFileSync(`${evidence}/containers.json`));
const environment = name => Object.fromEntries(containers.find(item => item.Name === `/${name}`).Config.Env.map(value => {
  const separator = value.indexOf('=');
  return [value.slice(0, separator), value.slice(separator + 1)];
}));
const services = {
  wubzduh: ['wubzduh-postgres-1', 'wubzduh', ['DB_USER', 'DB_PASSWORD', 'SPOTIFY_CLIENT_ID', 'SPOTIFY_CLIENT_SECRET']],
  'job-board': ['job-board-postgres', 'job-board-api', ['POSTGRES_USER', 'POSTGRES_PASSWORD', 'POSTGRES_DB', 'ANTHROPIC_API_KEY', 'AUTH_PASSWORD']],
};
const [databaseName, applicationName, applicationKeys] = services[namespace];
const database = environment(databaseName);
const application = environment(applicationName);
for (const [name, values, keys] of [
  ['database', database, ['POSTGRES_USER', 'POSTGRES_PASSWORD', 'POSTGRES_DB']],
  ['application', application, applicationKeys],
]) {
  const stringData = Object.fromEntries(keys.map(key => {
    if (!values[key]) throw new Error(`Missing ${key}`);
    return [key, values[key]];
  }));
  fs.writeFileSync(`${evidence}/${name}-secret.json`, JSON.stringify({
    apiVersion: 'v1', kind: 'Secret', metadata: { name, namespace }, type: 'Opaque', stringData,
  }), { mode: 0o600 });
}
if (namespace === 'job-board') {
  const worker = environment('job-board-worker');
  if (applicationKeys.some(key => worker[key] !== application[key])) throw new Error('API and worker credentials differ');
  const cookie = `session=${crypto.createHmac('sha256', application.AUTH_PASSWORD).update('job-board-auth').digest('hex')}`;
  fs.writeFileSync(`${evidence}/http-auth.json`, JSON.stringify({ cookie }), { mode: 0o600 });
}
