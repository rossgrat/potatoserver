#!/usr/bin/env bash
set -euo pipefail
umask 077
script_dir=$(cd -- "$(dirname -- "$0")" && pwd)
tools_dir=$(dirname "$script_dir")
evidence=${1:?Pass the installation evidence directory}
kubectl() {
  K3S_CONFIG_FILE=/dev/null /usr/local/bin/k3s kubectl --kubeconfig /home/rossgrat/.kube/potatoserver-k3s.yaml "$@"
}
namespace="potatoserver-check-$(date +%s)"
kubectl create namespace "$namespace"
cleanup() {
  kubectl get pods -n "$namespace" -o wide > "$evidence/probe-pods.txt" 2>&1 || true
  kubectl get events -n "$namespace" > "$evidence/probe-events.txt" 2>&1 || true
  kubectl delete namespace "$namespace" --wait=true --timeout=90s >/dev/null
}
trap cleanup EXIT
kubectl get --raw /readyz > "$evidence/api-ready.txt"
kubectl get --raw /version > "$evidence/api-version.json"
kubectl apply -n "$namespace" -f "$tools_dir/k3s/probe.yaml" > "$evidence/probe-apply.txt"
for pod in client blocked storage; do
  kubectl wait --for=create --for=condition=Ready "pod/$pod" -n "$namespace" --timeout=180s
done
kubectl rollout status deployment/web -n "$namespace" --timeout=180s
printf 'Testing cluster DNS, external DNS, and outbound HTTPS\n'
kubectl exec -n "$namespace" client -- nslookup kubernetes.default.svc.cluster.local > "$evidence/cluster-dns.txt"
kubectl exec -n "$namespace" client -- nslookup github.com > "$evidence/external-dns.txt"
kubectl exec -n "$namespace" client -- wget -T 10 -q -O /dev/null https://example.com > "$evidence/outbound-https.txt" 2>&1
expected=potatoserver-k3s-check
[[ $(kubectl exec -n "$namespace" client -- wget -T 5 -qO- http://web:8080/) == "$expected" ]]
[[ $(docker exec caddy wget -T 5 -qO- http://172.18.0.1:30080/) == "$expected" ]]
printf 'Testing persistent storage after application replacement\n'
printf '%s' "$namespace" | kubectl exec -i -n "$namespace" storage -- tee /data/marker > "$evidence/storage-write.txt"
kubectl delete pod/storage -n "$namespace" --wait=true --timeout=60s
kubectl apply -n "$namespace" -f "$tools_dir/k3s/probe.yaml" > /dev/null
kubectl wait --for=create --for=condition=Ready pod/storage -n "$namespace" --timeout=120s
[[ $(kubectl exec -n "$namespace" storage -- cat /data/marker) == "$namespace" ]]
printf 'Testing failed release and rollback\n'
kubectl patch deployment/web -n "$namespace" --type=json \
  -p '[{"op":"replace","path":"/spec/template/spec/containers/0/readinessProbe/httpGet/path","value":"/missing"},{"op":"replace","path":"/spec/progressDeadlineSeconds","value":20}]' > /dev/null
if kubectl rollout status deployment/web -n "$namespace" --timeout=45s > "$evidence/failed-release.txt" 2>&1; then exit 1; fi
[[ $(kubectl exec -n "$namespace" client -- wget -T 5 -qO- http://web:8080/) == "$expected" ]]
kubectl rollout undo deployment/web -n "$namespace" > "$evidence/rollback.txt"
kubectl rollout status deployment/web -n "$namespace" --timeout=120s
kubectl patch deployment/web -n "$namespace" --type=merge -p '{"spec":{"progressDeadlineSeconds":120}}' > /dev/null
kubectl apply -n "$namespace" -f "$tools_dir/k3s/probe-policy.yaml" > /dev/null
printf 'Testing network policy and administrative access restrictions\n'
service_ip=$(kubectl get service/web -n "$namespace" -o jsonpath='{.spec.clusterIP}')
blocked=false
for _ in {1..15}; do
  if ! kubectl exec -n "$namespace" blocked -- wget -T 3 -qO- "http://$service_ip:8080/" >/dev/null 2>&1; then blocked=true; break; fi
  sleep 1
done
"$blocked"
[[ $(kubectl exec -n "$namespace" client -- wget -T 5 -qO- http://web:8080/) == "$expected" ]]
docker run --rm --network caddy-network --read-only -i --entrypoint node \
  "$(docker inspect --format '{{.Image}}' pages-cms-app-1)" --input-type=module <<'JS'
import net from 'node:net';
const connect = port => new Promise(resolve => {
  const socket = net.createConnection({ host: '172.18.0.1', port });
  const finish = value => { socket.destroy(); resolve(value); };
  socket.setTimeout(3000);
  socket.on('connect', () => finish(true));
  socket.on('error', () => finish(false));
  socket.on('timeout', () => finish(false));
});
if (!await connect(80) || await connect(6443)) process.exit(1);
console.log('Host web port reachable; cluster administration blocked from Docker network');
JS
for url in https://stats.grattafiori.dev/ https://cms.grattafiori.dev/sign-in https://jobs.grattafiori.dev/ https://wubzduh.grattafiori.dev/ https://alerts.grattafiori.dev/v1/health https://rss.grattafiori.dev/ https://grafana.grattafiori.dev/; do
  curl --fail --max-time 15 -sS -o /dev/null -w '%{url_effective} HTTP %{http_code} TLS %{ssl_verify_result}\n' "$url"
done > "$evidence/application-routes.txt"
printf 'DNS, HTTPS, Caddy routing, persistent storage, failed release, rollback, and network policy PASS\n' | tee "$evidence/verification.txt"
