# Cloudflare Tunnel

The host `cloudflared` service carries public requests to Caddy on port 80.
Caddy runs in K3s and forwards each hostname to its Kubernetes service.
Cloudflare terminates public HTTPS. The tunnel connects to Caddy over local HTTP.

## Current routes

The installed configuration is `/etc/cloudflared/config.yml`.
It contains these routes:

| Hostname | Local origin |
|---|---|
| `media.grattafiori.dev` | `http://localhost:80` |
| `alerts.grattafiori.dev` | `http://localhost:80` |
| `wubzduh.grattafiori.dev` | `http://localhost:80` |
| `jobs.grattafiori.dev` | `http://localhost:80` |
| `stats.grattafiori.dev` | `http://localhost:80` |
| `cms.grattafiori.dev` | `http://127.0.0.1:80` |

The final ingress rule returns HTTP 404 for unmatched hostnames.
Miniflux and Grafana use [Tailscale](tailscale.md). Their hostnames have no tunnel routes.
Umami remains public because website visitors send page views to `/api/send`.

## Routing changes

Edit `caddy/Caddyfile` and the service declaration before adding a tunnel hostname.
Review and apply the Kubernetes changes on potatoserver:

```sh
make k3s-diff
make k3s-apply
```

Add the hostname to `/etc/cloudflared/config.yml` and its Cloudflare DNS route.
Keep the existing tunnel UUID and credential file when recovering this host.
Both are included in the protected server backups.

After changing the tunnel configuration on potatoserver, restart its host service:

```sh
sudo systemctl restart cloudflared
systemctl status cloudflared
```

Read the service logs on potatoserver:

```sh
journalctl -u cloudflared -f
```

See [Cloudflare ingress configuration](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/configure-tunnels/local-management/configuration-file/).
