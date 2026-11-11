import fs from 'node:fs';

const containers = JSON.parse(fs.readFileSync('/evidence/containers.json'));
const environment = name => Object.fromEntries(containers.find(item => item.Name === `/${name}`).Config.Env.map(value => {
  const separator = value.indexOf('=');
  return [value.slice(0, separator), value.slice(separator + 1)];
}));
const database = environment('miniflux-postgres-1');
const application = environment('miniflux-miniflux-1');
for (const [name, values, keys] of [
  ['database', database, ['POSTGRES_USER', 'POSTGRES_PASSWORD', 'POSTGRES_DB']],
  ['application', application, ['DATABASE_URL', 'BASE_URL', 'MEDIA_PROXY_MODE']],
]) {
  const stringData = Object.fromEntries(keys.map(key => {
    if (!values[key]) throw new Error(`Missing ${key}`);
    return [key, values[key]];
  }));
  fs.writeFileSync(`/evidence/${name}-secret.json`, JSON.stringify({
    apiVersion: 'v1', kind: 'Secret', metadata: { name, namespace: 'miniflux' }, type: 'Opaque', stringData,
  }), { mode: 0o600 });
}
fs.writeFileSync('/evidence/http-auth.json', JSON.stringify({
  username: application.ADMIN_USERNAME, password: application.ADMIN_PASSWORD,
}), { mode: 0o600 });
