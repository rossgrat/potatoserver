# Tailscale

Miniflux and Grafana use the tailnet, the private Tailscale network. Both services keep their existing HTTPS hostnames.

| Service | URL | Caddy destination |
|---|---|---|
| Miniflux | `https://rss.grattafiori.dev` | `miniflux:8080` |
| Grafana | `https://grafana.grattafiori.dev` | `lgtm:3000` |

Their DNS-only A records point to `100.108.26.48`, the Tailscale address of potatoserver.
Neither hostname has a Cloudflare Tunnel route. Umami remains public because its `/api/send` endpoint receives page views from website visitors.

## HTTPS

Caddy accepts private HTTPS connections on host port 443 and forwards them to each service.
Caddy obtains certificates through a DNS challenge, proof of domain ownership through DNS records.
The [DNS challenge](https://caddyserver.com/docs/automatic-https#dns-challenge) works without public access to the service.

Caddy uses the existing `caddy-dns/cloudflare` plugin and `CLOUDFLARE_API_TOKEN` from `caddy/.env`.
Keep that token available for automatic certificate renewal. Removing a tunnel route does not remove the need for Cloudflare DNS access.

The Miniflux route uses this TLS configuration:

```caddyfile
rss.grattafiori.dev {
    reverse_proxy miniflux:8080
    tls {
        dns cloudflare {env.CLOUDFLARE_API_TOKEN}
        resolvers 9.9.9.9 149.112.112.112
    }
}
```

## Access

Connect the client device to Tailscale. Open the service URL from the table above.
Access also depends on the Tailscale access policy.

On potatoserver, make sure that Tailscale reports `Running` and an assigned address:

```sh
tailscale status
tailscale ip -4
```

If Tailscale needs authentication, run this command on potatoserver:

```sh
sudo tailscale up --timeout=30s
```

Complete any login link that the command prints. If the server address changes, update both private DNS records.

## Routing changes

On potatoserver, make sure that the mounted Caddyfile is valid before reloading Caddy:

```sh
docker exec caddy caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile
docker exec caddy caddy reload --config /etc/caddy/Caddyfile --adapter caddyfile
```

Keep `rss.grattafiori.dev` and `grafana.grattafiori.dev` out of `/etc/cloudflared/config.yml`.
Keep their DNS records unproxied. Public services still use the tunnel, including Umami.
