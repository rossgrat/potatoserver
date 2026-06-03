# potatoserver

Home server infrastructure exposed to the internet via [Cloudflare Tunnel](docs/cloudflare-tunnel.md).

## Services

| Service | URL | Description |
|---|---|---|
| Miniflux | `rss.grattafiori.dev` | RSS reader |
| Media | `media.grattafiori.dev` | Static media file server |
| ntfy | `alerts.grattafiori.dev` | Push notification server |
| wubzduh | `wubzduh.grattafiori.dev` | New music release feed |
| Grafana (lgtm) | `grafana.grattafiori.dev` | Observability — **tailnet-only**, see [docs/tailscale.md](docs/tailscale.md) |
| Caddy | — | Reverse proxy (hostname-based routing) |
| PostgreSQL | — | Database backend for Miniflux |

## Architecture

```
Public services:   Internet → Cloudflare Edge (TLS/WAF/DDoS) → Tunnel (QUIC) → cloudflared → Caddy:80 → service
Private (Grafana): Tailscale device → tailnet → host:80 → Caddy → lgtm:3000
```

Public services have no open inbound ports and no exposed home IP. Grafana is not on the public
internet at all — its hostname resolves to the host's Tailscale IP, so only tailnet devices can reach it.

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

- `caddy/Caddyfile` — Reverse proxy config (use `http://` prefix, Cloudflare handles TLS)
- `caddy/docker-compose.yml` — Caddy container
- `miniflux/docker-compose.yml` — Miniflux + PostgreSQL containers
- `ntfy/docker-compose.yml` — ntfy notification server container
- `ntfy/server.yml` — ntfy server config
- `/etc/cloudflared/config.yml` — Tunnel config (on server)

## Docs

- [Cloudflare Tunnel](docs/cloudflare-tunnel.md) — Tunnel setup, DNS records, management commands
- [Tailscale](docs/tailscale.md) — How Grafana is served privately over the tailnet
- [ntfy](docs/ntfy.md) — Push notification server setup, auth, and usage

## Security

- Never commit `.env` files — they contain credentials
- Logs are excluded via `.gitignore`
- Miniflux database is on an internal-only Docker network
- All public traffic goes through Cloudflare (DDoS protection, WAF, bot filtering)
