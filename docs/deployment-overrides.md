# Deployment overrides

These files preserve the service versions and database mounts deployed on potatoserver.
The applications live outside this infrastructure repository.

Run Compose commands from `/home/rossgrat/repos/network` on potatoserver:

```sh
docker compose -p job-board-v2 --project-directory /home/rossgrat/services/job-board-v2 -f /home/rossgrat/services/job-board-v2/docker-compose.yml -f overrides/job-board-v2.yml config --quiet
docker compose -p wubzduh --project-directory /home/rossgrat/services/wubzduh -f /home/rossgrat/services/wubzduh/docker-compose.yml -f overrides/wubzduh.yml config --quiet
```

Use both files for later Compose operations on these applications.
The Job Board override selects its existing PostgreSQL volume.
Do not replace that volume with the unused `pgdata` volume from the application configuration.

`systemd/90-potatoserver-network-online.conf` records the installed network startup rule.
It allows startup after either the Ethernet or Wi-Fi interface becomes routable.
The installed copy lives in `/etc/systemd/system/systemd-networkd-wait-online.service.d/`.

The completed migration scripts and evidence are archived outside Git in
`/home/rossgrat/backups/worktrees-20261111`.
