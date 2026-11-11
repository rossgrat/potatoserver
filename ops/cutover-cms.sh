#!/usr/bin/env bash
set -euo pipefail
umask 077
script_dir=$(cd -- "$(dirname -- "$0")" && pwd)
tools_dir=$(dirname "$script_dir")
exec 9> "$tools_dir/state/operations.lock"
flock -n 9
runtime_config=/home/rossgrat/repos/network/deployments.conf
[[ $(bash "$script_dir/runtime-for.sh" pages-cms "$runtime_config") == docker ]]
rehearsal=$(cat "$tools_dir/state/pages-cms-rehearsal")
test -s "$rehearsal/result.txt"
test -s "$rehearsal/source-repositories.json"
test -f "$rehearsal/k3s-database/recovery.diff"
test ! -s "$rehearsal/k3s-database/recovery.diff"
evidence=/home/rossgrat/backups/pages-cms-cutover-$(date -u +%Y%m%dT%H%M%SZ)
mkdir "$evidence"
printf '%s\n' "$evidence" > "$tools_dir/state/pages-cms-cutover"
cp "$rehearsal/http-auth.json" "$rehearsal/source-repositories.json" "$evidence/"
docker inspect pages-cms-app-1 pages-cms-postgres-1 > "$evidence/containers.json"
live=/home/rossgrat/repos/network/caddy/Caddyfile
cp "$live" "$evidence/Caddyfile.before"
[[ $(grep -Fc 'reverse_proxy pages-cms:3000' "$live") == 1 ]]
sed 's/reverse_proxy pages-cms:3000/reverse_proxy 172.18.0.1:30083/' "$live" > "$evidence/Caddyfile.after"
docker exec -i caddy sh -c 'umask 077; cat > /tmp/pages-cms-Caddyfile' < "$evidence/Caddyfile.after"
docker exec caddy caddy validate --config /tmp/pages-cms-Caddyfile --adapter caddyfile > "$evidence/caddy-validation.txt" 2>&1
export K3S_CONFIG_FILE=/dev/null
kubectl=(/usr/local/bin/k3s kubectl --kubeconfig /home/rossgrat/.kube/potatoserver-k3s.yaml)
image=$(cat "$tools_dir/k3s/backup-image")
http_test() {
  docker run --rm --network caddy-network --read-only -i --user "$(id -u):$(id -g)" -v "$evidence:/evidence" \
    --entrypoint node "$image" --input-type=module - "$@" < "$script_dir/test-cms-http.mjs"
}
stopped=false
route_started=false
cleanup() {
  result=$?
  if ((result != 0)); then
    if "$route_started"; then
      printf 'Cutover failed after routing changed. Preserve K3s data before any rollback.\n' >&2
    elif "$stopped"; then
      "${kubectl[@]}" scale deployment/pages-cms -n pages-cms --replicas=0 >/dev/null || true
      bash "$script_dir/set-runtime.sh" pages-cms docker "$runtime_config"
      docker start pages-cms-app-1 >/dev/null
      printf 'Cutover failed before routing changed. Docker CMS restarted.\n' >&2
    fi
  fi
}
trap cleanup EXIT
"${kubectl[@]}" scale deployment/pages-cms -n pages-cms --replicas=0
"${kubectl[@]}" wait --for=delete pod -n pages-cms -l app=pages-cms --timeout=60s
docker stop --time 30 pages-cms-app-1 >/dev/null
stopped=true
bash "$script_dir/backup-database.sh" pages-cms-postgres-1 "$evidence/source-database"
bash "$script_dir/restore-database.sh" pages-cms "$evidence/source-database"
"${kubectl[@]}" scale deployment/pages-cms -n pages-cms --replicas=1
"${kubectl[@]}" rollout status deployment/pages-cms -n pages-cms --timeout=180s
http_test http://172.18.0.1:30083 basic
bash "$script_dir/set-runtime.sh" pages-cms k3s "$runtime_config"
"${kubectl[@]}" get deployments,statefulsets,services,persistentvolumeclaims,networkpolicies,secrets -n pages-cms -o yaml > "$evidence/resources.yaml"
route_started=true
cat "$evidence/Caddyfile.after" > "$live"
docker exec caddy caddy reload --config /etc/caddy/Caddyfile --adapter caddyfile > "$evidence/caddy-reload.txt" 2>&1
ready=false
for _ in {1..15}; do
  if curl --fail --max-time 5 -sS -o /dev/null https://cms.grattafiori.dev/sign-in > "$evidence/public-health.txt" 2>&1; then ready=true; break; fi
  sleep 1
done
"$ready"
"${kubectl[@]}" apply -f "$tools_dir/k3s/pages-cms-egress.yaml"
outbound=false
for _ in {1..5}; do
  if "${kubectl[@]}" exec -n pages-cms deployment/pages-cms -- node -e 'fetch("https://example.com",{signal:AbortSignal.timeout(3000)}).then(response=>process.exit(response.ok?0:1),()=>process.exit(1))' > "$evidence/outbound-https.txt" 2>&1; then outbound=true; break; fi
  sleep 1
done
"$outbound"
http_test https://cms.grattafiori.dev repositories
bash "$script_dir/backup-database.sh" pages-cms-postgres-1 "$evidence/k3s-database"
docker update --restart=no pages-cms-app-1 pages-cms-postgres-1 >/dev/null
docker stop --time 30 pages-cms-postgres-1 >/dev/null
docker exec caddy rm /tmp/pages-cms-Caddyfile
printf 'CMS cutover PASS\n' | tee "$evidence/result.txt"
manifest=$(mktemp)
(cd "$evidence" && find . -type f ! -name SHA256SUMS -print0 | sort -z | xargs -0 sha256sum) > "$manifest"
mv "$manifest" "$evidence/SHA256SUMS"
