import fs from 'node:fs';

const { url, started, sessionId } = JSON.parse(fs.readFileSync('/evidence/collection.json'));
const { websiteId } = JSON.parse(fs.readFileSync('/evidence/http-auth.json'));
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
if (!uuid.test(sessionId) || !uuid.test(websiteId)) throw new Error('Invalid collection identifier');
if (!/^\/__k3s_migration_check__\/[0-9a-f-]{36}$/.test(url)) throw new Error('Invalid test path');
if (!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/.test(started)) throw new Error('Invalid test timestamp');
const event = `website_id='${websiteId}'::uuid AND session_id='${sessionId}'::uuid AND url_path='${url}'`;
fs.writeFileSync('/evidence/collection-check.sql', String.raw`
SELECT count(*)=1 AS event_present FROM website_event WHERE ${event} \gset
\if :event_present
\else
\quit 1
\endif
BEGIN;
DELETE FROM event_data WHERE website_event_id IN (SELECT event_id FROM website_event WHERE ${event});
DELETE FROM website_event WHERE ${event};
DELETE FROM session s WHERE session_id='${sessionId}'::uuid AND created_at>='${started}'::timestamptz
  AND NOT EXISTS (SELECT 1 FROM website_event e WHERE e.session_id=s.session_id)
  AND NOT EXISTS (SELECT 1 FROM session_data d WHERE d.session_id=s.session_id)
  AND NOT EXISTS (SELECT 1 FROM session_link l WHERE l.session_id=s.session_id);
COMMIT;
SELECT count(*)=0 AS event_removed FROM website_event WHERE ${event} \gset
\if :event_removed
\echo Synthetic page view stored and removed PASS
\else
\quit 1
\endif
`, { mode: 0o600 });
