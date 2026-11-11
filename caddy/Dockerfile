FROM caddy:2.11.7-builder@sha256:bf6a7d38add2508b7d2e3e3f40cf2af399214f143c0fa3daa51f254e01f8d293 AS builder
RUN xcaddy build v2.11.7 --with github.com/caddy-dns/cloudflare@v0.2.4

FROM caddy:2.11.7-alpine@sha256:eb4d35b7452d1ab6171fbdbe8d9275b2301dad6dad92115d91e19fb9b24d510f
COPY --from=builder /usr/bin/caddy /usr/bin/caddy
