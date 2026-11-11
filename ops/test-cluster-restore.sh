#!/usr/bin/env bash
set -euo pipefail
umask 077
script_dir=$(cd -- "$(dirname -- "$0")" && pwd)
tools_dir=$(dirname "$script_dir")
evidence=${1:?Pass an installation evidence directory}
target="$evidence/recovery-test-$(date -u +%Y%m%dT%H%M%SZ)"
mkdir "$target"
mkdir "$target/root"
tar -xzf "$evidence/cluster-backup.tar.gz" -C "$target/root" --no-same-owner --same-permissions
K3S_CONFIG_FILE=/dev/null /usr/local/bin/k3s kubectl --kubeconfig /home/rossgrat/.kube/potatoserver-k3s.yaml \
  get secret potatoserver.node-password.k3s -n kube-system -o json > "$target/source-secret.json"
network=$(docker network create --internal --label potatoserver.task=k3s-state-restore "k3s-state-restore-$$")
container=
cleanup() {
  if [[ -n "$container" ]]; then
    docker logs "$container" > "$target/startup.log" 2>&1 || true
    docker rm -fv "$container" >/dev/null
  fi
  docker network rm "$network" >/dev/null
  if [[ -f "$target/result.txt" ]]; then
    docker run --rm --network none --read-only -v "$target/root:/scratch" \
      --entrypoint /bin/rm "$(cat "$tools_dir/k3s/recovery-image")" -rf /scratch/var /scratch/etc
    rmdir "$target/root"
  fi
}
trap cleanup EXIT
container=$(docker run -d --label potatoserver.task=k3s-state-restore --network "$network" --memory 2g --cpus 2 \
  -e K3S_CONFIG_FILE=/dev/null \
  -v "$target/root/var/lib/rancher/k3s:/var/lib/rancher/k3s" \
  --entrypoint /bin/sh "$(cat "$tools_dir/k3s/recovery-image")" \
  -c 'address=$(hostname -i); exec /bin/k3s server --node-ip="$address" --advertise-address="$address" "$@"' sh \
  --disable-agent --disable-scheduler \
  --disable-cloud-controller --disable-network-policy --secrets-encryption \
  --disable traefik,servicelb,coredns,local-storage,metrics-server,gateway-api-crd,runtimes \
  --write-kubeconfig /tmp/recovery.yaml --write-kubeconfig-mode 0600)
ready=false
for _ in {1..90}; do
  [[ $(docker inspect --format '{{.State.Running}}' "$container") == true ]] || break
  if docker exec "$container" /bin/kubectl --kubeconfig /tmp/recovery.yaml --request-timeout=5s get --raw /readyz > "$target/ready.txt" 2>/dev/null; then ready=true; break; fi
  sleep 1
done
"$ready"
docker exec "$container" /bin/kubectl --kubeconfig /tmp/recovery.yaml \
  get secret potatoserver.node-password.k3s -n kube-system -o json > "$target/restored-secret.json"
for namespace in miniflux umami pages-cms wubzduh job-board ntfy; do
  if K3S_CONFIG_FILE=/dev/null /usr/local/bin/k3s kubectl --kubeconfig /home/rossgrat/.kube/potatoserver-k3s.yaml \
      get namespace "$namespace" -o name >/dev/null 2>&1; then
    K3S_CONFIG_FILE=/dev/null /usr/local/bin/k3s kubectl --kubeconfig /home/rossgrat/.kube/potatoserver-k3s.yaml \
      get secrets -n "$namespace" -o json > "$target/source-$namespace-secrets.json"
    docker exec "$container" /bin/kubectl --kubeconfig /tmp/recovery.yaml \
      get secrets -n "$namespace" -o json > "$target/restored-$namespace-secrets.json"
  fi
done
docker run --rm --network none --read-only -i -v "$target:/evidence:ro" \
  --entrypoint node "$(docker inspect --format '{{.Image}}' pages-cms-app-1)" --input-type=module <<'JS'
import fs from 'node:fs';
const source=JSON.parse(fs.readFileSync('/evidence/source-secret.json'));
const restored=JSON.parse(fs.readFileSync('/evidence/restored-secret.json'));
if (!Object.keys(source.data).length) throw new Error('No source secret data');
if (source.metadata.uid!==restored.metadata.uid) throw new Error('Restored identity differs');
if (JSON.stringify(Object.entries(source.data).sort())!==JSON.stringify(Object.entries(restored.data).sort())) throw new Error('Restored secret differs');
for (const file of fs.readdirSync('/evidence').filter(file => /^source-.+-secrets[.]json$/.test(file))) {
  const identity = file => JSON.parse(fs.readFileSync(`/evidence/${file}`)).items.map(item => ({
    name: item.metadata.name, uid: item.metadata.uid, data: Object.entries(item.data ?? {}).sort(),
  })).sort((left, right) => left.name.localeCompare(right.name));
  if (JSON.stringify(identity(file)) !== JSON.stringify(identity(file.replace('source-', 'restored-')))) throw new Error('Restored application credentials differ');
}
console.log('Saved cluster state and encrypted secret recovery PASS');
JS
printf 'Cluster API and encrypted secret restoration PASS\n' > "$target/result.txt"
