import { randomBytes } from 'node:crypto';

let token;
async function post(path, body) {
    const response = await fetch(`http://127.0.0.1:3000/api${path}`, {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json',
            ...(token ? { Authorization: `Bearer ${token}` } : {}),
        },
        body: JSON.stringify(body),
    });
    if (!response.ok) throw new Error(`${path}: HTTP ${response.status}`);
    return response.json();
}

const username = 'admin';
const password = randomBytes(24).toString('base64url');
const websiteId = '8bbb85d9-34c5-4d84-b595-ecce3cba7846';
({ token } = await post('/auth/login', { username, password: 'umami' }));
await post('/websites', {
    id: websiteId,
    name: "Ross Grattafiori's Blog",
    domain: 'ross.grattafiori.dev',
});
const website = await post(`/websites/${websiteId}`, {
    replayConfig: { replayEnabled: false, heatmapEnabled: false },
});
if (website.recorderEnabled) throw new Error('Recording must remain disabled');
await post('/me/password', { currentPassword: 'umami', newPassword: password });
process.stdout.write(JSON.stringify({ username, password, websiteId }) + '\n');
