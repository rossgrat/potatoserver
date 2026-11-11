# Umami

Umami provides blog analytics at `https://stats.grattafiori.dev`.
The dashboard requires a login. The public `/api/send` endpoint accepts page views.
The deployment pins Umami 3.4.1 and PostgreSQL 18.6.
PostgreSQL does not publish a host port.
The application also listens on `127.0.0.1:3031` for local administration.

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

## Initial setup

On potatoserver, create `umami/.env` from `.env.example` in the deployment checkout.
Generate each value with `openssl rand -hex 32`.
Set the file permissions to `600`.
From the checkout, start the application:

```sh
docker compose -p umami -f umami/docker-compose.yml up -d --wait
```

Before routing public requests, replace the default administrator password and create the blog site:

```sh
umask 077
mkdir -p "$HOME/.config/umami"
set -o noclobber
docker compose -p umami -f umami/docker-compose.yml exec -T umami node --input-type=module < umami/bootstrap.mjs > "$HOME/.config/umami/admin.json"
```

Run the bootstrap script only on a new database.
It saves the generated password on the server without printing it.
The blog website ID is `8bbb85d9-34c5-4d84-b595-ecce3cba7846`.
Keep this ID consistent with the blog loader.
The script explicitly disables recording and heatmaps for that website.

## Operations

From `/home/rossgrat/repos/network` on potatoserver, run:

```sh
docker compose -p umami -f umami/docker-compose.yml ps
docker compose -p umami -f umami/docker-compose.yml logs --tail=100
bash umami/backup.sh /home/rossgrat/backups/umami/manual
```

Backups contain the PostgreSQL database and application secrets.
Keep them private and copy them to separate storage.
The `umami_postgres_data` volume holds the live database.
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
