# Private access through Tailscale

Connect the client device to Tailscale, then open:

| Service | URL |
| --- | --- |
| Miniflux | `https://rss.grattafiori.dev` |
| Grafana | `https://grafana.grattafiori.dev` |

Both DNS-only A records point to potatoserver's recorded Tailscale address, `100.108.26.48`.
Access also depends on the tailnet policy.
Caddy accepts HTTPS on host port 443 and routes to the Kubernetes services in [Caddyfile](../caddy/Caddyfile).

Caddy renews certificates through a Cloudflare DNS challenge.
Retain the `CLOUDFLARE_API_TOKEN` in K3s Secret `caddy/cloudflare`, even though these services have no tunnel route.
See [Caddy's DNS challenge](https://caddyserver.com/docs/automatic-https#dns-challenge).

## Check or change access

On potatoserver, run `tailscale status` and `tailscale ip -4`.
If authentication is needed, run `sudo tailscale up --timeout=30s` and complete its login link.
Update both private DNS records if the server address changes.

Edit the repository Caddyfile, then run `make k3s-diff` and `make k3s-apply` from `/home/rossgrat/repos/network` on potatoserver.
Check the Caddy rollout:

```sh
K3S_CONFIG_FILE=/dev/null /usr/local/bin/k3s kubectl \
  --kubeconfig /home/rossgrat/.kube/potatoserver-k3s.yaml \
  rollout status deployment/caddy -n caddy --timeout=180s
```

Keep these DNS records unproxied and their hostnames out of `/etc/cloudflared/config.yml`.
Other public services, including Umami collection, retain tunnel access.
