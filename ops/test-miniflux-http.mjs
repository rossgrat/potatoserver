import fs from 'node:fs';

const base = process.argv[2];
const { username, password } = JSON.parse(fs.readFileSync('/evidence/http-auth.json'));
if (!username || !password) throw new Error('Saved HTTP credentials are missing');
const request = (path, authorization) => fetch(new URL(path, base), {
  headers: authorization ? { Authorization: authorization } : {},
  redirect: 'manual', signal: AbortSignal.timeout(10000),
});
const health = await request('/healthcheck');
if (health.status !== 200) throw new Error(`Health returned HTTP ${health.status}`);
const authorization = `Basic ${Buffer.from(`${username}:${password}`).toString('base64')}`;
const me = await request('/v1/me', authorization);
if (me.status !== 200) throw new Error(`Authentication returned HTTP ${me.status}`);
const account = await me.json();
if (account.username !== username || !Number.isInteger(account.id)) throw new Error('Account identity differs');
const feeds = await request('/v1/feeds', authorization);
if (feeds.status !== 200 || !Array.isArray(await feeds.json())) throw new Error('Feed listing failed');
const invalid = await request('/v1/me', `Basic ${Buffer.from(`${username}:k3s-deliberately-incorrect`).toString('base64')}`);
if (invalid.status !== 401) throw new Error(`Invalid credentials returned HTTP ${invalid.status}`);
console.log('Health, saved account, feed listing, and invalid-password rejection PASS');
