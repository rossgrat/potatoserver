# Tailscale

Grafana is served **privately over the tailnet** instead of the public internet. The host
(`potatoserver`) is already a Tailscale node, so any device on the tailnet can reach it; nobody
else can.

## Architecture

```
Tailscale device → tailnet (WireGuard) → host:443 → Caddy (TLS) → lgtm:3000
```

`grafana.grattafiori.dev` resolves to the host's **Tailscale IP** (`100.108.26.48`), which lives in
the CGNAT range `100.64.0.0/10` and is not routable from the public internet. Caddy listens on the
host's `tailscale0` interface (it publishes `80/443` to the host) and reverse-proxies to Grafana.

## HTTPS

`.dev` is on the [HSTS preload list](https://hstspreload.org/), so browsers hard-force HTTPS for
every `.dev` hostname — plain http is refused. Cloudflare used to terminate TLS at its edge; now
that Grafana is off the tunnel, **Caddy terminates TLS itself**.

The host isn't publicly reachable, so HTTP-01 / TLS-ALPN-01 ACME challenges can't work. Caddy
instead uses the **Cloudflare DNS-01 challenge** to get a real Let's Encrypt cert for
`grafana.grattafiori.dev`. This needs:

- A Caddy build that includes the `caddy-dns/cloudflare` plugin — see [`caddy/Dockerfile`](../caddy/Dockerfile).
- A Cloudflare API token with **Zone → DNS → Edit** on `grattafiori.dev`, provided to Caddy as
  `CLOUDFLARE_API_TOKEN` via `caddy/.env` (gitignored — never committed).

The relevant Caddyfile block:

```
grafana.grattafiori.dev {
    reverse_proxy lgtm:3000
    tls {
        dns cloudflare {env.CLOUDFLARE_API_TOKEN}
    }
}
```

## How it was set up

1. **Cloudflare DNS** — `grafana` is a **DNS-only** (grey cloud) A record → the host's Tailscale IP:

   | Type | Name | Content | Proxy |
   |---|---|---|---|
   | A | `grafana` | `100.108.26.48` | DNS only |

   This is what removes Grafana from the public internet: the hostname resolves to an unroutable
   CGNAT address that only tailnet devices can reach.

2. **cloudflared** — removed the `grafana.grattafiori.dev` ingress rule from
   `/etc/cloudflared/config.yml` and restarted the service.

3. **Cloudflare API token** — created a token (Zone:DNS:Edit on `grattafiori.dev`) and wrote it to
   `caddy/.env` on the server:

   ```
   CLOUDFLARE_API_TOKEN=<token>
   ```

4. **Caddy** — switched the `grafana.grattafiori.dev` block to TLS via the Cloudflare DNS challenge,
   gave the data volume to uid 1000 so Caddy can write certs, and rebuilt the custom image:

   ```bash
   docker run --rm -v caddy_caddy_data:/data alpine chown -R 1000:1000 /data
   cd caddy && docker compose up -d --build
   ```

## Access

From any device on the tailnet:

```
https://grafana.grattafiori.dev
```

Devices not on the tailnet get a `100.x` address that routes nowhere — Grafana is unreachable.

## Notes

- The host's Tailscale IP (`100.108.26.48`) is stable per-node but will change if the node is
  removed and re-added to the tailnet. Update the Cloudflare A record if that happens.
- To check the host's tailnet IP: `tailscale ip -4` on the server.
- Cert renewal is automatic (Caddy), as long as the Cloudflare token stays valid.
