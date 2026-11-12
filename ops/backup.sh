#!/usr/bin/env bash
set -euo pipefail
umask 077

script_dir=$(cd -- "$(dirname -- "$0")" && pwd)
state_dir=/home/rossgrat/.local/state/potatoserver
exec 9>"$state_dir/operations.lock"
flock -n 9
backup_dir=${1:?Pass a new absolute backup directory on potatoserver}
case "$backup_dir" in
  /home/rossgrat/backups/*) ;;
  *) exit 2 ;;
esac
mkdir "$backup_dir"

export K3S_CONFIG_FILE=/dev/null
kubectl=(/usr/local/bin/k3s kubectl --kubeconfig /home/rossgrat/.kube/potatoserver-k3s.yaml)

lgtm_paused=false
backup_namespace=

cleanup() {
  if [[ -n "$backup_namespace" ]]; then
    "${kubectl[@]}" delete pod/state-backup -n "$backup_namespace" --ignore-not-found --wait=true >/dev/null || true
  fi
  if "$lgtm_paused"; then
    "${kubectl[@]}" scale deployment/lgtm -n lgtm --replicas=1 >/dev/null
    "${kubectl[@]}" rollout status deployment/lgtm -n lgtm --timeout=240s
  fi
}
trap cleanup EXIT

date -u +%FT%TZ >"$backup_dir/started.txt"
"${kubectl[@]}" get pods -A -o wide >"$backup_dir/runtime.txt"
free -h >"$backup_dir/memory.txt"
df -h / >"$backup_dir/disk.txt"
cp "$script_dir/lib/database-fingerprint.sql" "$backup_dir/"
backup_pids=()
databases=(
  miniflux:miniflux-postgres-1
  job-board:job-board-postgres
  wubzduh:wubzduh-postgres-1
  umami:umami-postgres-1
  pages-cms:pages-cms-postgres-1
)
for entry in "${databases[@]}"; do
  IFS=: read -r namespace label <<<"$entry"
  bash "$script_dir/backup-database.sh" "$namespace" "$backup_dir/$label" &
  backup_pids+=("$!")
done
backup_status=0
for pid in "${backup_pids[@]}"; do
  wait "$pid" || backup_status=1
done
((backup_status == 0))
for namespace in miniflux umami pages-cms wubzduh job-board ntfy caddy lgtm; do
  "${kubectl[@]}" get deployments,statefulsets,services,persistentvolumeclaims,networkpolicies,configmaps,secrets -n "$namespace" -o json >"$backup_dir/$namespace-resources.json"
done
tar -czf "$backup_dir/configuration.tar.gz" -C /home/rossgrat \
  --exclude='.git' --exclude='caddy/logs' --exclude='caddy/media' \
  repos/network .config/umami/admin.json
tar -czf "$backup_dir/host-configuration.tar.gz" -C / \
  etc/cloudflared/config.yml etc/systemd/system/cloudflared.service \
  etc/systemd/system/systemd-networkd-wait-online.service.d
(
  cd "$backup_dir"
  sha256sum configuration.tar.gz ./*-resources.json ./*/database.dump ./*/schema.sql ./*/globals.sql \
    ./*/image.txt ./*/connection.txt ./*/source-fingerprint.txt >DATABASE_SHA256SUMS
)
bash "$script_dir/lib/backup-ntfy.sh" "$backup_dir"
"${kubectl[@]}" exec -n wubzduh deployment/wubzduh -- tar -C /var/log/wubzduh -cf - . >"$backup_dir/wubzduh-logs.tar"
gzip -1 "$backup_dir/wubzduh-logs.tar"
for backup_namespace in caddy lgtm; do
  /usr/local/libexec/potatoserver-runtime/node-24.22.2 "$script_dir/lib/backup-infrastructure.mjs" "$backup_namespace" | "${kubectl[@]}" apply -f - >/dev/null
  "${kubectl[@]}" wait --for=condition=Ready pod/state-backup -n "$backup_namespace" --timeout=120s
  if [[ "$backup_namespace" == caddy ]]; then
    "${kubectl[@]}" exec -n caddy state-backup -- sh -ec 'for name in data config media logs; do cp -R --preserve=mode,timestamps "/$name" "/tmp/$name"; done'
    "${kubectl[@]}" exec -i -n caddy state-backup -- node --input-type=module <<'JS'
import fs from 'node:fs';
import path from 'node:path';
import { X509Certificate, createPrivateKey } from 'node:crypto';
let certificateCount = 0;

function checkCertificates(directory) {
  for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
    const file = path.join(directory, entry.name);
    if (entry.isDirectory()) {
      checkCertificates(file);
    } else if (file.endsWith('.crt')) {
      const certificate = new X509Certificate(fs.readFileSync(file));
      const key = createPrivateKey(fs.readFileSync(file.slice(0, -4) + '.key'));
      if (!certificate.checkPrivateKey(key)) {
        throw Error('TLS certificate and key differ');
      }
      certificateCount++;
    }
  }
}
checkCertificates('/tmp/data');
if (!certificateCount) {
  throw Error('No saved TLS certificates');
}
console.log('Saved Caddy TLS certificates and private keys PASS');
JS
    for name in data config media logs; do
      archive="caddy-$name"
      if [[ "$name" == media ]]; then
        archive=media
      fi
      "${kubectl[@]}" exec -n caddy state-backup -- tar -C "/tmp/$name" -cf - . | gzip -1 >"$backup_dir/$archive.tar.gz"
    done
  else
    [[ $("${kubectl[@]}" get deployment/lgtm -n lgtm -o jsonpath='{.spec.replicas}') == 1 ]]
    lgtm_paused=true
    "${kubectl[@]}" scale deployment/lgtm -n lgtm --replicas=0 >/dev/null
    "${kubectl[@]}" wait --for=delete pod -n lgtm -l app=lgtm --timeout=90s >/dev/null
    timeout --kill-after=5 600 "${kubectl[@]}" exec -n lgtm state-backup -- tar -C /data -cf - . >"$backup_dir/lgtm-data.tar"
    "${kubectl[@]}" scale deployment/lgtm -n lgtm --replicas=1 >/dev/null
    "${kubectl[@]}" rollout status deployment/lgtm -n lgtm --timeout=240s
    lgtm_paused=false
    gzip -1 "$backup_dir/lgtm-data.tar"
  fi
  "${kubectl[@]}" delete pod/state-backup -n "$backup_namespace" --wait=true >/dev/null
done
backup_namespace=
test -s "$state_dir/custom-images.tar"
gzip -1 -c "$state_dir/custom-images.tar" >"$backup_dir/custom-images.tar.gz"
cd "$backup_dir"
find . -type f ! -name SHA256SUMS -print0 | sort -z | xargs -0 sha256sum >SHA256SUMS
printf 'K3s application and infrastructure backup saved to %s\n' "$backup_dir"
