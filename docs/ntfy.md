# ntfy

Authenticated push notifications at `https://alerts.grattafiori.dev`.
The [K3s declaration](../k3s/ntfy.yaml) runs namespace `ntfy`; the ntfy.sh relay supplies iOS push delivery.
Default access is `deny-all`.

## Users and tokens

On potatoserver, define this helper:

```bash
ntfyctl() {
  K3S_CONFIG_FILE=/dev/null /usr/local/bin/k3s kubectl \
    --kubeconfig /home/rossgrat/.kube/potatoserver-k3s.yaml \
    exec -it -n ntfy deployment/ntfy -- ntfy "$@"
}
```

Use `ntfyctl user add USER`, `ntfyctl access USER TOPIC read-write`, and `ntfyctl token add USER` to configure a publisher.
Use `read-only` for subscribers and `reset` to remove topic access.
The `user` and `token` subcommands also list and remove entries; `user add --role=admin USER` creates an administrator.

Replace `TOKEN` and `TOPIC` with the generated token and permitted topic:

```sh
curl -H "Authorization: Bearer TOKEN" -d "Hello!" https://alerts.grattafiori.dev/TOPIC
```

Optional headers include `Title`, `Click`, and `Priority` from 1 to 5; 3 is the default.
On iOS, add the topic in the ntfy app with this server URL and the user's credentials.

## Retained data

Authentication lives in `/var/lib/ntfy/auth.db` on claim `ntfy/auth`.
Nightly backups use SQLite's online backup API and retain volume data and Kubernetes declarations on potatoserver.
Message history is in memory; the deployment does not enable a persistent message cache.
Retired Docker data remains in server-local retirement backups.
See [operations](operations.md) for recovery tests and [ntfy configuration](https://docs.ntfy.sh/config/) for command details.
