# Potatoserver operations

Run server commands from `/home/rossgrat/repos/network` on potatoserver.
The root `kustomization.yaml` declares the Kubernetes deployment.
K3s uses its bundled containerd runtime. The host does not need Docker.
Private credentials and backups stay on potatoserver.

## Deployments

Miniflux, Umami, Pages CMS, Wubzduh, Job Board, ntfy, Caddy, and LGTM run in K3s.
Job Board has separate API and worker deployments.
Five PostgreSQL StatefulSets hold the application databases.
Caddy exposes host ports 80 and 443 and routes through Kubernetes service DNS.
Cloudflare Tunnel and Tailscale run as host services.
The expected K3s version is pinned in `k3s/release`.

Review and apply declarations:

```sh
make k3s-diff
make k3s-apply
```

Read application logs:

```sh
make k3s-logs SERVICE=job-board
make logs
```

`make up` applies declarations. `make down` stops applications and databases.
The declarations retain persistent storage when workloads stop.
The runtime guard in `ops/require-runtime.sh` rejects retired Docker deployment commands from the Job Board and Wubzduh repositories.

## CMS updates

Build on a workstation with a container builder.
Advance the pinned tag in both the Makefile and `k3s/pages-cms.yaml` when image contents change.
The Dockerfile pins the application, Node version, and dependency lockfile.
The image must target Linux amd64.

From the workstation checkout:

```sh
make cms-build
docker image save potatoserver-pages-cms:2.1.8-r4-node24.22.2 > /tmp/pages-cms-image.tar
```

Transfer the archive to potatoserver. Back up the database before an upgrade:

```sh
bash ops/backup-database.sh pages-cms /home/rossgrat/backups/pages-cms/manual-YYYYMMDDTHHMMSS
sudo bash ops/import-cms-image.sh /home/rossgrat/pages-cms-image.tar
make cms-up
```

The import checks the image reference, architecture, and identity, then saves recovery images on the server.
`make cms-up` runs a database migration Job before applying the CMS declaration.
Review schema changes before upgrading. Retain the matching database backup and previous image for rollback.

## Backups

The root timer captures K3s state at 02:55 America/Chicago.
The user timer captures application data at 03:00 America/Chicago.
Both write dated directories under `/home/rossgrat/backups`.
The first scheduled runs succeeded on November 12, 2026.

The full application backup contains PostgreSQL dumps, roles, schemas, fingerprints, Kubernetes resources and Secrets, ntfy state, media, custom images, and infrastructure data.
Database dumps and fingerprints share an exported snapshot.
ntfy authentication uses SQLite's online backup API.
Caddy continues serving while its files are copied and certificate/key pairs are checked.
LGTM stops during its data archive and restarts before compression. Grafana is unavailable during that interval.

Run a full backup into a new directory:

```sh
bash ops/backup.sh /home/rossgrat/backups/k3s-manual-YYYYMMDDTHHMMSS
```

Run a database backup with its namespace and a new directory:

```sh
bash ops/backup-database.sh umami /home/rossgrat/backups/umami/manual-YYYYMMDDTHHMMSS
```

The database command also saves namespace resources and Secrets.
For Umami, it includes the saved administrator credentials.
Full-backup database directories retain the labels used by existing recovery snapshots.

Inspect timer schedules and service results:

```sh
systemctl list-timers potatoserver-k3s-backup.timer
systemctl --user list-timers potatoserver-backup.timer
systemctl show potatoserver-k3s-backup.service -p Result
systemctl --user show potatoserver-backup.service -p Result
```

After changing tunnel, Wi-Fi, or Tailscale credentials, repeat the protected host backup:

```sh
sudo bash ops/backup-host-secrets.sh /home/rossgrat/backups/k3s-manual-YYYYMMDDTHHMMSS
```

That command requires an existing backup directory and saves credentials with permissions `600`.

## Recovery tests

Recovery tests live in `tests/recovery`.
Use a complete nightly or manual application backup, rather than a single-database backup directory:

```sh
bash tests/recovery/applications.sh /home/rossgrat/backups/k3s-manual-YYYYMMDDTHHMMSS
bash tests/recovery/ntfy.sh /home/rossgrat/backups/k3s-manual-YYYYMMDDTHHMMSS
```

The application tests compare restored contents and schema, inspect indexes and sequences, test passwords, and start isolated application copies.
ntfy tests SQLite integrity, a saved bearer token, and rejection of unauthorized requests.
Temporary namespaces use isolated networks and temporary storage without production volumes or public ports.

Test a root cluster backup:

```sh
bash tests/recovery/cluster.sh /home/rossgrat/backups/k3s-state-YYYYMMDDTHHMMSSZ
```

The agentless recovery pod compares restored credentials and object identities without printing secret data.
It uses no host volumes or service account.
These tests exercise recovery inside the running cluster. A replacement host also needs its operating system, K3s, host services, and protected credentials restored.

## Health checks

Create a private evidence directory and run:

```sh
mkdir -m 700 /home/rossgrat/backups/k3s-health-YYYYMMDDTHHMMSS
bash ops/verify-services.sh /home/rossgrat/backups/k3s-health-YYYYMMDDTHHMMSS
bash ops/verify-telemetry.sh /home/rossgrat/backups/k3s-health-YYYYMMDDTHHMMSS
```

The service check covers declared configuration, the pinned K3s version, workloads, retained storage, HTTPS routes, and timers.
The telemetry check uses a two-hour log window for the worker's hourly fetch schedule and checks fetcher metrics.
Run these checks after the server returns from a planned reboot.

## Host-managed files

The installed root backup and firewall files are separate from the repository checkout.
Their versioned sources are in `systemd/libexec`:

| Source | Installed path |
|---|---|
| `systemd/libexec/backup-k3s-state.sh` | `/usr/local/libexec/potatoserver-k3s/backup-k3s-state.sh` |
| `systemd/libexec/backup-k3s-state.mjs` | `/usr/local/libexec/potatoserver-k3s/backup-k3s-state.mjs` |
| `systemd/libexec/firewall.sh` | `/usr/local/libexec/potatoserver-k3s/firewall.sh` |

The root backup uses `/usr/local/libexec/potatoserver-runtime/node-24.22.2`.
Unit and drop-in sources are in `systemd`. Host configuration is in `k3s/config.yaml`.
Changing those sources requires installation as root; `make k3s-apply` only applies Kubernetes declarations.

## Known follow-ups

The November 11 OS reboot required a manual power-on. Unattended OS reboot recovery remains unverified.
The migration also recorded Spotify album HTTP 403 responses that predated K3s.
Historical migration commands and receipts remain in Git history and the server's dated retirement backups.

## Sources

- [K3s backup and recovery](https://docs.k3s.io/datastore/backup-restore)
- [PostgreSQL consistent dumps](https://www.postgresql.org/docs/18/app-pgdump.html)
- [SQLite online backup](https://www.sqlite.org/backup.html)
