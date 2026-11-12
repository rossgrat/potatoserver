#!/usr/bin/env bash
set -euo pipefail
exec 9> /home/rossgrat/.local/state/potatoserver/operations.lock
flock -n 9
export K3S_CONFIG_FILE=/dev/null
kubectl=(/usr/local/bin/k3s kubectl --kubeconfig /home/rossgrat/.kube/potatoserver-k3s.yaml)
for namespace in miniflux umami pages-cms wubzduh job-board ntfy lgtm caddy; do
  "${kubectl[@]}" scale deployments --all -n "$namespace" --replicas=0
  "${kubectl[@]}" wait --for=delete pod -n "$namespace" -l 'app!=postgres' --timeout=60s
  if [[ -n $("${kubectl[@]}" get statefulsets -n "$namespace" -o name) ]]; then
    "${kubectl[@]}" scale statefulsets --all -n "$namespace" --replicas=0
    "${kubectl[@]}" wait --for=delete pod -n "$namespace" -l app=postgres --timeout=60s
  fi
done
