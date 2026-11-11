# K3s migration

Migrate one application at a time after its recovery tests pass.
Keep all backups on potatoserver. Do not copy private data to the Mac.
Keep cloudflared, Tailscale, and Caddy outside K3s during the application migration.

The November 11 baseline is `/home/rossgrat/backups/k3s-baseline-20261111T1754` on potatoserver.
All five database restorations and isolated application startup tests passed.
Restored database passwords passed authentication tests. Incorrect passwords were rejected.
The restored ntfy and monitoring services passed their health tests.
Caddy configuration validation, SQLite integrity tests, custom image loading, and backup checksum tests passed.
The protected host archive passed its checksum and archive tests. Its permissions are `600`.
The nightly timer is enabled and active. The user service can run after logout.
The backup service passed a manual run. Its completed backup passed checksum tests.
The service's final timestamp command required a journald compatibility fix.
K3s installation and its disposable workload tests passed on November 11.
The isolated cluster restoration returned the original encrypted secret and object identity.
Installation evidence is `/home/rossgrat/backups/k3s-install/20261111T193830Z` on potatoserver.
The Miniflux rehearsal passed data, schema, authentication, network, and database replacement tests.
Its K3s backup restored into an isolated PostgreSQL container with matching data.
Miniflux now serves private HTTPS from K3s. The original Docker containers remain stopped with their volumes preserved.
Its database wait step removed the initial connection failures during application startup.
The private account and single-feed refresh tests passed after the cutover.
The first backup after the move saved the Miniflux database from K3s.
That backup passed its checksums. All five database restorations passed.
Umami now serves its existing public URL from K3s.
Its first complete backup passed checksum tests and isolated restorations of both K3s databases.
CMS now serves its public URL from K3s with its existing owner session and GitHub repository access.
Wubzduh, Job Board, and ntfy also serve their existing URLs from K3s.
Their original Docker containers remain stopped with their volumes preserved.
Clock-based observation periods are follow-up checks. Functional failures still stop dependent changes.

## Milestones

Each milestone gates the next live change. Record failures before retrying.
Keep the original Docker volumes until the final observation period ends.

| Milestone | Required evidence |
|---|---|
| 1. Recovery | Complete server-local backups, matching restored data, isolated application startup, protected host state, and a successful backup service run |
| 2. K3s installation | Ready node, working DNS, restricted administrative access, working network rules, and healthy existing applications |
| 3. Recovery rehearsal | Successful container replacement, failed-release detection, explicit rollback, persistent storage, and isolated cluster restoration |
| 4. Miniflux | Matching restored data, working private access, and successful restart tests. Continue observation after the move. |
| 5. Other applications | Individual acceptance and recovery tests for Umami, CMS, wubzduh, job-board, and ntfy. Continue observation after each move. |
| 6. Operations | Working telemetry, isolated updates, successful restoration, planned reboot recovery, and seven successful nightly backups |

## Backup procedure

The scripts require Bash 4 or later on potatoserver.
Run them on the server, not on the Mac.
Use a new directory for each backup. The scripts keep files private with permissions of `600`.

From the infrastructure checkout on potatoserver, run:

```sh
bash ops/migration-backup.sh /home/rossgrat/backups/k3s-baseline-YYYYMMDDTHHMMSS
```

The backup includes five database dumps, database roles, application secrets, configuration, media, persistent volumes, and the custom images.
Database dumps and data fingerprints use the same exported snapshot.
A fingerprint records each table's row count and a digest of its sorted row digests.
It does not print application records.

The script pauses each application while it archives that application's files.
Each archive has a ten-minute limit. The cleanup handler resumes the application after an error.
The monitoring store can require several minutes. Other applications continue to run during that archive.

If a volume archive fails after the database backups finish, resume the unfinished steps:

```sh
bash ops/migration-backup.sh /home/rossgrat/backups/k3s-baseline-YYYYMMDDTHHMMSS --resume-volumes
```

The resume procedure retains completed database dumps and compressed volume archives.
It tests existing compressed archives before skipping them.
Do not use the resume procedure for a different backup date or source deployment.

