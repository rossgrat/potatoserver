# ntfy

Self-hosted push notification server. Runs on `caddy-network` behind Caddy, accessible at `https://alerts.grattafiori.dev`. Uses the ntfy.sh upstream relay for iOS push delivery via APNs.

## Architecture

```
Phone (ntfy app) ← APNs ← ntfy.sh relay ← ntfy server (caddy-network)
                                                ↑
                                          services (e.g. stock-checker)
```

## Auth

Default access is `deny-all`. All users and tokens are stored in `/var/lib/ntfy/auth.db` (persisted via `ntfy-auth` Docker volume).

### User management

```bash
# Add a user
docker exec -it ntfy ntfy user add <username>

# Add an admin user
docker exec -it ntfy ntfy user add --role=admin <username>

# Delete a user
docker exec -it ntfy ntfy user del <username>

# List users
docker exec -it ntfy ntfy user list
```

### Access control

```bash
# Grant a user read-write access to a topic
docker exec -it ntfy ntfy access <username> <topic> read-write

# Grant read-only access
docker exec -it ntfy ntfy access <username> <topic> read-only

# Remove access
docker exec -it ntfy ntfy access <username> <topic> reset
```

### Tokens

Services authenticate with bearer tokens instead of username/password.

```bash
# Generate a token for a user
docker exec -it ntfy ntfy token add <username>

# List tokens
docker exec -it ntfy ntfy token list

# Remove a token
docker exec -it ntfy ntfy token remove <token>
```

## Publishing

```bash
# Simple message
curl -H "Authorization: Bearer <token>" -d "Hello!" https://alerts.grattafiori.dev/<topic>

# With title, priority, and click action
curl -H "Authorization: Bearer <token>" \
     -H "Title: Alert" \
     -H "Priority: 5" \
     -H "Click: https://example.com" \
     -d "Something happened" \
     https://alerts.grattafiori.dev/<topic>
```

Priority levels: 1 (min), 2 (low), 3 (default), 4 (high), 5 (urgent — bypasses DND).

## Subscribing (iOS)

1. Install the ntfy app
2. Tap **+** to subscribe
3. Topic: `<topic>`
4. Server: `https://alerts.grattafiori.dev`
5. Enter username and password when prompted
