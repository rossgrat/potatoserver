#!/usr/bin/env bash
set -euo pipefail
umask 077
script_dir=$(cd -- "$(dirname -- "$0")" && pwd)
backup_dir=${1:?Pass an absolute backup directory outside the repository}
case "$backup_dir" in /*) ;; *) exit 2 ;; esac
tools=$(dirname "$script_dir")
bash "$tools/ops/backup-database.sh" pages-cms-postgres-1 "$backup_dir"
K3S_CONFIG_FILE=/dev/null /usr/local/bin/k3s kubectl --kubeconfig /home/rossgrat/.kube/potatoserver-k3s.yaml \
  get deployments,statefulsets,services,persistentvolumeclaims,networkpolicies,secrets -n pages-cms -o json > "$backup_dir/resources.json"
printf 'Backup saved to %s\n' "$backup_dir"
