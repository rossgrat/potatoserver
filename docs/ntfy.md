# ntfy

ntfy runs in the K3s namespace `ntfy` at `https://alerts.grattafiori.dev`.
Caddy forwards requests to `ntfy.ntfy.svc.cluster.local:8080`.
The ntfy.sh relay provides iOS push delivery through APNs.

On potatoserver, define this helper for the commands below:

```bash
ntfyctl() {
  K3S_CONFIG_FILE=/dev/null /usr/local/bin/k3s kubectl \
    --kubeconfig /home/rossgrat/.kube/potatoserver-k3s.yaml \
    exec -it -n ntfy deployment/ntfy -- ntfy "$@"
}
```

## Auth

Default access is `deny-all`. All users and tokens are stored in `/var/lib/ntfy/auth.db` on the retained K3s claim `ntfy/auth`.

### User management

```bash
# Add a user
ntfyctl user add <username>

# Add an admin user
ntfyctl user add --role=admin <username>

# Delete a user
ntfyctl user del <username>

# List users
ntfyctl user list
```

### Access control

```bash
# Grant a user read-write access to a topic
ntfyctl access <username> <topic> read-write

# Grant read-only access
ntfyctl access <username> <topic> read-only

# Remove access
ntfyctl access <username> <topic> reset
```

### Tokens

Services authenticate with bearer tokens instead of username/password.

```bash
# Generate a token for a user
ntfyctl token add <username>

# List tokens
ntfyctl token list

# Remove a token
ntfyctl token remove <token>
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

## Recovery

Nightly backups use SQLite's online backup API for the active authentication database.
The backups also contain the cache volume and K3s declarations.
All backups stay on potatoserver. The retired Docker data is archived in server-local cleanup backups.
Message history remains in memory because the deployment does not set a persistent message cache.
Isolated publication, subscription, and pod replacement tests passed during migration.
A test notification reached the existing phone subscription after the move.

See [the operations guide](operations.md) and [ntfy configuration](https://docs.ntfy.sh/config/).
