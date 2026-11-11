import fs from 'node:fs';

const [backupDir, databaseName, network] = process.argv.slice(2);
const applications = {
  'miniflux-postgres-1': ['miniflux-miniflux-1', 8080, '/healthcheck'],
  'job-board-postgres': ['job-board-api', 8080, '/'],
  'wubzduh-postgres-1': ['wubzduh', 8080, '/'],
  'umami-postgres-1': ['umami', 3000, '/api/heartbeat'],
  'pages-cms-postgres-1': ['pages-cms-app-1', 3000, '/sign-in'],
};
const [name, port, path] = applications[databaseName];
const containers = JSON.parse(fs.readFileSync('/backup/containers.json', 'utf8'));
const database = containers.find(container => container.Name === `/${databaseName}`);
const password = database.Config.Env.find(value => value.startsWith('POSTGRES_PASSWORD=')).slice('POSTGRES_PASSWORD='.length);
if (password.includes('\n')) throw new Error('Database password needs a multiline-safe test transport');
fs.writeFileSync(`/backup/restore-results/${databaseName}-password.env`, `PGPASSWORD=${password}\n`, { mode: 0o600 });
const source = containers.find(container => container.Name === `/${name}`);
const environment = Object.fromEntries(source.Config.Env.map(value => {
  const index = value.indexOf('=');
  return [value.slice(0, index), value.slice(index + 1).replaceAll('$', '$$')];
}));
if (environment.DATABASE_URL) {
  const url = new URL(environment.DATABASE_URL);
  url.hostname = 'postgres';
  environment.DATABASE_URL = url.toString();
}
if (name === 'miniflux-miniflux-1') {
  environment.RUN_MIGRATIONS = '0';
  environment.CREATE_ADMIN = '0';
  environment.DISABLE_SCHEDULER_SERVICE = '1';
}
const app = {
  image: source.Image,
  pull_policy: 'never',
  entrypoint: source.Config.Entrypoint,
  command: source.Config.Cmd,
  environment,
  mem_limit: '1g',
  networks: { recovery: { aliases: ['recovery-app'] } },
};
if (name === 'wubzduh') {
  app.volumes = [`${backupDir}/restore-results/configuration/services/wubzduh/config.yaml:/app/config.yaml:ro`];
}
fs.writeFileSync(`/backup/restore-results/${databaseName}-app.json`, JSON.stringify({
  services: { app },
  networks: { recovery: { external: true, name: network } },
}), { mode: 0o600 });
fs.writeFileSync(`/backup/restore-results/${databaseName}-url.txt`, `http://recovery-app:${port}${path}`);
