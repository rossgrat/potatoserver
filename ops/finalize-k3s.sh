#!/usr/bin/env bash
set -euo pipefail
umask 077
((EUID == 0))
[[ $(hostname) == potatoserver ]]
script_dir=$(cd -- "$(dirname -- "$0")" && pwd)
tools_dir=$(dirname "$script_dir")
exec 9> "$tools_dir/state/operations.lock"
flock -n 9
backup=$(cat "$tools_dir/state/final-backup")
test -s "$backup/final-verification/result.txt"
(cd "$backup" && sha256sum --check --quiet SHA256SUMS)
evidence=/home/rossgrat/backups/k3s-final-$(date -u +%Y%m%dT%H%M%SZ)
install -d -m 700 -o rossgrat -g rossgrat "$evidence"
runuser -u rossgrat -- bash "$script_dir/verify-final.sh" "$evidence"
bash "$script_dir/backup-host-secrets.sh" "$evidence"
git -C /home/rossgrat/repos/network bundle create "$evidence/infrastructure.bundle" --all
tar -czf "$evidence/migration-tools.tar.gz" -C "$tools_dir" ops k3s systemd state
chown rossgrat:rossgrat "$evidence/infrastructure.bundle" "$evidence/migration-tools.tar.gz"
systemctl is-enabled k3s docker tailscaled cloudflared
systemctl is-active k3s docker tailscaled cloudflared
systemctl start potatoserver-k3s-backup.service
cluster_backup=$(find /home/rossgrat/backups -maxdepth 1 -name 'k3s-state-*' -type d | sort | tail -1)
runuser -u rossgrat -- bash "$script_dir/test-cluster-restore.sh" "$cluster_backup"
systemctl is-enabled potatoserver-k3s-backup.timer
runuser -u rossgrat -- env XDG_RUNTIME_DIR="/run/user/$(id -u rossgrat)" systemctl --user is-enabled potatoserver-backup.timer
printf 'Protected host backup, current cluster recovery, and startup services PASS\n'
printf 'Reboot recovery and overnight backup observations remain pending.\n'
