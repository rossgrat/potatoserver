import fs from 'node:fs';

const containers = JSON.parse(fs.readFileSync('/evidence/containers.json'));
const environment = name => Object.fromEntries(containers.find(item => item.Name === `/${name}`).Config.Env.map(value => {
  const separator = value.indexOf('=');
  return [value.slice(0, separator), value.slice(separator + 1)];
}));
const application = environment('pages-cms-app-1');
for (const [name, values, keys] of [
  ['database', environment('pages-cms-postgres-1'), ['POSTGRES_USER', 'POSTGRES_PASSWORD', 'POSTGRES_DB']],
  ['application', application, ['BASE_URL', 'DATABASE_URL', 'BETTER_AUTH_SECRET', 'CRYPTO_KEY', 'ADMIN_EMAILS', 'GITHUB_APP_ID', 'GITHUB_APP_NAME', 'GITHUB_APP_PRIVATE_KEY', 'GITHUB_APP_WEBHOOK_SECRET', 'GITHUB_APP_CLIENT_ID', 'GITHUB_APP_CLIENT_SECRET', 'ALLOWED_GITHUB_USER_ID']],
]) {
  const stringData = Object.fromEntries(keys.map(key => {
    if (values[key] === undefined) throw new Error(`Missing ${key}`);
    return [key, values[key]];
  }));
  fs.writeFileSync(`/evidence/${name}-secret.json`, JSON.stringify({
    apiVersion: 'v1', kind: 'Secret', metadata: { name, namespace: 'pages-cms' }, type: 'Opaque', stringData,
  }), { mode: 0o600 });
}
if (!/^\d+$/.test(application.ALLOWED_GITHUB_USER_ID)) throw new Error('Invalid owner identifier');
fs.writeFileSync('/evidence/session-query.sql', `SELECT row_to_json(selected) FROM (
  SELECT s.token, s.user_id AS "userId", s.expires_at AS "expiresAt", a.account_id AS "accountId"
  FROM session s JOIN account a ON a.user_id=s.user_id
  WHERE s.expires_at>now() AND a.provider_id='github' AND a.account_id='${application.ALLOWED_GITHUB_USER_ID}'
  ORDER BY s.expires_at DESC LIMIT 1
) selected;`, { mode: 0o600 });
