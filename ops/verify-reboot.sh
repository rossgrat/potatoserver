#!/usr/bin/env bash
set -euo pipefail
umask 077
script_dir=$(cd -- "$(dirname -- "$0")" && pwd)
state_dir=/home/rossgrat/.local/state/potatoserver
export K3S_CONFIG_FILE=/dev/null
kubectl=(/usr/local/bin/k3s kubectl --kubeconfig /home/rossgrat/.kube/potatoserver-k3s.yaml)
case ${1:-} in
  --prepare)
    mkdir -p "$state_dir"
    checkpoint=/home/rossgrat/backups/k3s-reboot-$(date -u +%Y%m%dT%H%M%SZ)
    mkdir "$checkpoint"
    cat /proc/sys/kernel/random/boot_id > "$checkpoint/boot-id.before"
    uptime -s > "$checkpoint/boot-time.before"
    "${kubectl[@]}" get persistentvolumeclaims -A -o json > "$checkpoint/claims.before.json"
    printf '%s\n' "$checkpoint" > "$state_dir/reboot-check"
    printf 'Saved reboot checkpoint: %s\n' "$checkpoint"
    exit 0
    ;;
  '') ;;
  *) exit 2 ;;
esac
checkpoint=$(cat "$state_dir/reboot-check")
boot=$(cat /proc/sys/kernel/random/boot_id)
if [[ "$boot" == $(cat "$checkpoint/boot-id.before") ]]; then
  printf 'The boot ID is unchanged. Reboot recovery is not verified.\n' >&2
  exit 1
fi
evidence="$checkpoint/after-$(date -u +%Y%m%dT%H%M%SZ)"
mkdir "$evidence"
printf '%s\n' "$boot" > "$evidence/boot-id.after"
uptime -s > "$evidence/boot-time.txt"
ready=false
for _ in {1..60}; do
  if "${kubectl[@]}" get --raw /readyz --request-timeout=5s > "$evidence/api-ready.txt" 2>&1; then ready=true; break; fi
  sleep 3
done
"$ready"
"${kubectl[@]}" wait --for=condition=Ready node/potatoserver --timeout=180s
for namespace in miniflux umami pages-cms wubzduh job-board ntfy caddy lgtm; do
  if [[ "$namespace" != ntfy && "$namespace" != caddy && "$namespace" != lgtm ]]; then "${kubectl[@]}" rollout status statefulset/postgres -n "$namespace" --timeout=180s; fi
  "${kubectl[@]}" rollout status deployment/"$namespace" -n "$namespace" --timeout=180s
done
"${kubectl[@]}" rollout status deployment/worker -n job-board --timeout=180s
bash "$script_dir/verify-services.sh" "$evidence"
"${kubectl[@]}" get pods -A -o json > "$evidence/pods.before.json"
printf 'Observing container stability for 30 seconds\n'
sleep 30
"${kubectl[@]}" get pods -A -o json > "$evidence/pods.after.json"
/usr/local/libexec/potatoserver-runtime/node-24.22.2 - "$checkpoint" "$evidence" <<'JS'
const fs = require('fs');
const [checkpoint, evidence] = process.argv.slice(2);
const namespaces = ['miniflux', 'umami', 'pages-cms', 'wubzduh', 'job-board', 'ntfy', 'caddy', 'lgtm'];
const read = file => JSON.parse(fs.readFileSync(file)).items;
const claims = items => items.filter(item => item.kind === 'PersistentVolumeClaim' && namespaces.includes(item.metadata.namespace))
  .map(item => [item.metadata.namespace, item.metadata.name, item.metadata.uid, item.spec.volumeName]).sort();
if (JSON.stringify(claims(read(`${checkpoint}/claims.before.json`))) !== JSON.stringify(claims(read(`${evidence}/cluster-health.json`)))) throw Error('Persistent storage changed across the reboot');
const containers = file => read(file).filter(pod => namespaces.includes(pod.metadata.namespace) && pod.metadata.labels?.app).flatMap(pod => {
  if (pod.status.phase !== 'Running') throw Error('An application pod is not running');
  return pod.status.containerStatuses.map(container => {
    if (!container.ready || !container.state.running) throw Error('An application container is not ready');
    return [pod.metadata.uid, container.name, container.restartCount, container.state.running.startedAt];
  });
}).sort();
if (JSON.stringify(containers(`${evidence}/pods.before.json`)) !== JSON.stringify(containers(`${evidence}/pods.after.json`))) throw Error('Application containers restarted during the observation');
console.log('New boot identity, unchanged persistent storage, and stable application containers PASS');
JS
systemctl list-timers potatoserver-k3s-backup.timer --no-pager > "$evidence/root-timer.txt"
XDG_RUNTIME_DIR="/run/user/$(id -u)" systemctl --user list-timers potatoserver-backup.timer --no-pager > "$evidence/user-timer.txt"
printf 'Reboot health and storage recovery PASS\n' | tee "$evidence/reboot-result.txt"
