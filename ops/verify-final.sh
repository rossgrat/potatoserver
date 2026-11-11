#!/usr/bin/env bash
set -euo pipefail
umask 077
script_dir=$(cd -- "$(dirname -- "$0")" && pwd)
evidence=${1:?Pass an existing evidence directory on potatoserver}
case ${2:-} in ''|--after-reboot) ;; *) exit 2 ;; esac
export K3S_CONFIG_FILE=/dev/null
kubectl=(/usr/local/bin/k3s kubectl --kubeconfig /home/rossgrat/.kube/potatoserver-k3s.yaml)
bash /home/rossgrat/repos/network/ops/apply-k3s.sh --diff
"${kubectl[@]}" wait --for=condition=Ready node/potatoserver --timeout=30s
"${kubectl[@]}" get deployments,statefulsets,pods,persistentvolumeclaims -A -o json > "$evidence/cluster-health.json"
"${kubectl[@]}" get persistentvolumes -o json > "$evidence/volumes.json"
node - "$evidence" "${2:-}" <<'JS'
const fs = require('fs');
const path = process.argv[2];
const afterReboot = process.argv[3] === '--after-reboot';
const items = JSON.parse(fs.readFileSync(path + '/cluster-health.json')).items;
const namespaces = ['miniflux', 'umami', 'pages-cms', 'wubzduh', 'job-board', 'ntfy'];
for (const namespace of namespaces) {
  const deployments = namespace === 'job-board' ? ['job-board', 'worker'] : [namespace];
  for (const name of deployments) {
    const item = items.find(item => item.kind === 'Deployment' && item.metadata.namespace === namespace && item.metadata.name === name);
    if (item?.spec.replicas !== 1 || item.status.availableReplicas !== 1 || item.status.updatedReplicas !== 1) throw Error(`${namespace}/${name} is not ready`);
  }
  if (namespace !== 'ntfy') {
    const database = items.find(item => item.kind === 'StatefulSet' && item.metadata.namespace === namespace && item.metadata.name === 'postgres');
    if (database?.spec.replicas !== 1 || database.status.readyReplicas !== 1) throw Error(`${namespace} database is not ready`);
  }
}
for (const item of items.filter(item => namespaces.includes(item.metadata.namespace))) {
  if (item.kind === 'Pod' && item.metadata.labels?.app) {
    if (item.status.phase !== 'Running' || item.status.containerStatuses.some(container => !container.ready || (!afterReboot && container.restartCount !== 0))) throw Error(`${item.metadata.namespace}/${item.metadata.name} is unhealthy`);
  }
  if (item.kind === 'PersistentVolumeClaim' && item.status.phase !== 'Bound') throw Error('Application storage is not bound');
}
for (const volume of JSON.parse(fs.readFileSync(path + '/volumes.json')).items) {
  if (namespaces.includes(volume.spec.claimRef?.namespace) && volume.spec.persistentVolumeReclaimPolicy !== 'Retain') throw Error('Application volume is not retained');
}
console.log('Seven deployments, five databases, pod health, and retained storage PASS');
JS
sources=(miniflux-miniflux-1 miniflux-postgres-1 umami umami-postgres-1 pages-cms-app-1 pages-cms-postgres-1 wubzduh wubzduh-postgres-1 job-board-api job-board-worker job-board-postgres ntfy)
docker inspect --format '{{.Name}} {{.State.Running}} {{.HostConfig.RestartPolicy.Name}}' "${sources[@]}" > "$evidence/docker-sources.txt"
[[ $(grep -c ' false no$' "$evidence/docker-sources.txt") == ${#sources[@]} ]]
for url in https://rss.grattafiori.dev/healthcheck https://stats.grattafiori.dev/api/heartbeat https://cms.grattafiori.dev/sign-in https://wubzduh.grattafiori.dev/feed/ https://jobs.grattafiori.dev/login https://alerts.grattafiori.dev/v1/health https://grafana.grattafiori.dev/api/health; do
  status=$(curl --fail --silent --show-error --max-time 15 -o /dev/null -w '%{http_code}' "$url")
  [[ "$status" == 200 ]]
  printf '%s HTTP %s\n' "$url" "$status"
done
docker exec lgtm /otel-lgtm/docker/healthcheck.sh > "$evidence/lgtm-health.txt"
systemctl is-active k3s docker tailscaled cloudflared
systemctl is-active potatoserver-k3s-backup.timer
XDG_RUNTIME_DIR="/run/user/$(id -u)" systemctl --user is-active potatoserver-backup.timer
docker run --rm --read-only --network caddy-network -i --entrypoint node "$(cat "$script_dir/../k3s/backup-image")" --input-type=module <<'JS'
import net from 'node:net';
const reachable = port => new Promise(resolve => {
  const socket = net.connect({ host: '172.18.0.1', port });
  const finish = result => { socket.destroy(); resolve(result); };
  socket.setTimeout(1500, () => finish(false));
  socket.once('error', () => finish(false));
  socket.once('connect', () => finish(true));
});
if (!await reachable(80) || await reachable(6443) || await reachable(10250)) throw new Error('Docker access restrictions failed');
console.log('Docker web access and blocked cluster administration PASS');
JS
printf 'Final application and infrastructure health PASS\n' | tee "$evidence/result.txt"
