import fs from 'node:fs';

const containers = JSON.parse(fs.readFileSync('/evidence/containers.json'));
const environment = name => Object.fromEntries(containers.find(item => item.Name === `/${name}`).Config.Env.map(value => {
  const separator = value.indexOf('=');
  return [value.slice(0, separator), value.slice(separator + 1)];
}));
for (const [name, container, keys] of [
  ['database', 'umami-postgres-1', ['POSTGRES_USER', 'POSTGRES_PASSWORD', 'POSTGRES_DB']],
  ['application', 'umami', ['DATABASE_URL', 'APP_SECRET', 'TWO_FACTOR_ENCRYPTION_KEY', 'PRIVATE_MODE', 'DISABLE_TELEMETRY']],
]) {
  const values = environment(container);
  const stringData = Object.fromEntries(keys.map(key => {
    if (!values[key]) throw new Error(`Missing ${key}`);
    return [key, values[key]];
  }));
  fs.writeFileSync(`/evidence/${name}-secret.json`, JSON.stringify({
    apiVersion: 'v1', kind: 'Secret', metadata: { name, namespace: 'umami' }, type: 'Opaque', stringData,
  }), { mode: 0o600 });
}