## Restoration tests

The restoration test reads private data only on potatoserver.
It starts temporary databases and applications on internal Docker networks.
These networks have no external access. The test does not publish host ports.

Run:

```sh
bash ops/migration-restore-test.sh /home/rossgrat/backups/k3s-baseline-YYYYMMDDTHHMMSS
```

The test performs these steps for each database:

1. Make sure that database backup checksums match.
2. Restore the dump into an empty database with the original PostgreSQL image.
3. Compare table counts, row digests, and normalized schema definitions.
4. Test database pages, indexes, and sequence positions.
5. Test the saved database password and reject an incorrect password.
6. Start the original application image against the restored database and saved credentials.
7. Request the application's health or landing endpoint.
8. Remove the temporary application, database, network, and scratch volumes.

Results stay in the backup's `restore-results` directory.
A failed HTTP startup test does not erase a successful database comparison.
Some applications require external providers during startup. Record that restriction before changing a test's network access.

These tests do not establish authenticated browser behavior, background-job completion, or a complete host rebuild.
The service-specific migration checkpoints cover those behaviors later.
The test saves database roles but restores application objects under the original application's database user.
It does not rehearse every database role or grant.

After the complete archive passes its checksum test, test the other persistent volumes:

```sh
bash ops/migration-volume-test.sh /home/rossgrat/backups/k3s-baseline-YYYYMMDDTHHMMSS
```

This test extracts the volume archives and loads the saved custom images.
It tests SQLite integrity, then starts isolated ntfy and Grafana copies against the restored files.
Their health endpoints must respond successfully.
The test also validates Caddy with its restored configuration, certificates, media paths, and saved environment.

## K3s installation

K3s `v1.37.2+k3s1` runs on potatoserver. The binary matches the published release checksum.
The pinned installer checksum, server configuration, and disposable test manifests live in `k3s/`.
The server keeps its existing Caddy ports. Cluster administration accepts local, Tailscale, and cluster traffic.

The installation script requires root access on potatoserver.
From the Mac, run:

```sh
ssh -t -o HostName=100.108.26.48 -o HostKeyAlias=potatoserver potatoserver \
  'sudo bash /home/rossgrat/k3s-migration-tools/ops/install-k3s.sh'
```

The script installs K3s, waits for each object's creation and readiness, and runs disposable verification workloads.
An installation lock rejects overlapping runs.
It tests DNS, outbound HTTPS, the Caddy connection, persistent storage, a failed release, rollback, and network policy.
It also tests that a Docker client cannot reach the administrative port.
The script stops K3s to back up cluster state and test existing services independently.
It then starts K3s again and compares the original Docker containers with the initial inventory.

The administrator credentials stay on potatoserver at `/home/rossgrat/.kube/potatoserver-k3s.yaml`, with permissions of `600`.
Installation evidence and the cluster backup stay under `/home/rossgrat/backups/k3s-install/`.
The cluster backup contains cluster state and its server token. It does not contain application volume data.
An installation checkpoint failure stops K3s. Diagnose the failure before moving application data.

The K3s client uses this command on potatoserver:

```sh
K3S_CONFIG_FILE=/dev/null /usr/local/bin/k3s kubectl \
  --kubeconfig /home/rossgrat/.kube/potatoserver-k3s.yaml get nodes
```

The client override avoids reading the root-only server configuration. It does not change the server configuration.
Do not rerun the installer after migrating applications. It includes a deliberate cluster stop.

For an isolated restoration on potatoserver, run:

```sh
bash /home/rossgrat/k3s-migration-tools/ops/test-cluster-restore.sh \
  /home/rossgrat/backups/k3s-install/20261111T193830Z
```

The restoration uses the pinned K3s image on an internal Docker network.
It publishes no ports and starts no application workloads.
It compares the recovered secret data and identity without printing credentials.

The recurring cluster backup runs through a root service on potatoserver.
The application backup service cannot read the protected cluster database or token.
From the Mac, run:

```sh
ssh -t -o HostName=100.108.26.48 -o HostKeyAlias=potatoserver potatoserver \
  'sudo bash /home/rossgrat/k3s-migration-tools/ops/finish-k3s-backups.sh'
```

