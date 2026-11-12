#!/usr/bin/env bash
set -euo pipefail
umask 077

[[ $EUID == 0 ]]
backup_dir=$(realpath -e "${1:?Pass the existing baseline backup directory}")
case "$backup_dir" in
  /home/rossgrat/backups/k3s-*) ;;
  *) exit 2 ;;
esac
[[ $(stat -c %U "$backup_dir") == rossgrat ]]
tar -czf "$backup_dir/host-secrets.tar.gz" -C / \
  etc/cloudflared etc/netplan var/lib/tailscale/tailscaled.state
chown rossgrat:rossgrat "$backup_dir/host-secrets.tar.gz"
chmod 600 "$backup_dir/host-secrets.tar.gz"
cd "$backup_dir"
sha256sum host-secrets.tar.gz >host-secrets.sha256
chown rossgrat:rossgrat host-secrets.sha256
printf 'Protected host state saved in %s\n' "$backup_dir/host-secrets.tar.gz"
