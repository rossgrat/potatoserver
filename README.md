# Network Services

Home server infrastructure with Caddy reverse proxy and Miniflux RSS reader.

## Services

- **Caddy**: Reverse proxy with automatic HTTPS
- **Miniflux**: Lightweight RSS reader
- **PostgreSQL**: Database backend for Miniflux

## Prerequisites

- Docker and Docker Compose
- Make (optional, for convenience commands)

## Setup

1. Copy the example environment file:
   ```bash
   cp .env.example .env
   ```

2. Edit `.env` with your actual credentials:
   ```bash
   nano .env
   ```

   Required variables:
   - `POSTGRES_USER`: Database username (default: miniflux)
   - `POSTGRES_PASSWORD`: **Change this to a secure password**
   - `POSTGRES_DB`: Database name (default: miniflux)
   - `ADMIN_USERNAME`: Miniflux admin username
   - `ADMIN_PASSWORD`: **Change this to a secure admin password**

3. Start all services:
   ```bash
   make up
   ```

   Or manually:
   ```bash
   docker network create --driver bridge caddy-network
   cd caddy && docker-compose up -d
   cd ../miniflux && docker-compose up -d
   ```

## Usage

### Start services
```bash
make up
```

### Stop services
```bash
make down
```

### Restart services
```bash
make restart
```

### View logs
```bash
make logs
```

## Security Notes

- **Never commit `.env` files** - they contain sensitive credentials
- Logs are excluded from version control (`.gitignore`)
- Miniflux is configured with internal network isolation
- Review `cloudflare-architecture-analysis.md` for deployment security considerations

## Architecture

```
Internet
   │
   ├─ Caddy (Port 80/443)
   │     └─ Reverse proxy to Miniflux
   │
   └─ Miniflux (Internal port 8080)
         └─ PostgreSQL (Internal network only)
```

## Configuration Files

- `caddy/Caddyfile`: Caddy reverse proxy configuration
- `caddy/docker-compose.yml`: Caddy container configuration
- `miniflux/docker-compose.yml`: Miniflux and PostgreSQL containers
- `Makefile`: Convenience commands

## Additional Documentation

See `cloudflare-architecture-analysis.md` for detailed security considerations and deployment architectures for exposing services to the internet.

## License

Personal infrastructure configuration.