The installer saves a cluster snapshot and tests its isolated restoration before enabling the timer.
The snapshot procedure copies SQLite through its backup API while K3s continues to run.
It also saves the server token and configuration. It keeps all files on potatoserver.
The timer runs at 02:55 America/Chicago, before the application backup at 03:00.
The snapshot procedure passed a concurrent-write test and an encrypted cluster restoration test against a saved copy.
The protected live snapshot and isolated restoration passed on November 11.
The root timer is enabled and active.

## Miniflux cutover

The Miniflux database uses the `local-retain` storage class.
Deleting its claim does not delete the stored data automatically.
This storage remains on potatoserver and does not protect against server or disk loss.

The rehearsal disables the Miniflux scheduler and blocks external HTTP traffic.
The live manifest enables the scheduler. Disable it and set zero replicas before applying that manifest for another rehearsal.
Its restored database must match the source snapshot before the application starts.
The account, incorrect-password, database replacement, and network tests must pass before the cutover.

The cutover stops Docker Miniflux before taking its final database snapshot.
It restores that snapshot into K3s and repeats the data and account tests.
It changes the backup authority to K3s before changing Caddy.
Caddy forwards RSS to `172.18.0.1:30081`. The private hostname and TLS configuration remain the same.
The cutover enables feed access and the scheduler after private HTTPS tests pass.

The versioned `deployments.conf` file records each application's Docker or K3s ownership.
Deployment commands and nightly backups read that file from the infrastructure checkout.
Unknown authority values fail the backup. K3s errors do not fall back to the old Docker database.
The nightly backup also saves the Miniflux resources, secrets, and migration tools.
Its files and credentials remain on potatoserver.

The original Docker volumes remain available for recovery.
After Caddy changes, preserve K3s writes before restoring the Docker service.
Reverting Caddy alone can expose the stale Docker database and lose newer changes.
Keep the original Docker containers until the backup procedures no longer need their saved image and environment.

## Umami cutover

Umami runs in the namespace `umami`. Caddy forwards its existing public hostname to `172.18.0.1:30082`.
Its database uses the retained claim `umami/data-postgres-0`.
The original Docker application and database remain stopped with restart policies set to `no`.

The rehearsal compared source data and schema before application startup.
The existing account, existing session, website configuration, and tracker content matched.
The database retained its data after pod replacement.
The K3s backup restored into an isolated PostgreSQL container with matching data.

The public collection test stored one synthetic page view after the switch.
The test removed its own event and unused test session.
The complete backup service then saved both K3s databases and passed their isolated restoration tests.
The manual Umami backup also reads the active database and saves its secrets and saved HTTP credentials.

## CMS preparation

The CMS database copy matches its source data and schema.
The existing owner session works through the prepared Caddy proxy to the Docker application.
Anonymous session access and the disabled email endpoint passed their tests.
The custom CMS image archive matches the running Docker image and passes its checksum test.
The image import and disposable image test passed.
The first tunnel checkpoint failed and restored the previous configuration.
The original checks discarded their error details.
The revised script prints each step and records tunnel and public HTTP results.
Its public checker passed temporary-error recovery and permanent-failure tests.
The revised script reuses the imported image when its identity matches.
The preparation retry passed at 21:41 UTC on November 11.
The first public probe returned HTTP 530. The second probe returned HTTP 200.
The preparation routed CMS through Caddy to the Docker application before the final transfer.
Protected host backup and isolated cluster recovery passed after that change.

The K3s image store and tunnel configuration require root access.
From the Mac, run:

```sh
ssh -t -o HostName=100.108.26.48 -o HostKeyAlias=potatoserver potatoserver \
  'sudo bash /home/rossgrat/k3s-migration-tools/ops/prepare-cms-k3s.sh'
```

The script imports the pinned image and tests it with a disposable job.
It routes CMS through Caddy to the same Docker application.
It restores the previous tunnel configuration if that route fails.
It also saves protected host state and repeats the cluster snapshot and recovery tests.
All archives remain on potatoserver.

