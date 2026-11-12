#!/usr/bin/env bash
set -euo pipefail
umask 077
script_dir=$(cd -- "$(dirname -- "$0")" && pwd)
evidence=${1:?Pass a completed cluster backup directory}
(cd "$evidence" && sha256sum --check --quiet cluster-backup.sha256)
target="$evidence/recovery-test-$(date -u +%Y%m%dT%H%M%SZ)"
mkdir "$target"
export K3S_CONFIG_FILE=/dev/null
K=(/usr/local/bin/k3s kubectl --kubeconfig /home/rossgrat/.kube/potatoserver-k3s.yaml)
namespace=potato-cluster-recovery-$(date +%s)
cleanup() {
  "${K[@]}" logs -n "$namespace" recovery > "$target/startup.log" 2>&1 || true
  "${K[@]}" delete namespace "$namespace" --ignore-not-found --wait=true --timeout=90s >/dev/null
}
trap cleanup EXIT
/usr/local/libexec/potatoserver-runtime/node-24.22.2 "$script_dir/cluster.mjs" "$namespace" > "$target/resources.json"
"${K[@]}" apply -f "$target/resources.json" > "$target/apply.txt"
"${K[@]}" wait --for=jsonpath='{.status.phase}'=Running pod/recovery -n "$namespace" --timeout=120s
"${K[@]}" exec -i -n "$namespace" recovery -- tar -xzf - -C / < "$evidence/cluster-backup.tar.gz"
"${K[@]}" exec -n "$namespace" recovery -- touch /tmp/start
ready=false
for _ in {1..90}; do
  if "${K[@]}" exec -n "$namespace" recovery -- /bin/kubectl --kubeconfig /tmp/recovery.yaml --request-timeout=5s get --raw /readyz > "$target/ready.txt" 2> "$target/readiness-error.txt"; then ready=true; break; fi
  [[ $("${K[@]}" get pod/recovery -n "$namespace" -o jsonpath='{.status.phase}') == Running ]] || break
  sleep 1
done
"$ready"
"${K[@]}" version -o json > "$target/source-version.json"
"${K[@]}" exec -n "$namespace" recovery -- /bin/kubectl --kubeconfig /tmp/recovery.yaml version -o json > "$target/restored-version.json"
"${K[@]}" get secret potatoserver.node-password.k3s -n kube-system -o json > "$target/source-secret.json"
"${K[@]}" exec -n "$namespace" recovery -- /bin/kubectl --kubeconfig /tmp/recovery.yaml get secret potatoserver.node-password.k3s -n kube-system -o json > "$target/restored-secret.json"
for service in miniflux umami pages-cms wubzduh job-board ntfy caddy lgtm; do
  "${K[@]}" get secrets -n "$service" -o json > "$target/source-$service-secrets.json"
  "${K[@]}" exec -n "$namespace" recovery -- /bin/kubectl --kubeconfig /tmp/recovery.yaml get secrets -n "$service" -o json > "$target/restored-$service-secrets.json"
done
/usr/local/libexec/potatoserver-runtime/node-24.22.2 - "$target" <<'JS'
const fs = require('fs');
const target = process.argv[2];
const read = file => JSON.parse(fs.readFileSync(target + '/' + file));
if (read('source-version.json').serverVersion.gitVersion !== read('restored-version.json').serverVersion.gitVersion) throw Error('Recovery image version differs from the live cluster');
const source = read('source-secret.json');
const restored = read('restored-secret.json');
const data = item => Object.entries(item.data ?? {}).sort();
if (!Object.keys(source.data).length || source.metadata.uid !== restored.metadata.uid || JSON.stringify(data(source)) !== JSON.stringify(data(restored))) throw Error('Restored node credentials differ');
let count = 0;
for (const file of fs.readdirSync(target).filter(file => /^source-.+-secrets[.]json$/.test(file))) {
  const identity = file => read(file).items.map(item => ({ name: item.metadata.name, uid: item.metadata.uid, data: data(item) })).sort((left, right) => left.name.localeCompare(right.name));
  const expected = identity(file);
  if (JSON.stringify(expected) !== JSON.stringify(identity(file.replace('source-', 'restored-')))) throw Error('Restored application credentials differ');
  count += expected.length;
}
console.log('K3s-native isolated API recovery and ' + count + ' restored application secrets PASS');
JS
printf 'K3s-native cluster API and encrypted secret restoration PASS\n' > "$target/result.txt"
