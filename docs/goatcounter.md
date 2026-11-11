# GoatCounter

GoatCounter 2.7.0 previously collected traffic statistics for `ross.grattafiori.dev`.
It is stopped after the [Umami migration](umami.md). Its SQLite volume remains available for history and rollback.
The instructions below describe the previous deployment.
The container image is pinned by version and digest.
The dashboard at `https://stats.grattafiori.dev` requires an administrator login.
The `/count` endpoint accepts public tracking requests.

The blog hosts the matching tracking script in its own repository.
It loads the script after the page load event, during browser idle time when available.
Tracking failures do not prevent reading or navigation. Local Hugo previews omit tracking.

## Deployment

Run these commands from the infrastructure checkout on potatoserver:

```sh
docker compose -f goatcounter/docker-compose.yml config --quiet
docker compose -f goatcounter/docker-compose.yml up -d
```

Create the site once. Replace the email address with the administrator email.
The command prompts for a password.

```sh
docker compose -f goatcounter/docker-compose.yml exec goatcounter \
  goatcounter db create site -vhost stats.grattafiori.dev -user.email YOUR_EMAIL
```

Add this ingress rule before the final 404 rule in `/etc/cloudflared/config.yml`:

```yaml
  - hostname: stats.grattafiori.dev
    service: http://localhost:80
```

Create the DNS route and validate the tunnel configuration:

```sh
cloudflared tunnel route dns potatoserver stats.grattafiori.dev
cloudflared tunnel --config /etc/cloudflared/config.yml ingress validate
sudo systemctl restart cloudflared
```

Validate and reload the updated Caddyfile. Use the Caddy container's mounted file.
Do not use `make deploy`, which restarts all managed services.

```sh
docker exec caddy caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile
docker exec caddy caddy reload --config /etc/caddy/Caddyfile --adapter caddyfile
```

Caddy forwards Cloudflare's visitor IP to GoatCounter for visit counting and country lookup.
Keep this route behind Cloudflare Tunnel. Do not expose it directly to the internet.

## Administration

The SQLite database lives in the `goatcounter_goatcounter-data` Docker volume.
Do not remove this volume during upgrades.
Email delivery is not configured. GoatCounter writes email contents to container logs.
Use the CLI to reset a forgotten password:

```sh
docker compose -f goatcounter/docker-compose.yml exec goatcounter \
  goatcounter db update user -find YOUR_EMAIL
```

To exclude your own browser, visit `https://ross.grattafiori.dev/#toggle-goatcounter`.
The tracker displays a confirmation. Visiting that URL again enables tracking.

## Backups

Create a consistent SQLite snapshot while GoatCounter runs:

```sh
backup_name="goatcounter-$(date -u +%Y%m%dT%H%M%SZ).sqlite3"
mkdir -p "$HOME/backups/goatcounter"
docker compose -f goatcounter/docker-compose.yml exec -T goatcounter \
  goatcounter db query "VACUUM INTO '/tmp/$backup_name'" -format exec
docker compose -f goatcounter/docker-compose.yml cp \
  "goatcounter:/tmp/$backup_name" "$HOME/backups/goatcounter/$backup_name"
docker compose -f goatcounter/docker-compose.yml exec -T goatcounter rm "/tmp/$backup_name"
chmod 600 "$HOME/backups/goatcounter/$backup_name"
```

Copy snapshots to separate storage to protect against server disk failure.
No recurring backup job is configured by this deployment.

## Sources

- [GoatCounter 2.7.0](https://github.com/arp242/goatcounter/releases/tag/v2.7.0)
- [Self-hosting](https://github.com/arp242/goatcounter#self-hosting-goatcounter)
- [JavaScript integration](https://www.goatcounter.com/help/js)
- [SQLite VACUUM INTO](https://www.sqlite.org/lang_vacuum.html#vacuuminto)
