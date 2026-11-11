#!/usr/bin/env bash
set -euo pipefail
umask 077
((EUID == 0))
script_dir=$(cd -- "$(dirname -- "$0")" && pwd)
tools_dir=$(dirname "$script_dir")
install -d -m 700 /usr/local/libexec/potatoserver-k3s
install -m 700 "$script_dir/backup-k3s-state.sh" /usr/local/libexec/potatoserver-k3s/backup.sh
install -m 600 "$script_dir/backup-k3s-state.mjs" /usr/local/libexec/potatoserver-k3s/backup.mjs
install -m 600 "$tools_dir/k3s/backup-image" /usr/local/libexec/potatoserver-k3s/backup-image
install -m 644 "$tools_dir/systemd/potatoserver-k3s-backup.service" /etc/systemd/system/
install -m 644 "$tools_dir/systemd/potatoserver-k3s-backup.timer" /etc/systemd/system/
systemd-analyze verify potatoserver-k3s-backup.service potatoserver-k3s-backup.timer
systemctl daemon-reload
systemctl start potatoserver-k3s-backup.service
target=$(find /home/rossgrat/backups -maxdepth 1 -name 'k3s-state-*' -type d | sort | tail -1)
test -s "$target/cluster-backup.sha256"
runuser -u rossgrat -- bash "$script_dir/test-cluster-restore.sh" "$target"
systemctl enable --now potatoserver-k3s-backup.timer
systemctl list-timers potatoserver-k3s-backup.timer --no-pager
