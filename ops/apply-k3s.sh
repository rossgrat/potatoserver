#!/usr/bin/env bash
set -euo pipefail
script_dir=$(cd -- "$(dirname -- "$0")" && pwd)
repo_dir=$(dirname "$script_dir")
operation=apply
case ${1:-} in --diff) operation='diff' ;; '') ;; *) exit 2 ;; esac
manifests=(-f "$repo_dir/k3s/local-retain.yaml")
while IFS='=' read -r key runtime; do
  case "$runtime" in docker) continue ;; k3s) ;; *) exit 1 ;; esac
  service=$(printf '%s' "${key%_RUNTIME}" | tr 'A-Z_' 'a-z-')
  manifests+=(-f "$repo_dir/k3s/$service.yaml")
  if [[ -f "$repo_dir/k3s/$service-egress.yaml" ]]; then manifests+=(-f "$repo_dir/k3s/$service-egress.yaml"); fi
done < "$repo_dir/deployments.conf"
K3S_CONFIG_FILE=/dev/null /usr/local/bin/k3s kubectl --kubeconfig /home/rossgrat/.kube/potatoserver-k3s.yaml "$operation" "${manifests[@]}"
