#!/usr/bin/env bash
set -euo pipefail
umask 077
script_dir=$(cd -- "$(dirname -- "$0")" && pwd)
backup_dir=${1:?Pass an absolute backup directory outside the repository}
case "$backup_dir" in /*) ;; *) exit 2 ;; esac
tools=$(dirname "$script_dir")
bash "$tools/ops/backup-database.sh" umami-postgres-1 "$backup_dir"
K3S_CONFIG_FILE=/dev/null /usr/local/bin/k3s kubectl --kubeconfig /home/rossgrat/.kube/potatoserver-k3s.yaml \
  get deployments,statefulsets,services,persistentvolumeclaims,networkpolicies,secrets -n umami -o json > "$backup_dir/resources.json"
cp /home/rossgrat/.config/umami/admin.json "$backup_dir/http-auth.json"
printf 'Backup saved to %s\n' "$backup_dir"
