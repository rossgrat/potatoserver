#!/usr/bin/env bash
set -euo pipefail
umask 077

script_dir=$(cd -- "$(dirname -- "$0")" && pwd)
evidence=${1:?Pass a completed cluster backup directory}
(cd "$evidence" && sha256sum --check --quiet cluster-backup.sha256)
target="$evidence/recovery-test-$(date -u +%Y%m%dT%H%M%SZ)"
mkdir "$target"

export K3S_CONFIG_FILE=/dev/null
kubectl=(/usr/local/bin/k3s kubectl --kubeconfig /home/rossgrat/.kube/potatoserver-k3s.yaml)

namespace=potato-cluster-recovery-$(date +%s)

cleanup() {
  "${kubectl[@]}" logs -n "$namespace" recovery >"$target/startup.log" 2>&1 || true
  "${kubectl[@]}" delete namespace "$namespace" --ignore-not-found --wait=true --timeout=90s >/dev/null
}
trap cleanup EXIT

/usr/local/libexec/potatoserver-runtime/node-24.22.2 "$script_dir/cluster.mjs" "$namespace" >"$target/resources.json"
"${kubectl[@]}" apply -f "$target/resources.json" >"$target/apply.txt"
"${kubectl[@]}" wait --for=jsonpath='{.status.phase}'=Running pod/recovery -n "$namespace" --timeout=120s
"${kubectl[@]}" exec -i -n "$namespace" recovery -- tar -xzf - -C / <"$evidence/cluster-backup.tar.gz"
"${kubectl[@]}" exec -n "$namespace" recovery -- touch /tmp/start
ready=false
for _ in {1..90}; do
  if "${kubectl[@]}" exec -n "$namespace" recovery -- /bin/kubectl --kubeconfig /tmp/recovery.yaml --request-timeout=5s get --raw /readyz >"$target/ready.txt" 2>"$target/readiness-error.txt"; then
    ready=true
    break
  fi
  [[ $("${kubectl[@]}" get pod/recovery -n "$namespace" -o jsonpath='{.status.phase}') == Running ]] || break
  sleep 1
done
"$ready"
"${kubectl[@]}" version -o json >"$target/source-version.json"
"${kubectl[@]}" exec -n "$namespace" recovery -- /bin/kubectl --kubeconfig /tmp/recovery.yaml version -o json >"$target/restored-version.json"
"${kubectl[@]}" get secret potatoserver.node-password.k3s -n kube-system -o json >"$target/source-secret.json"
"${kubectl[@]}" exec -n "$namespace" recovery -- /bin/kubectl --kubeconfig /tmp/recovery.yaml get secret potatoserver.node-password.k3s -n kube-system -o json >"$target/restored-secret.json"
for service in miniflux umami pages-cms wubzduh job-board ntfy caddy lgtm; do
  "${kubectl[@]}" get secrets -n "$service" -o json >"$target/source-$service-secrets.json"
  "${kubectl[@]}" exec -n "$namespace" recovery -- /bin/kubectl --kubeconfig /tmp/recovery.yaml get secrets -n "$service" -o json >"$target/restored-$service-secrets.json"
done
/usr/local/libexec/potatoserver-runtime/node-24.22.2 - "$target" <<'JS'
const fs = require('fs');
const resultsDirectory = process.argv[2];
const readEvidence = (file) => JSON.parse(fs.readFileSync(resultsDirectory + '/' + file));
if (
  readEvidence('source-version.json').serverVersion.gitVersion !==
  readEvidence('restored-version.json').serverVersion.gitVersion
) {
  throw Error('Recovery image version differs from the live cluster');
}
const source = readEvidence('source-secret.json');
const restored = readEvidence('restored-secret.json');
const secretEntries = (item) => Object.entries(item.data ?? {}).sort();
if (
  !Object.keys(source.data).length ||
  source.metadata.uid !== restored.metadata.uid ||
  JSON.stringify(secretEntries(source)) !== JSON.stringify(secretEntries(restored))
) {
  throw Error('Restored node credentials differ');
}
let secretCount = 0;
for (const file of fs
  .readdirSync(resultsDirectory)
  .filter((file) => /^source-.+-secrets[.]json$/.test(file))) {
  const secretIdentities = (file) =>
    readEvidence(file)
      .items.map((item) => ({
        name: item.metadata.name,
        uid: item.metadata.uid,
        data: secretEntries(item),
      }))
      .sort((left, right) => left.name.localeCompare(right.name));
  const expected = secretIdentities(file);
  if (
    JSON.stringify(expected) !==
    JSON.stringify(secretIdentities(file.replace('source-', 'restored-')))
  ) {
    throw Error('Restored application credentials differ');
  }
  secretCount += expected.length;
}
console.log(
  'K3s-native isolated API recovery and ' + secretCount + ' restored application secrets PASS',
);
JS
printf 'K3s-native cluster API and encrypted secret restoration PASS\n' >"$target/result.txt"
