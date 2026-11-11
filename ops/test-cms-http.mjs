import fs from 'node:fs';
import http from 'node:http';
import https from 'node:https';

const [base, mode = 'basic'] = process.argv.slice(2);
const { cookie, userId } = JSON.parse(fs.readFileSync('/evidence/http-auth.json'));
const request = (path, authenticated = false) => new Promise((resolve, reject) => {
  const url = new URL(path, base);
  const client = url.protocol === 'https:' ? https : http;
  const request = client.request(url, {
    headers: { Host: 'cms.grattafiori.dev', 'X-Forwarded-Proto': 'https', ...(authenticated ? { Cookie: cookie } : {}) },
  }, response => {
    const chunks = [];
    response.on('data', chunk => chunks.push(chunk));
    response.on('error', reject);
    response.on('end', () => resolve({
      status: response.statusCode,
      json: () => {
        try { return JSON.parse(Buffer.concat(chunks).toString()); }
        catch { throw new Error('Session endpoint did not return valid JSON'); }
      },
    }));
  });
  request.setTimeout(15000, () => request.destroy(new Error('CMS request timed out')));
  request.on('error', reject);
  request.end();
});
const landing = await request('/sign-in');
if (landing.status !== 200) throw new Error(`Sign-in returned HTTP ${landing.status}`);
const response = await request('/api/auth/get-session', true);
if (response.status !== 200) throw new Error(`Existing session returned HTTP ${response.status}`);
const account = await response.json();
if (!account?.session || account.user?.id !== userId) throw new Error('Existing owner session was not preserved');
const anonymous = await request('/api/auth/get-session');
if (anonymous.status !== 200 || await anonymous.json() !== null) throw new Error('Anonymous request gained a session');
const disabled = await request('/api/auth/email-otp/send-verification-otp');
if (disabled.status !== 404) throw new Error(`Disabled email authentication returned HTTP ${disabled.status}`);
console.log('CMS sign-in, existing owner session, anonymous-session rejection, and disabled email authentication PASS');
if (mode !== 'basic') {
  const owner = account.user.githubUsername;
  if (!owner) throw new Error('The owner GitHub identity is missing');
  const repositoriesResponse = await request(`/api/repos/${encodeURIComponent(owner)}?repository_selection=selected`, true);
  if (repositoriesResponse.status !== 200) throw new Error(`Repository access returned HTTP ${repositoriesResponse.status}`);
  const repositories = await repositoriesResponse.json();
  if (repositories.status !== 'success' || !Array.isArray(repositories.data) || !repositories.data.length) throw new Error('No accessible GitHub repository');
  const identities = repositories.data.map(({ owner, repo, private: privateRepository, defaultBranch }) => ({ owner, repo, privateRepository, defaultBranch }))
    .sort((left, right) => `${left.owner}/${left.repo}`.localeCompare(`${right.owner}/${right.repo}`));
  if (mode === 'capture') {
    fs.writeFileSync('/evidence/source-repositories.json', JSON.stringify(identities), { mode: 0o600 });
  } else {
    const source = JSON.parse(fs.readFileSync('/evidence/source-repositories.json'));
    if (JSON.stringify(source) !== JSON.stringify(identities)) throw new Error('Accessible GitHub repositories differ');
  }
  console.log('Authenticated GitHub repository access PASS');
}
