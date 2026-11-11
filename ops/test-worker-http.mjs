import fs from 'node:fs';

const [namespace, base] = process.argv.slice(2);
const request = (path, cookie) => fetch(new URL(path, base), {
  headers: cookie ? { Cookie: cookie } : {}, redirect: 'manual', signal: AbortSignal.timeout(10000),
});
if (namespace === 'wubzduh') {
  for (const path of ['/feed/', '/artists/', '/static/style.css']) {
    const response = await request(path);
    if (response.status !== 200 || !(await response.text()).length) throw new Error(`${path} returned HTTP ${response.status}`);
  }
  console.log('Wubzduh feed, artist page, and static assets PASS');
} else if (namespace === 'job-board') {
  const { cookie } = JSON.parse(fs.readFileSync('/evidence/http-auth.json'));
  for (const path of ['/', '/browse', '/companies', '/metrics']) {
    const response = await request(path, cookie);
    if (response.status !== 200 || !(await response.text()).length) throw new Error(`${path} returned HTTP ${response.status}`);
  }
  for (const cookie of [undefined, 'session=k3s-invalid']) {
    const response = await request('/', cookie);
    if (response.status !== 302 || response.headers.get('location') !== '/login') throw new Error('Unauthenticated access was not rejected');
  }
  console.log('Job Board existing session, dashboard, browse, companies, metrics, and authentication rejection PASS');
} else {
  throw new Error('Unknown service');
}
