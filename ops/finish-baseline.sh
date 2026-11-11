#!/usr/bin/env bash
set -euo pipefail
[[ $EUID == 0 ]]
script_dir=$(cd -- "$(dirname -- "$0")" && pwd)
backup_dir=${1:?Pass the existing baseline backup directory}
test -s "$backup_dir/restore-results/volumes-summary.txt"
for target in miniflux-postgres-1 job-board-postgres wubzduh-postgres-1 umami-postgres-1 pages-cms-postgres-1; do
  grep -q "$target PASS " "$backup_dir/restore-results/summary.txt"
  grep -q 'password authentication failed' "$backup_dir/restore-results/$target-invalid-password.txt"
done
bash "$script_dir/backup-host-secrets.sh" "${1:?Pass the existing baseline backup directory}"
loginctl enable-linger rossgrat
runuser -u rossgrat -- env XDG_RUNTIME_DIR=/run/user/1000 systemctl --user daemon-reload
runuser -u rossgrat -- env XDG_RUNTIME_DIR=/run/user/1000 systemctl --user enable --now potatoserver-backup.timer
runuser -u rossgrat -- env XDG_RUNTIME_DIR=/run/user/1000 systemctl --user list-timers potatoserver-backup.timer --no-pager
