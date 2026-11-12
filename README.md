# potatoserver

Configuration for potatoserver, my home server.
Applications run in K3s. Caddy routes requests to them.
Cloudflare Tunnel provides public access. Tailscale provides private access.

| Service | Hostname | Access |
| --- | --- | --- |
| Pages CMS | `cms.grattafiori.dev` | Owner sign-in |
| Miniflux | `rss.grattafiori.dev` | Tailscale |
| Umami | `stats.grattafiori.dev` | Public collection, dashboard login |
| Job Board | `jobs.grattafiori.dev` | Application login |
| Media | `media.grattafiori.dev` | Public |
| ntfy | `alerts.grattafiori.dev` | Authenticated topics |
| wubzduh | `wubzduh.grattafiori.dev` | Public |
| Grafana | `grafana.grattafiori.dev` | Tailscale |

## Operate

On the configured server, work from `/home/rossgrat/repos/network`:

```sh
make k3s-diff
make k3s-apply
make k3s-logs SERVICE=job-board
```

Read [operations](docs/operations.md) before deployment, backup, recovery, or host replacement.
The repository does not contain database contents, credentials, or the imported CMS image.
Keep `.env` files and protected backups out of Git.

[kustomization.yaml](kustomization.yaml) lists the Kubernetes resources.
[k3s](k3s) defines application versions and storage. [Caddyfile](caddy/Caddyfile) defines routing.
Cloudflare Tunnel and Tailscale run as host services.

Service guides: [CMS](docs/pages-cms.md), [Umami](docs/umami.md), [ntfy](docs/ntfy.md), [Cloudflare Tunnel](docs/cloudflare-tunnel.md), and [Tailscale](docs/tailscale.md).