The private K3s application passed its owner-session and database replacement tests.
Its database backup restored into isolation with matching data.
The final transfer used a new database snapshot after stopping the Docker application.
The application backup authority stayed on Docker during preparation.

CMS now serves its public URL from K3s.
The final transfer took 24 seconds and preserved the source data, owner session, and accessible GitHub repositories.
The original Docker containers remain stopped with their volumes preserved.

## Declarative operations

The repository contains the intended application configuration, image pins, network rules, and storage declarations.
The `deployments.conf` file selects the production runtime for each application.
Private credentials and database contents remain in server-local backups.

From `/home/rossgrat/repos/network` on potatoserver, compare the running applications with their declarations:

```sh
make k3s-diff
```

Apply the declared configuration:

```sh
make k3s-apply
```

The comparison passed without differences after each completed transfer.
Migration scripts use live commands for temporary pauses and data restoration.
Completed transfers update the versioned runtime configuration and application manifests.

Each remaining transfer uses a fresh backup of its own data and its application-specific acceptance tests.
Full nightly backups remain enabled. Repeat the full backup verification after the remaining transfers finish.

## Wubzduh, Job Board, and ntfy

Wubzduh uses NodePort `30084`. Job Board uses `30085`. ntfy uses `30086`.
Each database transfer compared table contents, schema, indexes, and sequence positions before starting the application.
Database replacement tests passed for Wubzduh and Job Board.
Wubzduh also retained its original log contents in a separate persistent volume.

The Wubzduh feed, artist page, and static assets passed private and public requests.
Spotify token acquisition passed. Spotify album reads returned HTTP 403 from K3s and the original Docker network.
The original Docker logs also contain HTTP 403 errors. The music fetch behavior remains a known application issue.
The migration does not establish successful scheduled music updates.

Job Board retained its existing session, dashboard, browse page, company page, and metrics page.
Anonymous requests and invalid sessions were rejected.
The original worker stopped before the K3s worker started.
LGTM accepts OTLP on `172.18.0.1:4317`. The API and worker retain their original service names.
Queries found new API and worker logs after their K3s pods started.
The K3s worker discovered a new job and completed a processing task after the handoff.

ntfy retained its user database, access rules, token, and cache volume contents.
The restored files matched their source hashes. SQLite integrity and foreign key tests passed.
An isolated test identity published and received a synthetic notification with external traffic blocked.
The application retained authentication after pod replacement.
The public endpoint accepted the existing token and rejected anonymous requests and invalid tokens.
These tests do not establish notification delivery to a physical phone.
The existing configuration stores message history in memory. The migration preserves that configuration.

Nightly backups read the five active databases from K3s.
They archive Wubzduh logs from its K3s volume and use SQLite's online backup API for ntfy.
Caddy and LGTM volume backups continue to use Docker.
All backup files remain on potatoserver.

The older Docker deployment commands in the Wubzduh and Job Board repositories now require the Docker runtime.
The guard rejects those commands after a service moves to K3s.
Update the pinned infrastructure manifests before deploying a new application version.
Review database migrations separately before applying an image that changes the schema.

After an application accepts writes on K3s, preserve its current data before reverting its route.
The original Docker database contains the state from the handoff, not later writes.
Do not restart the old worker alongside the K3s worker.

Reboot recovery and seven successful nightly backups remain pending until those events occur.
Functional tests do not replace those observations.

The final application backup is `/home/rossgrat/backups/k3s-nightly-20261111T225502Z` on potatoserver.
Its complete checksum test passed after all six transfers.
The Wubzduh and Job Board dumps passed isolated restoration, data comparison, password tests, and application startup.
The ntfy online backup passed isolated startup, saved-token authentication, and anonymous-access rejection.
Final verification found seven healthy deployments, five healthy databases, retained storage, and zero application pod restarts.
All seven application and infrastructure health URLs returned HTTP 200.
The declared configuration matched the cluster. Docker reached the host web port but could not reach cluster administration.
The evidence remains in the backup's `restore-results` and `final-verification` directories.

## Final protected checkpoint

