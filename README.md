# potatoserver

Home server infrastructure exposed to the internet via [Cloudflare Tunnel](docs/cloudflare-tunnel.md).

## Services

| Service | URL | Description |
|---|---|---|
| Miniflux | `rss.grattafiori.dev` | RSS reader |
| Media | `media.grattafiori.dev` | Static media file server |
| Caddy | — | Reverse proxy (hostname-based routing) |
| PostgreSQL | — | Database backend for Miniflux |

## Architecture

```
Internet → Cloudflare Edge (TLS/WAF/DDoS) → Tunnel (QUIC) → cloudflared → Caddy:80 → services
```

No open inbound ports. No exposed home IP.

## Setup

1. Copy and configure environment variables:
   ```bash
   cp .env.example miniflux/.env
   nano miniflux/.env
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
```

## Configuration Files

- `caddy/Caddyfile` — Reverse proxy config (use `http://` prefix, Cloudflare handles TLS)
- `caddy/docker-compose.yml` — Caddy container
- `miniflux/docker-compose.yml` — Miniflux + PostgreSQL containers
- `/etc/cloudflared/config.yml` — Tunnel config (on server)

## Docs

- [Cloudflare Tunnel](docs/cloudflare-tunnel.md) — Tunnel setup, DNS records, management commands

## Security

- Never commit `.env` files — they contain credentials
- Logs are excluded via `.gitignore`
- Miniflux database is on an internal-only Docker network
- All public traffic goes through Cloudflare (DDoS protection, WAF, bot filtering)
