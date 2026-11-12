# Potatoserver operations

Run these commands on potatoserver from `/home/rossgrat/repos/network`.
The repository declares all eight services, their versions, storage, and network rules.
Private credentials and database contents stay on potatoserver.

## Services and deployment

Miniflux, Umami, CMS, Wubzduh, Job Board, ntfy, Caddy, and LGTM run on K3s.
Cloudflare Tunnel and Tailscale run as host services.
K3s uses its own containerd runtime. The cleanup removed the system Docker packages and data.
Caddy exposes host ports 80 and 443 and routes requests through Kubernetes service DNS.
The `deployments.conf` file records the active runtimes.
The root `kustomization.yaml` declares the complete deployment and generates Caddy and Grafana configuration maps.

Compare the declared configuration with the cluster:

```sh
make k3s-diff
```

Apply the declared configuration:

```sh
make k3s-apply
```

Read application logs:

```sh
make k3s-logs SERVICE=job-board
```

`make up` applies all K3s declarations.
`make down` stops the applications and databases.
The older Docker deployment commands in the application repositories reject migrated services.

## CMS image updates

Build CMS images on a workstation with a container builder.
Use a new pinned tag when the image contents change.
Update that tag in the Makefile and `k3s/pages-cms.yaml` together.
The image must target Linux amd64.

From the workstation checkout, build and export the pinned image:

```sh
make cms-build
docker image save potatoserver-pages-cms:2.1.8-r4-node24.22.2 > /tmp/pages-cms-image.tar
```

Transfer the image archive to potatoserver.
On potatoserver, back up the database and import the archive:

```sh
bash pages-cms/backup.sh /home/rossgrat/backups/pages-cms/manual-YYYYMMDDTHHMMSS
sudo bash ops/import-cms-image.sh /home/rossgrat/pages-cms-image.tar
make cms-up
```

The import accepts a Docker or OCI image archive and checks its reference, architecture, and image identity.
It saves recovery images under `/home/rossgrat/.local/state/potatoserver`.
The deployment requires the imported image reference to match the declaration.
It runs database migrations through a temporary Job from the declared CMS pod specification.
Review schema changes before running an application upgrade.

## Backups

The root timer captures K3s state at 02:55 America/Chicago.
The user timer captures application data at 03:00 America/Chicago.
Both timers remain enabled after logout and reboot.
They write dated directories under `/home/rossgrat/backups`.
They do not send data to the Mac or another server.

The application backup contains five PostgreSQL dumps, roles, schemas, and data fingerprints.
It also contains K3s resources and Secrets, ntfy state, Wubzduh logs, media, custom images, Caddy state, and LGTM data.
Database dumps and fingerprints use the same exported snapshot.
ntfy uses SQLite's online backup API.
Caddy continues serving traffic while the backup copies its files and checks certificate and key pairs.
The script stops LGTM while it copies persistent files, then restarts LGTM before compression.
The LGTM archive takes several minutes. Other application services continue to run.

Run a manual application backup with a new directory:

```sh
bash ops/backup.sh /home/rossgrat/backups/k3s-manual-YYYYMMDDTHHMMSS
```

Inspect the timers and last service results:

```sh
systemctl list-timers potatoserver-k3s-backup.timer
systemctl --user list-timers potatoserver-backup.timer
systemctl show potatoserver-k3s-backup.service -p Result
systemctl --user show potatoserver-backup.service -p Result
```

Repeat the protected host backup after changing tunnel, Wi-Fi, or Tailscale credentials.
Run `sudo bash ops/backup-host-secrets.sh` with an existing `k3s-*` backup directory.
The archive contains credentials. Keep its permissions at `600`.

## Recovery tests

Restore application databases and start isolated application copies:

```sh
bash ops/restore-test.sh /home/rossgrat/backups/k3s-manual-YYYYMMDDTHHMMSS
bash ops/test-ntfy-restore.sh /home/rossgrat/backups/k3s-manual-YYYYMMDDTHHMMSS
```

The tests compare database contents and schema, inspect indexes and sequences, and test database authentication.
The restored applications use temporary K3s namespaces with isolated networks and temporary storage.
They do not expose public ports or use production volumes.
These tests do not replace a full host recovery procedure.

Test a root cluster backup in isolation:

```sh
bash ops/test-cluster-restore.sh /home/rossgrat/backups/k3s-state-YYYYMMDDTHHMMSSZ
```

The test starts an agentless K3s API inside a temporary pod with no host volumes or service account.
It compares saved and restored credentials without printing their contents.
The recovery tests work with Docker stopped.

## Service and reboot verification

Create a private directory before running service verification:

```sh
mkdir -m 700 /home/rossgrat/backups/k3s-health-YYYYMMDDTHHMMSS
bash ops/verify-services.sh /home/rossgrat/backups/k3s-health-YYYYMMDDTHHMMSS
bash ops/verify-telemetry.sh /home/rossgrat/backups/k3s-health-YYYYMMDDTHHMMSS
```

The telemetry check requires API and worker logs from the current containers and available fetcher metrics.
Its two-hour log window covers the worker's hourly fetch schedule.

Prepare a storage and boot baseline before a planned reboot:

```sh
bash ops/verify-reboot.sh --prepare
```

After the host returns, run:

```sh
bash ops/verify-reboot.sh
```

The test requires a new boot identity, unchanged persistent storage, ready applications, healthy routes, active timers, and stable container restart counts.
It does not establish that the host restarted without manual intervention.

## Follow-up work

The applications recovered after a manual power-on following the November 11 reboot request.
Automatic restart remains unresolved. The previous journal reached the system reboot target.
The host reports an Inspiron 7559 with BIOS 1.2.2 from January 22, 2017.
CMS and Umami allow three minutes for startup before normal liveness monitoring begins.

Wubzduh's Spotify album requests return HTTP 403, as they did before migration.
The first scheduled cluster and application backups passed on November 12, 2026.
The [migration record](archive/k3s-migration-20261111.md) retains the historical checkpoints and retired command paths.

## Sources

- [K3s backup and recovery](https://docs.k3s.io/datastore/backup-restore)
- [PostgreSQL consistent dumps](https://www.postgresql.org/docs/18/app-pgdump.html)
- [SQLite online backup](https://www.sqlite.org/backup.html)
- [Kubernetes startup probes](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/#protect-slow-starting-containers-with-startup-probes)
- [Kubernetes pod port settings](https://kubernetes.io/docs/tasks/administer-cluster/sysctl-cluster/)
