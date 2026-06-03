# Tailscale

Grafana is served **privately over the tailnet** instead of the public internet. The host
(`potatoserver`) is already a Tailscale node, so any device on the tailnet can reach it; nobody
else can.

## Architecture

```
Tailscale device → tailnet (WireGuard) → host:80 → Caddy → lgtm:3000
```

`grafana.grattafiori.dev` resolves to the host's **Tailscale IP** (`100.108.26.48`), which lives in
the CGNAT range `100.64.0.0/10` and is not routable from the public internet. Caddy already listens
on the host's `tailscale0` interface (it publishes `80:443` to the host), so no port changes are
needed — the Caddy `grafana.grattafiori.dev` block handles the routing and security headers.

Traffic is encrypted end-to-end by WireGuard, so the Caddy block stays plain `http://` — no TLS
cert for the hostname is required.

## How it was set up

1. **Cloudflare DNS** — replaced the proxied tunnel record for `grafana` with a **DNS-only** A
   record pointing at the host's Tailscale IP:

   | Type | Name | Content | Proxy |
   |---|---|---|---|
   | A | `grafana` | `100.108.26.48` | DNS only (grey cloud) |

   This is what removes Grafana from the public internet: the hostname now resolves to an
   unroutable CGNAT address that only tailnet devices can reach.

2. **cloudflared** — removed the `grafana.grattafiori.dev` ingress rule from
   `/etc/cloudflared/config.yml` and restarted the service:

   ```bash
   sudo nano /etc/cloudflared/config.yml   # delete the grafana ingress block
   sudo systemctl restart cloudflared
   ```

3. **Caddy** — no change; the existing `grafana.grattafiori.dev` block routes to `lgtm:3000`.

## Access

From any device on the tailnet:

```
http://grafana.grattafiori.dev
```

Devices not on the tailnet get a `100.x` address that routes nowhere — Grafana is unreachable.

## Notes

- The host's Tailscale IP (`100.108.26.48`) is stable per-node but will change if the node is
  removed and re-added to the tailnet. Update the Cloudflare A record if that happens.
- To check the host's tailnet IP: `tailscale ip -4` on the server.
