import fs from 'node:fs';

const [base, mode = 'read'] = process.argv.slice(2);
const { token } = JSON.parse(fs.readFileSync('/evidence/http-auth.json'));
const request = (path, authorization, body) => fetch(new URL(path, base), {
  method: body ? 'POST' : 'GET',
  headers: authorization ? { Authorization: authorization } : {},
  body, signal: AbortSignal.timeout(10000),
});
const health = await request('/v1/health');
if (health.status !== 200 || !(await health.json()).healthy) throw new Error('ntfy health failed');
const topic = '/k3s-isolated-recovery-test';
const authenticated = await request(`${topic}/json?poll=1`, `Bearer ${token}`);
if (authenticated.status !== 200) throw new Error(`Existing ntfy token returned HTTP ${authenticated.status}`);
for (const authorization of [undefined, 'Bearer tk_deliberately_invalid']) {
  const response = await request(`${topic}/json?poll=1`, authorization);
  if (![401, 403].includes(response.status)) throw new Error('ntfy accepted an unauthorized subscription');
}
console.log('ntfy health, existing token, anonymous rejection, and invalid token rejection PASS');
if (mode === 'isolated') {
  const password = fs.readFileSync('/evidence/test-password', 'utf8').trim();
  const authorization = `Basic ${Buffer.from(`k3s-recovery-test:${password}`).toString('base64')}`;
  const body = 'Isolated K3s recovery test';
  const response = await request(topic, authorization, body);
  if (response.status !== 200) throw new Error('Isolated test publication failed');
  const published = await response.json();
  const received = await request(`${topic}/json?poll=1`, authorization);
  const messages = (await received.text()).trim().split('\n').filter(Boolean).map(line => JSON.parse(line));
  if (!messages.some(message => message.id === published.id && message.message === body)) throw new Error('Isolated subscription missed the test message');
  console.log('Isolated test identity publication and subscription PASS');
}
