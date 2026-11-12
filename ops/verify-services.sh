#!/usr/bin/env bash
set -euo pipefail
umask 077
script_dir=$(cd -- "$(dirname -- "$0")" && pwd)
evidence=${1:?Pass an existing evidence directory on potatoserver}
export K3S_CONFIG_FILE=/dev/null
kubectl=(/usr/local/bin/k3s kubectl --kubeconfig /home/rossgrat/.kube/potatoserver-k3s.yaml)
bash /home/rossgrat/repos/network/ops/apply-k3s.sh --diff
"${kubectl[@]}" wait --for=condition=Ready node/potatoserver --timeout=30s
"${kubectl[@]}" get deployments,statefulsets,pods,persistentvolumeclaims -A -o json > "$evidence/cluster-health.json"
"${kubectl[@]}" get persistentvolumes -o json > "$evidence/volumes.json"
/usr/local/libexec/potatoserver-runtime/node-24.22.2 - "$evidence" <<'JS'
const fs = require('fs');
const path = process.argv[2];
const items = JSON.parse(fs.readFileSync(path + '/cluster-health.json')).items;
const namespaces = ['miniflux', 'umami', 'pages-cms', 'wubzduh', 'job-board', 'ntfy', 'caddy', 'lgtm'];
for (const namespace of namespaces) {
  const deployments = namespace === 'job-board' ? ['job-board', 'worker'] : [namespace];
  for (const name of deployments) {
    const item = items.find(item => item.kind === 'Deployment' && item.metadata.namespace === namespace && item.metadata.name === name);
    if (item?.spec.replicas !== 1 || item.status.availableReplicas !== 1 || item.status.updatedReplicas !== 1) throw Error(`${namespace}/${name} is not ready`);
  }
  if (!['ntfy', 'caddy', 'lgtm'].includes(namespace)) {
    const database = items.find(item => item.kind === 'StatefulSet' && item.metadata.namespace === namespace && item.metadata.name === 'postgres');
    if (database?.spec.replicas !== 1 || database.status.readyReplicas !== 1) throw Error(`${namespace} database is not ready`);
  }
}
for (const item of items.filter(item => namespaces.includes(item.metadata.namespace))) {
  if (item.kind === 'Pod' && item.metadata.labels?.app) {
    if (item.status.phase !== 'Running' || item.status.containerStatuses.some(container => !container.ready)) throw Error(`${item.metadata.namespace}/${item.metadata.name} is unhealthy`);
  }
  if (item.kind === 'PersistentVolumeClaim' && item.status.phase !== 'Bound') throw Error('Application storage is not bound');
}
for (const volume of JSON.parse(fs.readFileSync(path + '/volumes.json')).items) {
  if (namespaces.includes(volume.spec.claimRef?.namespace) && volume.spec.persistentVolumeReclaimPolicy !== 'Retain') throw Error('Application volume is not retained');
}
console.log('Nine deployments, five databases, pod health, and retained storage PASS');
JS
for url in https://rss.grattafiori.dev/healthcheck https://stats.grattafiori.dev/api/heartbeat https://cms.grattafiori.dev/sign-in https://wubzduh.grattafiori.dev/feed/ https://jobs.grattafiori.dev/login https://alerts.grattafiori.dev/v1/health https://grafana.grattafiori.dev/api/health; do
  status=$(curl --fail --silent --show-error --max-time 15 -o /dev/null -w '%{http_code}' "$url")
  [[ "$status" == 200 ]]
  printf '%s HTTP %s\n' "$url" "$status"
done
"${kubectl[@]}" exec -n lgtm deployment/lgtm -- /otel-lgtm/docker/healthcheck.sh > "$evidence/lgtm-health.txt"
systemctl is-active k3s tailscaled cloudflared
if systemctl is-active --quiet docker.service || systemctl is-active --quiet docker.socket; then exit 1; fi
systemctl is-active potatoserver-k3s-backup.timer
XDG_RUNTIME_DIR="/run/user/$(id -u)" systemctl --user is-active potatoserver-backup.timer
printf 'Application and infrastructure health PASS\n' | tee "$evidence/result.txt"
