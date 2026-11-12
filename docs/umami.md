# Umami

Umami provides blog analytics at `https://stats.grattafiori.dev`.
The dashboard requires a login. The public `/api/send` endpoint accepts page views.
The deployment pins Umami 3.4.1 and PostgreSQL 18.6.
PostgreSQL does not publish a host port.
The application and PostgreSQL run in the K3s namespace `umami`.
Caddy forwards requests to `umami.umami.svc.cluster.local:3000`.

## Data collection

The blog sends one page view after the page loads, during browser idle time when available.
It does not load a session recorder or enable heatmaps, performance measurements, custom events, or custom visitor IDs.
Automatic tracking is disabled. The loader sends the page view explicitly without installing click or navigation listeners.
The tracker omits URL queries and fragments.
The application disables its own telemetry and external service calls.

Browser storage failures, Do Not Track, and Global Privacy Control stop the loader.
Blocked scripts or collection requests do not prevent reading or navigation.
Existing GoatCounter browser exclusions transfer to Umami on the next visit.

To exclude your browser, open `https://ross.grattafiori.dev/#toggle-analytics`.
Make sure that the message says tracking is disabled.
Repeat this on each browser and device that you use.
Opening the URL again enables tracking in that browser.

## Recovery

Restore the database, application Secret, and saved account credentials from the backups on potatoserver.
Use [operations](operations.md) for the recovery tests.
The blog website ID is `8bbb85d9-34c5-4d84-b595-ecce3cba7846`.
Keep this ID consistent with the blog loader.

## Operations

From `/home/rossgrat/repos/network` on potatoserver, run:

```sh
K3S_CONFIG_FILE=/dev/null /usr/local/bin/k3s kubectl --kubeconfig /home/rossgrat/.kube/potatoserver-k3s.yaml get pods -n umami
K3S_CONFIG_FILE=/dev/null /usr/local/bin/k3s kubectl --kubeconfig /home/rossgrat/.kube/potatoserver-k3s.yaml logs -n umami deployment/umami --tail=100
bash ops/backup-database.sh umami /home/rossgrat/backups/umami/manual
```

Backups contain the PostgreSQL database and application secrets.
Keep them private on potatoserver. Do not copy them to the Mac or another server.
The claim `umami/data-postgres-0` holds the live database in K3s.
The retired Docker data is archived in server-local cleanup backups.
Each manual backup requires a new directory. It saves the active database, deployment secrets, and saved HTTP credentials.
The memory limits are 512 MiB for Umami and 256 MiB for PostgreSQL.

## GoatCounter history

Umami starts with fresh counts. GoatCounter history is not imported.
The retired GoatCounter container, image, volume, and deployment files are removed.
The final SQLite snapshot remains at `/home/rossgrat/backups/goatcounter/umami-20261111/goatcounter-final.sqlite3`.
The snapshot passed SQLite's integrity check before the old volume was removed.

## Sources

- [Umami 3.4.1](https://github.com/umami-software/umami/releases/tag/v3.4.1)
- [Tracker configuration](https://docs.umami.is/docs/tracker-configuration)
- [Browser exclusion](https://docs.umami.is/docs/exclude-my-own-visits)
- [Environment variables](https://docs.umami.is/docs/environment-variables)
