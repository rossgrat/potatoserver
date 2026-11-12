# Potatoserver operations

Run server commands from `/home/rossgrat/repos/network` on potatoserver.
The [root declaration](../kustomization.yaml) defines K3s workloads.
[k3s/release](../k3s/release) pins the cluster version.
K3s uses bundled containerd. Docker is not needed on the host.
Keep credentials and backups on potatoserver.

## Deploy and inspect

```sh
make k3s-diff
make k3s-apply
make k3s-logs SERVICE=job-board
```

`make logs` follows Caddy. `make up` applies declarations.
`make down` stops applications and databases. It retains their storage.
The runtime guard rejects retired Docker deployment commands from Job Board and Wubzduh.
Caddy exposes host ports 80 and 443.
Cloudflare Tunnel and Tailscale run as host services.

## CMS updates

Build on a workstation for Linux amd64.
Advance the pinned image tag in both [Makefile](../Makefile) and [k3s/pages-cms.yaml](../k3s/pages-cms.yaml) when image contents change:

```sh
make cms-build
docker image save potatoserver-pages-cms:2.1.8-r4-node24.22.2 > /tmp/pages-cms-image.tar
```

Transfer the archive to potatoserver, then back up and deploy there:

```sh
bash ops/backup-database.sh pages-cms /home/rossgrat/backups/pages-cms/manual-YYYYMMDDTHHMMSS
sudo bash ops/import-cms-image.sh /home/rossgrat/pages-cms-image.tar
make cms-up
```

Import checks image reference, architecture, and identity, and retains recovery images.
`cms-up` runs database migrations before applying the application declaration.
Review schema changes and retain the previous image plus its matching database backup.

## Backups

The root timer backs up K3s state at 02:55 America/Chicago.
The user timer backs up application data at 03:00 in the same time zone.
Each writes dated directories under `/home/rossgrat/backups`.
Use a new directory for every manual backup:

```sh
bash ops/backup.sh /home/rossgrat/backups/k3s-manual-YYYYMMDDTHHMMSS
bash ops/backup-database.sh umami /home/rossgrat/backups/umami/manual-YYYYMMDDTHHMMSS
```

Full backups retain PostgreSQL dumps, roles, schemas, fingerprints, Kubernetes resources/Secrets, ntfy data, media, images, and infrastructure data.
Dumps and fingerprints share an exported snapshot. ntfy uses SQLite online backup.
Caddy stays available while files and certificate/key pairs are copied and checked.
LGTM stops during its data archive and restarts before compression, briefly interrupting Grafana.
Single-database backups also retain namespace resources and Secrets.
Umami backups include saved administrator credentials.
Full-backup directory labels remain compatible with existing recovery snapshots.

Inspect schedules and results:

```sh
systemctl list-timers potatoserver-k3s-backup.timer
systemctl --user list-timers potatoserver-backup.timer
systemctl show potatoserver-k3s-backup.service -p Result
systemctl --user show potatoserver-backup.service -p Result
```

After changing tunnel, Wi-Fi, or Tailscale credentials, save protected host credentials into an existing backup directory:

```sh
sudo bash ops/backup-host-secrets.sh /home/rossgrat/backups/k3s-manual-YYYYMMDDTHHMMSS
```

That command stores credentials with permissions `600`.

## Recovery tests

Use a complete application backup, not a single-database backup directory:

```sh
bash tests/recovery/applications.sh /home/rossgrat/backups/k3s-manual-YYYYMMDDTHHMMSS
bash tests/recovery/ntfy.sh /home/rossgrat/backups/k3s-manual-YYYYMMDDTHHMMSS
```

Tests compare restored contents/schema, indexes, sequences, passwords, and isolated application startup.
ntfy checks SQLite integrity, token access, and unauthorized-request rejection.
Temporary namespaces use isolated networks/storage without production volumes or public ports.

Test a root cluster backup separately:

```sh
bash tests/recovery/cluster.sh /home/rossgrat/backups/k3s-state-YYYYMMDDTHHMMSSZ
```

The agentless recovery pod compares credentials and object identities without printing secrets.
It has no host mounts or service account.
These are in-cluster tests. Host replacement also requires the OS, K3s, host services, and protected credentials.

## Health and host files

After a deployment or planned reboot, create a private evidence directory and run:

```sh
mkdir -m 700 /home/rossgrat/backups/k3s-health-YYYYMMDDTHHMMSS
bash ops/verify-services.sh /home/rossgrat/backups/k3s-health-YYYYMMDDTHHMMSS
bash ops/verify-telemetry.sh /home/rossgrat/backups/k3s-health-YYYYMMDDTHHMMSS
```

Checks cover declarations, cluster version, workloads, storage, HTTPS, timers, and worker telemetry.
The telemetry window is two hours because fetching is hourly.
Unattended OS reboot recovery remains unverified.
The November 11 reboot needed manual power-on.
The migration also recorded Spotify album HTTP 403 responses predating K3s.

Installed root backup/firewall helpers live under `/usr/local/libexec/potatoserver-k3s/`, with versioned sources in [systemd/libexec](../systemd/libexec).
The root backup uses `/usr/local/libexec/potatoserver-runtime/node-24.22.2`.
Unit and drop-in sources live in [systemd](../systemd).
Host configuration is [k3s/config.yaml](../k3s/config.yaml).
Changes to these host files need root installation.
`make k3s-apply` applies only Kubernetes declarations.
Historical migration receipts remain in Git history and server-local retirement backups.

## Script languages

Bash runs commands, copies files, and coordinates backups and deployments.
JavaScript helpers handle Kubernetes JSON, SQLite backups, and certificate checks.
These operations helpers use Node's built-in modules. They need no npm packages on the server.
The host scripts use the pinned Node binary at `/usr/local/libexec/potatoserver-runtime/node-24.22.2`.

References: [K3s recovery](https://docs.k3s.io/datastore/backup-restore), [PostgreSQL dumps](https://www.postgresql.org/docs/18/app-pgdump.html), [SQLite online backup](https://www.sqlite.org/backup.html), and [Node SQLite APIs](https://nodejs.org/download/release/v24.22.2/docs/api/sqlite.html).
