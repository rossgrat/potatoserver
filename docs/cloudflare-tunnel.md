# Cloudflare Tunnel

Exposes potatoserver to the internet via Cloudflare Tunnel. The server makes outbound-only connections to Cloudflare's edge — no open inbound ports, no exposed home IP, no DDNS needed.

## Architecture

```
Internet → Cloudflare Edge (DDoS/WAF/TLS) → Tunnel (QUIC) → cloudflared → Caddy:80 → services
```

## Domain: grattafiori.dev

- **Registrar**: Squarespace
- **DNS/Nameservers**: Cloudflare (`cora.ns.cloudflare.com`, `hugh.ns.cloudflare.com`)
- **SSL/TLS**: Full (set in Cloudflare dashboard)

### DNS Records

| Subdomain | Purpose | Proxy |
|---|---|---|
| `ross` | GitHub Pages portfolio | Proxied |
| `cms` | Pages CMS with GitHub sign-in (via tunnel) | Proxied |
| `rss` | Miniflux through Tailscale | DNS-only A record |
| `grafana` | Grafana through Tailscale | DNS-only A record |
| `media` | Static media files (via tunnel) | Proxied |
| `alerts` | ntfy notifications (via tunnel) | Proxied |
| `jobs` | Job Board (via tunnel) | Proxied |
| `wubzduh` | Music release feed (via tunnel) | Proxied |
| `stats` | GoatCounter dashboard and collection (via tunnel) | Proxied |
| `@` (MX/TXT) | ProtonMail email | DNS-only |

## Setup

### Install cloudflared

```bash
curl -L https://pkg.cloudflare.com/cloudflare-main.gpg | sudo tee /usr/share/keyrings/cloudflare-main.gpg >/dev/null
echo "deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/cloudflared.list
sudo apt update && sudo apt install -y cloudflared
```

### Create tunnel

```bash
cloudflared tunnel login
cloudflared tunnel create potatoserver
```

### Configure

The configuration lives at `/etc/cloudflared/config.yml`:

```yaml
tunnel: <TUNNEL_UUID>
credentials-file: /etc/cloudflared/<TUNNEL_UUID>.json

ingress:
  - hostname: media.grattafiori.dev
    service: http://localhost:80
  - hostname: alerts.grattafiori.dev
    service: http://localhost:80
  - hostname: wubzduh.grattafiori.dev
    service: http://localhost:80
  - hostname: jobs.grattafiori.dev
    service: http://localhost:80
  - hostname: stats.grattafiori.dev
    service: http://localhost:80
  - hostname: cms.grattafiori.dev
    service: http://127.0.0.1:3030
  - service: http_status:404
```

Miniflux and Grafana use private Tailscale access. Their DNS-only A records point to `100.108.26.48`.
Keep both hostnames out of the tunnel configuration. See [tailscale.md](tailscale.md).

GoatCounter remains on the tunnel because public visitors send analytics to its `/count` endpoint.
Pages CMS uses the same tunnel and forwards directly to its loopback port, without Caddy.
See [Pages CMS](pages-cms.md) for its installation script and GitHub sign-in.

### Add DNS routes

```bash
cloudflared tunnel route dns potatoserver media.grattafiori.dev
cloudflared tunnel route dns potatoserver alerts.grattafiori.dev
cloudflared tunnel route dns potatoserver wubzduh.grattafiori.dev
cloudflared tunnel route dns potatoserver jobs.grattafiori.dev
cloudflared tunnel route dns potatoserver stats.grattafiori.dev
cloudflared tunnel route dns potatoserver cms.grattafiori.dev
```

### Run as service

```bash
sudo cloudflared service install
sudo systemctl enable cloudflared
sudo systemctl start cloudflared
```

OR

```
sudo systemctl restart cloudflared
```

Restart cloudflared after you change `/etc/cloudflared/config.yml`.

## Management

```bash
# Check tunnel status
systemctl status cloudflared

# View logs
journalctl -u cloudflared -f

# List tunnels
cloudflared tunnel list

# Add a new subdomain
# 1. Add ingress rule to /etc/cloudflared/config.yml
# 2. cloudflared tunnel route dns potatoserver <subdomain>.grattafiori.dev
# 3. Add server block to caddy/Caddyfile (use http:// prefix)
# 4. sudo systemctl restart cloudflared
```