The final script requires root access because it reads the K3s encryption material and protected host credentials.
It requires a complete application backup and successful final verification first.
It saves the current host state, Git history, and migration tools on potatoserver.
It also restores the current cluster in isolation and compares application credentials with the live cluster.
It does not reboot the server.

The protected checkpoint passed on November 11 at 23:13 UTC.
The host archive is `/home/rossgrat/backups/k3s-final-20261111T231320Z` on potatoserver.
Its checksums, archive integrity, source bundle, ownership, and permissions passed verification.
The current cluster backup is `/home/rossgrat/backups/k3s-state-20261111T231330Z`.
Isolated recovery preserved all ten application Secrets across six namespaces, including their object identities and contents.
All applications remained healthy after the checkpoint.

From the Mac, run:

```sh
ssh -t -o HostName=100.108.26.48 -o HostKeyAlias=potatoserver potatoserver \
  'sudo bash /home/rossgrat/k3s-migration-tools/ops/finalize-k3s.sh'
```

After that checkpoint passes, arrange physical access before the reboot test.
The earlier boot history includes a manual power cycle. Remote SSH alone does not provide recovery from that failure.
After the reboot, run `bash /home/rossgrat/k3s-migration-tools/ops/verify-reboot.sh` on potatoserver.
The script requires a different boot identity and the same persistent claims and volumes.
It tests service health, network restrictions, and both backup timers.
It also requires ready application containers without further restarts during a 30-second observation.
Restart counts from the boot itself do not fail this test.
Test authenticated application access before marking the full reboot checkpoint complete.

## Protected host state

The tunnel credential, Wi-Fi configuration, and Tailscale identity require root access for backup.
The protected archive remains on potatoserver and contains secrets.
Do not print its contents or commit it to Git.

After the application backup finishes, run this remote command from the Mac:

```sh
ssh -t -o HostName=100.108.26.48 -o HostKeyAlias=potatoserver potatoserver \
  'sudo bash /home/rossgrat/k3s-migration-tools/ops/finish-baseline.sh /home/rossgrat/backups/k3s-baseline-YYYYMMDDTHHMMSS'
```

The password prompt belongs to potatoserver.
This command archives protected host state and enables the server-local backup timer.
It also permits the user service to run after logout.
The timer starts at 03:00 America/Chicago. It never copies data off the server.

The nightly procedure captures application data and readable host configuration.
Repeat the protected backup after changing tunnel credentials, Wi-Fi credentials, or the Tailscale identity.
Backups remain in dated directories. Automatic deletion is not configured.

## Sources

- [PostgreSQL consistent backups and exported snapshots](https://www.postgresql.org/docs/18/app-pgdump.html)
- [PostgreSQL restoration](https://www.postgresql.org/docs/18/app-pgrestore.html)
- [Docker container pause](https://docs.docker.com/reference/cli/docker/container/pause/)
- [K3s cluster backup and server token](https://docs.k3s.io/datastore/backup-restore)
- [K3s v1.37.2 release](https://github.com/k3s-io/k3s/releases/tag/v1.37.2%2Bk3s1)
- [K3s server configuration](https://docs.k3s.io/cli/server)
- [Kubernetes creation and readiness waits](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_wait/)
- [Miniflux scheduler configuration](https://miniflux.app/docs/configuration.html)
- [Miniflux API authentication](https://miniflux.app/docs/api.html#authentication)
- [Kubernetes volume retention](https://kubernetes.io/docs/concepts/storage/persistent-volumes/#retain)
- [SQLite online backup API](https://www.sqlite.org/backup.html)
- [Umami API authentication](https://docs.umami.is/docs/api/authentication)
- [Umami page-view collection](https://docs.umami.is/docs/api/sending-stats)
- [K3s manual image import](https://docs.k3s.io/installation/airgap)
- [Caddy reverse proxy](https://caddyserver.com/docs/caddyfile/directives/reverse_proxy)
- [ntfy listening addresses, authentication, and message history](https://docs.ntfy.sh/config/)
- [Kubernetes container restart counters](https://github.com/kubernetes/api/blob/master/core/v1/generated.proto)
