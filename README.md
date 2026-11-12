# potatoserver

Potatoserver provides public services through [Cloudflare Tunnel](docs/cloudflare-tunnel.md) and private services through [Tailscale](docs/tailscale.md).

## Services

| Service | URL | Description |
|---|---|---|
| Pages CMS | `cms.grattafiori.dev` | Blog editor with GitHub sign-in |
| Miniflux | `rss.grattafiori.dev` | RSS reader, accessible through Tailscale |
| Umami | `stats.grattafiori.dev` | Blog analytics with a dashboard that requires login |
| Job Board | `jobs.grattafiori.dev` | Job search dashboard and background worker |
| Media | `media.grattafiori.dev` | Static media file server |
| ntfy | `alerts.grattafiori.dev` | Push notification server |
| wubzduh | `wubzduh.grattafiori.dev` | New music release feed |
| Grafana (lgtm) | `grafana.grattafiori.dev` | Observability — **tailnet-only**, see [docs/tailscale.md](docs/tailscale.md) |
| Caddy | — | Reverse proxy (hostname-based routing) |
| PostgreSQL | — | Separate databases for Miniflux, Umami, CMS, Wubzduh, and Job Board |

## Architecture

```
Public services:   Internet → Cloudflare Edge (TLS/WAF/DDoS) → Tunnel (QUIC) → cloudflared → Caddy:80 → service
Private services: Tailscale device → tailnet → host:443 → Caddy (TLS) → Kubernetes service
```

Miniflux and Grafana use the host's Tailscale IP.
Miniflux, Umami, CMS, Wubzduh, Job Board, ntfy, Caddy, and LGTM run on K3s.
Caddy exposes host ports 80 and 443 and routes requests through Kubernetes service DNS.
Tailscale and Cloudflare Tunnel run as host services.
The cleanup removed Docker packages, data, bridges, and migration staging directories.
Umami remains public so website visitors can send page views to its `/api/send` endpoint.

## Setup

The K3s setup and recovery procedures are in [the operations guide](docs/operations.md).
Restore private credentials from the backups on potatoserver before starting a replacement host.
Run `make up` from `/home/rossgrat/repos/network` on the configured server.
The repository alone does not contain database contents, credentials, or the imported CMS image.

## Usage

```bash
make up        # Start all services
make down      # Stop all services
make restart   # Restart all services
make logs      # View Caddy logs
make k3s-logs SERVICE=job-board  # View K3s application logs
make k3s-diff   # Compare declared and running K3s configuration
make k3s-apply  # Apply declared K3s configuration
make deploy    # Pull configuration and apply it on the server
```

## Configuration Files

- `caddy/Caddyfile`: Routing configuration. Public tunnel routes use `http://`. Private routes use Caddy HTTPS.
- `kustomization.yaml`: Complete K3s deployment and generated configuration maps
- `k3s/*.yaml`: Application versions, storage, probes, and network rules
- `ops/`: Deployment, backup, and health commands
- `ops/lib/`: Internal helpers used by those commands
- `tests/recovery/`: Isolated application, ntfy, and cluster recovery tests
- `systemd/`: Host unit files, drop-ins, and installed helper sources
- `k3s/ntfy.yaml`: ntfy server configuration and retained storage
- `/etc/cloudflared/config.yml` — Tunnel config (on server)

## Docs

- [Operations](docs/operations.md): Deployment, recovery, health checks, and server-local backups
- [Pages CMS](docs/pages-cms.md): Blog editing, deployment, and backups

- [Cloudflare Tunnel](docs/cloudflare-tunnel.md) — Tunnel setup, DNS records, management commands
- [Tailscale](docs/tailscale.md): Private access to Miniflux and Grafana
- [ntfy](docs/ntfy.md) — Push notification server setup, auth, and usage
- [Umami](docs/umami.md): Blog analytics, privacy controls, and backups

## Security

- Never commit `.env` files — they contain credentials
- Logs are excluded via `.gitignore`
- K3s network rules restrict database access to each application's namespace
- All public traffic goes through Cloudflare (DDoS protection, WAF, bot filtering)
