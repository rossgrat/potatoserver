import fs from 'node:fs';
import { createRequire } from 'node:module';

const session = JSON.parse(fs.readFileSync('/evidence/source-session.json'));
const { stringData: application } = JSON.parse(fs.readFileSync('/evidence/application-secret.json'));
if (!session.token || session.accountId !== application.ALLOWED_GITHUB_USER_ID) throw new Error('No valid owner session');
const load = createRequire(import.meta.resolve('better-auth/cookies'));
const { serializeSignedCookie } = load('better-call');
const cookie = await serializeSignedCookie('__Secure-better-auth.session_token', session.token, application.BETTER_AUTH_SECRET, {
  secure: true, httpOnly: true, sameSite: 'lax', path: '/',
});
fs.writeFileSync('/evidence/http-auth.json', JSON.stringify({ cookie: cookie.split(';', 1)[0], userId: session.userId }), { mode: 0o600 });
console.log('Existing CMS owner session prepared on server');
