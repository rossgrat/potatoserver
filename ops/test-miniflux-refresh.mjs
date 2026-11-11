import fs from 'node:fs';

const { username, password } = JSON.parse(fs.readFileSync('/evidence/http-auth.json'));
const id = fs.readFileSync('/evidence/refresh-feed-id.txt', 'utf8').trim();
if (!/^\d+$/.test(id)) throw new Error('No feed selected for the refresh test');
const response = await fetch(`https://rss.grattafiori.dev/v1/feeds/${id}/refresh`, {
  method: 'PUT',
  headers: { Authorization: `Basic ${Buffer.from(`${username}:${password}`).toString('base64')}` },
  signal: AbortSignal.timeout(30000),
});
if (response.status !== 204) throw new Error(`Feed refresh returned HTTP ${response.status}`);
console.log('Existing feed refresh accepted');
