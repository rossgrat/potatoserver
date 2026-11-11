#!/usr/bin/env bash
set -euo pipefail
umask 077
script_dir=$(cd -- "$(dirname -- "$0")" && pwd)
backup_dir=${1:?Pass an absolute backup directory outside the repository}
case "$backup_dir" in /*) ;; *) exit 2 ;; esac
tools=/home/rossgrat/k3s-migration-tools
bash "$tools/ops/backup-database.sh" pages-cms-postgres-1 "$backup_dir"
if [[ $(cat "$backup_dir/authority.txt") == k3s ]]; then
  K3S_CONFIG_FILE=/dev/null /usr/local/bin/k3s kubectl --kubeconfig /home/rossgrat/.kube/potatoserver-k3s.yaml \
    get deployments,statefulsets,services,persistentvolumeclaims,networkpolicies,secrets -n pages-cms -o yaml > "$backup_dir/resources.yaml"
else
  cp "$script_dir/.env" "$backup_dir/app.env"
fi
printf 'Backup saved to %s\n' "$backup_dir"
