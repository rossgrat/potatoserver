#!/usr/bin/env bash
set -euo pipefail
script_dir=$(cd -- "$(dirname -- "$0")" && pwd)
repo_dir=$(dirname "$script_dir")
operation=apply
case ${1:-} in --diff) operation='diff' ;; '') ;; *) exit 2 ;; esac
if [[ "$operation" == apply ]]; then
  exec 9> /home/rossgrat/.local/state/potatoserver/operations.lock
  flock -n 9
fi
K3S_CONFIG_FILE=/dev/null /usr/local/bin/k3s kubectl --kubeconfig /home/rossgrat/.kube/potatoserver-k3s.yaml "$operation" -k "$repo_dir"
