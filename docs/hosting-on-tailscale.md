# Hosting services on Tailscale

A short reference for putting a service on the tailnet (private) instead of the public internet.
For the concrete Grafana setup that uses pattern 3 below, see [tailscale.md](tailscale.md).

## The mental model

Three facts do all the work:

1. Every Tailscale node gets a stable `100.x` IP in the CGNAT range `100.64.0.0/10`. This host is
   `100.108.26.48`.
2. That range is **not routable on the public internet** — a packet to a `100.x` address only goes
   anywhere if your device is on the tailnet. So "behind Tailscale" just means "addressed by its
   `100.x` IP."
3. Every node also gets a MagicDNS name (`potatoserver.tail55d221.ts.net`), and Tailscale can issue
   real Let's Encrypt certs for `*.ts.net` names automatically.

So hosting is two independent questions:

- **Addressing** — how does the client find the `100.x` IP? (raw IP, MagicDNS name, or your own domain)
- **TLS** — who provides the cert? (none/http, Tailscale's automatic `.ts.net` cert, or your own)

## The menu

| You want… | Use |
|---|---|
| Quick internal access, don't care about HTTPS/URL | Publish a host port → hit `100.x:PORT` or the MagicDNS name |
| Trusted HTTPS, fine with a `.ts.net` URL | `tailscale serve` — **lowest friction** |
| Trusted HTTPS on **your own** domain | DNS-only A record → `100.x` + your own DNS-01 cert |
| Reach non-Tailscale devices on a LAN | Subnet router (`--advertise-routes`) |
| Put one container on the tailnet without host changes | `tailscale/tailscale` sidecar container |
| Actually expose to the public | `tailscale funnel` (the opposite of private) |

### 1. Publish a port
If the host is on the tailnet and the service listens on a host port, any tailnet device can already
reach `http://100.108.26.48:PORT` (or `http://potatoserver.tail55d221.ts.net:PORT`). Nothing else
needed.

### 2. `tailscale serve` (recommended default for HTTPS)
```
tailscale serve --bg 3000        # reverse-proxy localhost:3000 over HTTPS
```
Tailscale provisions a real, trusted Let's Encrypt cert for the node's `.ts.net` name and serves it
tailnet-only. No token, no cert management, no custom image. Only cost: the URL is a `.ts.net` name,
not your own domain.

### 3. Your own domain → tailnet IP (what Grafana uses)
Point a hostname at the `100.x` IP with a **DNS-only** A record (e.g. Cloudflare grey cloud). You
keep a pretty hostname, but Tailscale can't issue a cert for your domain, so you provide TLS — and
because the host isn't publicly reachable, the only ACME challenge that works is **DNS-01** (needs a
DNS-provider API token). See [tailscale.md](tailscale.md) for the full Caddy setup.

## Gotchas (these bit us — see the Grafana migration)

- **`.dev` / `.app` and other Google TLDs are HSTS-preloaded** → browsers hard-force HTTPS; plain
  http won't load. Self-hosting on such a domain *requires* real HTTPS. `tailscale serve` sidesteps
  this since it hands you a cert.
- **A private host can only get certs via DNS-01.** No public IP means no HTTP-01 / TLS-ALPN-01.
- **Containers don't inherit the host's DNS.** Docker can't use the host's `127.0.0.53` stub; if
  external resolvers are blocked or the router hangs on NXDOMAIN, ACME DNS lookups fail. Pin the
  ACME `resolvers` to a reachable, well-behaved resolver (we use Quad9 `9.9.9.9`).
- **CGNAT IPs are stable but not permanent** — a node's `100.x` changes if you remove and re-add the
  machine. Anything that hardcodes it (like a DNS A record) must be updated then. MagicDNS names
  don't have this problem.
- **MagicDNS wires into the host resolver**, which can muddy *public* DNS resolution on a tailnet
  host — worth knowing when debugging resolution.
