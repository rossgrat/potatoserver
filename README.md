# potatoserver

Potatoserver provides public services through [Cloudflare Tunnel](docs/cloudflare-tunnel.md) and private services through [Tailscale](docs/tailscale.md).

## Services

| Service | URL | Description |
|---|---|---|
| Pages CMS | `cms.grattafiori.dev` | Blog editor with GitHub sign-in |
| Miniflux | `rss.grattafiori.dev` | RSS reader, accessible through Tailscale |
| GoatCounter | `stats.grattafiori.dev` | Blog analytics with a private dashboard |
| Media | `media.grattafiori.dev` | Static media file server |
| ntfy | `alerts.grattafiori.dev` | Push notification server |
| wubzduh | `wubzduh.grattafiori.dev` | New music release feed |
| Grafana (lgtm) | `grafana.grattafiori.dev` | Observability — **tailnet-only**, see [docs/tailscale.md](docs/tailscale.md) |
| Caddy | — | Reverse proxy (hostname-based routing) |
| PostgreSQL | — | Database backend for Miniflux |

## Architecture

```
Public services:   Internet → Cloudflare Edge (TLS/WAF/DDoS) → Tunnel (QUIC) → cloudflared → Caddy:80 → service
Private (Grafana): Tailscale device → tailnet → host:443 → Caddy (TLS) → lgtm:3000
```

Miniflux and Grafana use the host's Tailscale IP. Miniflux uses the same private HTTPS path as Grafana, with `miniflux:8080` as its destination.
GoatCounter remains public so website visitors can send analytics to its `/count` endpoint.

## Setup

1. Copy and configure environment variables:
   ```bash
   cp .env.example miniflux/.env
   nvim miniflux/.env
   ```

2. Start services:
   ```bash
   make up
   ```

3. Set up Cloudflare Tunnel — see [docs/cloudflare-tunnel.md](docs/cloudflare-tunnel.md)

## Usage

```bash
make up        # Start all services
make down      # Stop all services
make restart   # Restart all services
make logs      # View logs
make deploy    # Deploy to server (git pull + restart)
```

## Configuration Files

- `caddy/Caddyfile`: Routing configuration. Public tunnel routes use `http://`. Private routes use Caddy HTTPS.
- `caddy/docker-compose.yml` — Caddy container
- `miniflux/docker-compose.yml` — Miniflux + PostgreSQL containers
- `ntfy/docker-compose.yml` — ntfy notification server container
- `ntfy/server.yml` — ntfy server config
- `goatcounter/docker-compose.yml` — GoatCounter and its SQLite volume
- `/etc/cloudflared/config.yml` — Tunnel config (on server)

## Docs

- [Pages CMS](docs/pages-cms.md): Blog editing, deployment, and backups
- [Deployment overrides](docs/deployment-overrides.md): Existing application versions and database mounts

- [Cloudflare Tunnel](docs/cloudflare-tunnel.md) — Tunnel setup, DNS records, management commands
- [Tailscale](docs/tailscale.md): Private access to Miniflux and Grafana
- [Hosting on Tailscale](docs/hosting-on-tailscale.md) — General patterns for putting a service on the tailnet
- [ntfy](docs/ntfy.md) — Push notification server setup, auth, and usage
- [GoatCounter](docs/goatcounter.md) — Blog analytics, deployment, and backups

## Security

- Never commit `.env` files — they contain credentials
- Logs are excluded via `.gitignore`
- Miniflux database is on an internal-only Docker network
- All public traffic goes through Cloudflare (DDoS protection, WAF, bot filtering)
