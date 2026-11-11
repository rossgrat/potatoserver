#!/usr/bin/env bash
set -euo pipefail
script_dir=$(cd -- "$(dirname -- "$0")" && pwd)
export K3S_CONFIG_FILE=/dev/null
kubectl=(/usr/local/bin/k3s kubectl --kubeconfig /home/rossgrat/.kube/potatoserver-k3s.yaml)
while IFS='=' read -r key runtime; do
  [[ "$runtime" == k3s ]] || continue
  namespace=$(printf '%s' "${key%_RUNTIME}" | tr 'A-Z_' 'a-z-')
  "${kubectl[@]}" scale deployments --all -n "$namespace" --replicas=0
  "${kubectl[@]}" wait --for=delete pod -n "$namespace" -l 'app!=postgres' --timeout=60s
  if [[ -n $("${kubectl[@]}" get statefulsets -n "$namespace" -o name) ]]; then
    "${kubectl[@]}" scale statefulsets --all -n "$namespace" --replicas=0
    "${kubectl[@]}" wait --for=delete pod -n "$namespace" -l app=postgres --timeout=60s
  fi
done < "$script_dir/../deployments.conf"
