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
| `rss` | Miniflux (via tunnel) | Proxied |
| `media` | CloudFront CDN | DNS-only |
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

Config lives at `/etc/cloudflared/config.yml`:

```yaml
tunnel: <TUNNEL_UUID>
credentials-file: /etc/cloudflared/<TUNNEL_UUID>.json

ingress:
  - hostname: rss.grattafiori.dev
    service: http://localhost:80
  - service: http_status:404
```

### Add DNS routes

```bash
cloudflared tunnel route dns potatoserver rss.grattafiori.dev
```

### Run as service

```bash
sudo cloudflared service install
sudo systemctl enable cloudflared
sudo systemctl start cloudflared
```

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
