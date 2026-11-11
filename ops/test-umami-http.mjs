import fs from 'node:fs';
import { createHash, randomUUID } from 'node:crypto';

const [base, mode = 'test'] = process.argv.slice(2);
const { username, password, websiteId } = JSON.parse(fs.readFileSync('/evidence/http-auth.json'));
if (!username || !password || !websiteId) throw new Error('Saved Umami credentials are incomplete');
const request = (path, options = {}) => fetch(new URL(path, base), {
  ...options, redirect: 'manual', signal: AbortSignal.timeout(15000),
});
const health = await request('/api/heartbeat');
if (health.status !== 200) throw new Error(`Heartbeat returned HTTP ${health.status}`);
const login = async value => request('/api/auth/login', {
  method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ username, password: value }),
});
const authenticated = await login(password);
if (authenticated.status !== 200) throw new Error(`Saved login returned HTTP ${authenticated.status}`);
const account = await authenticated.json();
if (!account.token || account.requiresTwoFactor) throw new Error('Saved login needs an interactive authentication step');
const websiteRequest = token => request(`/api/websites/${websiteId}`, { headers: { Authorization: `Bearer ${token}` } });
const websiteResponse = await websiteRequest(account.token);
if (websiteResponse.status !== 200) throw new Error(`Website returned HTTP ${websiteResponse.status}`);
const website = await websiteResponse.json();
if ((website.id ?? website.websiteId) !== websiteId) throw new Error('Website identity differs');
if (website.recorderEnabled || website.replayConfig?.replayEnabled || website.replayConfig?.heatmapEnabled) throw new Error('Recording must remain disabled');
const invalid = await login('k3s-deliberately-incorrect');
if (invalid.status !== 401) throw new Error(`Invalid password returned HTTP ${invalid.status}`);
const tracker = await request('/script.js');
if (tracker.status !== 200) throw new Error(`Tracker returned HTTP ${tracker.status}`);
const trackerDigest = createHash('sha256').update(await tracker.text()).digest('hex');
const canonical = value => {
  if (Array.isArray(value)) return value.map(canonical);
  if (value && typeof value === 'object') return Object.fromEntries(Object.keys(value).sort().map(key => [key, canonical(value[key])]));
  return value;
};
if (mode === 'capture') {
  fs.writeFileSync('/evidence/source-http.json', JSON.stringify({ account, website, trackerDigest }), { mode: 0o600 });
  console.log('Source account, website configuration, and tracker captured on server');
} else {
  const source = JSON.parse(fs.readFileSync('/evidence/source-http.json'));
  if (account.user.id !== source.account.user.id) throw new Error('Account identity differs');
  if (JSON.stringify(canonical(website)) !== JSON.stringify(canonical(source.website))) throw new Error('Website configuration differs');
  if (trackerDigest !== source.trackerDigest) throw new Error('Tracker content differs');
  const existingSession = await websiteRequest(source.account.token);
  if (existingSession.status !== 200) throw new Error(`Existing session returned HTTP ${existingSession.status}`);
  console.log('Heartbeat, saved login, existing session, website configuration, tracker, and invalid-password rejection PASS');
  if (mode === 'collect') {
    const url = `/__k3s_migration_check__/${randomUUID()}`;
    const started = new Date().toISOString();
    const response = await request('/api/send', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'User-Agent': 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
      },
      body: JSON.stringify({ type: 'event', payload: { website: websiteId, hostname: 'ross.grattafiori.dev', language: 'en-US', screen: '1920x1080', title: 'K3s migration test', url, referrer: '' } }),
    });
    if (response.status !== 200) throw new Error(`Collection returned HTTP ${response.status}`);
    const result = await response.json();
    if (!result.sessionId || !result.visitId) throw new Error('Collection did not return session identifiers');
    fs.writeFileSync('/evidence/collection.json', JSON.stringify({ url, started, ...result }), { mode: 0o600 });
    console.log('Synthetic page-view request accepted');
  }
}
