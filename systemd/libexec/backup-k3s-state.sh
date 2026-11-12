#!/usr/bin/env bash
set -euo pipefail
umask 077

((EUID == 0))
script_dir=$(cd -- "$(dirname -- "$0")" && pwd)
target=/home/rossgrat/backups/k3s-state-$(date -u +%Y%m%dT%H%M%SZ)
mkdir "$target"
/usr/local/libexec/potatoserver-runtime/node-24.22.2 "$script_dir/backup-k3s-state.mjs" "$target"
tar -czf "$target/cluster-backup.tar.gz" -C "$target/root" \
  var/lib/rancher/k3s/server/db var/lib/rancher/k3s/server/token etc/rancher/k3s
gzip -t "$target/cluster-backup.tar.gz"
rm -rf -- "$target/root"
cd "$target"
sha256sum cluster-backup.tar.gz >cluster-backup.sha256
chown -R rossgrat:rossgrat "$target"
printf 'K3s state backup saved to %s\n' "$target"
