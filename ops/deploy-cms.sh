#!/usr/bin/env bash
set -euo pipefail
umask 077
script_dir=$(cd -- "$(dirname -- "$0")" && pwd)
repo_dir=$(dirname "$script_dir")
exec 9> /home/rossgrat/.local/state/potatoserver/operations.lock
flock -n 9
export K3S_CONFIG_FILE=/dev/null
kubectl=(/usr/local/bin/k3s kubectl --kubeconfig /home/rossgrat/.kube/potatoserver-k3s.yaml)
evidence=/home/rossgrat/backups/k3s-cms-release-$(date -u +%Y%m%dT%H%M%SZ)
mkdir "$evidence"
"${kubectl[@]}" create --dry-run=client -f "$repo_dir/k3s/pages-cms.yaml" \
  -o jsonpath='{.kind}{"\t"}{.spec.template.spec}{"\n"}' > "$evidence/declared-pods.txt"
/usr/local/libexec/potatoserver-runtime/node-24.22.2 - "$evidence" <<'JS'
const fs = require('fs'), path = process.argv[2];
const row = fs.readFileSync(`${path}/declared-pods.txt`, 'utf8').split('\n').find(row => row.startsWith('Deployment\t'));
const spec = JSON.parse(row.slice(row.indexOf('\t') + 1));
const container = spec.containers[0];
const imported = fs.readFileSync('/home/rossgrat/.local/state/potatoserver/pages-cms-imported-image-ref', 'utf8').trim();
if (container.image !== imported) throw Error('Import the declared CMS image before deploying');
delete container.readinessProbe;
delete container.livenessProbe;
delete container.startupProbe;
delete container.ports;
container.command = ['npm', 'run', 'db:migrate'];
delete container.args;
spec.restartPolicy = 'Never';
fs.writeFileSync(`${path}/migration-job.json`, JSON.stringify({
  apiVersion: 'batch/v1', kind: 'Job', metadata: { generateName: 'pages-cms-migrate-', namespace: 'pages-cms' },
  spec: { backoffLimit: 0, activeDeadlineSeconds: 180, template: { metadata: { labels: { app: 'pages-cms', role: 'migration' } }, spec } },
}), { mode: 0o600 });
JS
job=$("${kubectl[@]}" create -f "$evidence/migration-job.json" -o jsonpath='{.metadata.name}')
cleanup() {
  "${kubectl[@]}" logs -n pages-cms job/"$job" > "$evidence/migrations.log" 2>&1 || true
  "${kubectl[@]}" delete job/"$job" -n pages-cms --wait=true >/dev/null
}
trap cleanup EXIT
"${kubectl[@]}" wait --for=condition=Complete job/"$job" -n pages-cms --timeout=200s
"${kubectl[@]}" apply -f "$repo_dir/k3s/pages-cms.yaml" -f "$repo_dir/k3s/pages-cms-egress.yaml"
"${kubectl[@]}" rollout status deployment/pages-cms -n pages-cms --timeout=240s
printf 'CMS database migrations and declared deployment PASS\n'
