# Public access through Cloudflare Tunnel

The host `cloudflared` service carries public HTTPS requests to Caddy over local HTTP on port 80.
Caddy routes by hostname to Kubernetes services.
The installed tunnel configuration is `/etc/cloudflared/config.yml` on potatoserver.

Public routes are `media`, `alerts`, `wubzduh`, `jobs`, `stats`, and `cms` under `grattafiori.dev`.
Their origin is local port 80; unmatched hostnames return HTTP 404.
Miniflux and Grafana use [Tailscale](tailscale.md) and stay out of the tunnel.
Umami collection remains public so blog visitors can submit page views.

## Change a route

Update [Caddy](../caddy/Caddyfile) and the service declaration first.
From `/home/rossgrat/repos/network` on potatoserver, review and apply:

```sh
make k3s-diff
make k3s-apply
```

Add the hostname to the installed tunnel configuration and Cloudflare DNS route, then restart the host service:

```sh
sudo systemctl restart cloudflared
systemctl status cloudflared
journalctl -u cloudflared -f
```

For recovery, retain the existing tunnel UUID and credential file from protected server backups.
See [Cloudflare ingress configuration](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/configure-tunnels/local-management/configuration-file/).
