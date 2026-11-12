# Umami

Blog analytics at `https://stats.grattafiori.dev`.
The dashboard requires login; `/api/send` remains public for page views.
[k3s/umami.yaml](../k3s/umami.yaml) pins application and PostgreSQL images in namespace `umami`.
The database has no host port.

## Collection and exclusion

The blog explicitly sends one page view after load, during browser idle time when available.
It omits queries and fragments and installs no click/navigation listeners, session recording, heatmaps, custom events, or visitor IDs.
Umami's own telemetry and external service calls are disabled.

Do Not Track, Global Privacy Control, or browser-storage failure stops the loader.
Blocked collection does not prevent reading the site.
Open the [browser toggle](https://ross.grattafiori.dev/#toggle-analytics) and confirm that tracking is disabled.
Repeat per browser and device; opening it again enables tracking.
Existing GoatCounter exclusions transfer on the next visit.

## Operations and recovery

From `/home/rossgrat/repos/network` on potatoserver, use `make k3s-logs SERVICE=umami` for logs.
Follow [operations](operations.md#backups) for a database backup into a new directory and isolated restore tests.
Restore the database, application Secret, and saved account credentials from protected server backups.
Keep them private on potatoserver; do not copy them to the Mac or another server.
Retain claim `umami/data-postgres-0`.

Keep the blog loader's website ID consistent: `8bbb85d9-34c5-4d84-b595-ecce3cba7846`.
Umami starts with fresh counts; GoatCounter history was not imported.
The final historical snapshot remains at `/home/rossgrat/backups/goatcounter/umami-20261111/goatcounter-final.sqlite3`.

References: [tracker configuration](https://docs.umami.is/docs/tracker-configuration), [browser exclusion](https://docs.umami.is/docs/exclude-my-own-visits), and [environment variables](https://docs.umami.is/docs/environment-variables).
