#!/usr/bin/env bash
set -euo pipefail
umask 077
script_dir=$(cd -- "$(dirname -- "$0")" && pwd)
evidence=${1:?Pass an existing private evidence directory}
export K3S_CONFIG_FILE=/dev/null
K=(/usr/local/bin/k3s kubectl --kubeconfig /home/rossgrat/.kube/potatoserver-k3s.yaml)
"${K[@]}" get pods -n job-board -o json > "$evidence/pods.json"
collector=$("${K[@]}" get service/lgtm -n lgtm -o jsonpath='{.spec.clusterIP}')
/usr/local/libexec/potatoserver-runtime/node-24.22.2 "$script_dir/test-job-board-telemetry.mjs" "$evidence" "$collector"
