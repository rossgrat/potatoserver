#!/usr/bin/env bash
set -euo pipefail
umask 077
((EUID == 0))
script_dir=$(cd -- "$(dirname -- "$0")" && pwd)
target=/home/rossgrat/backups/k3s-state-$(date -u +%Y%m%dT%H%M%SZ)
mkdir "$target"
docker run --rm --network none --read-only --memory 256m --cpus 1 \
  -v /var/lib/rancher/k3s/server/db:/source/db:ro \
  -v /var/lib/rancher/k3s/server/token:/source/token:ro \
  -v /etc/rancher/k3s:/configuration:ro \
  -v "$target:/backup" -v "$script_dir/backup.mjs:/backup.mjs:ro" \
  --entrypoint node "$(cat "$script_dir/backup-image")" /backup.mjs
tar -czf "$target/cluster-backup.tar.gz" -C "$target/root" \
  var/lib/rancher/k3s/server/db var/lib/rancher/k3s/server/token etc/rancher/k3s
gzip -t "$target/cluster-backup.tar.gz"
rm -rf -- "$target/root"
cd "$target"
sha256sum cluster-backup.tar.gz > cluster-backup.sha256
chown -R rossgrat:rossgrat "$target"
printf 'K3s state backup saved to %s\n' "$target"
