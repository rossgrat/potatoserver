#!/usr/bin/env bash
set -euo pipefail
umask 077
script_dir=$(cd -- "$(dirname -- "$0")" && pwd)
tools_dir=$(dirname "$script_dir")
exec 9> "$tools_dir/state/operations.lock"
flock -n 9
runtime_config=/home/rossgrat/repos/network/deployments.conf
[[ $(bash "$script_dir/runtime-for.sh" miniflux "$runtime_config") == docker ]]
rehearsal=$(cat "$tools_dir/state/miniflux-rehearsal")
test -s "$rehearsal/result.txt"
evidence=/home/rossgrat/backups/miniflux-cutover-$(date -u +%Y%m%dT%H%M%SZ)
mkdir "$evidence"
printf '%s\n' "$evidence" > "$tools_dir/state/miniflux-cutover"
cp "$rehearsal/http-auth.json" "$evidence/"
docker inspect miniflux-miniflux-1 miniflux-postgres-1 > "$evidence/containers.json"
live=/home/rossgrat/repos/network/caddy/Caddyfile
cp "$live" "$evidence/Caddyfile.before"
[[ $(grep -Fc 'reverse_proxy miniflux:8080' "$live") == 1 ]]
sed 's/reverse_proxy miniflux:8080/reverse_proxy 172.18.0.1:30081/' "$live" > "$evidence/Caddyfile.after"
docker exec -i caddy sh -c 'umask 077; cat > /tmp/miniflux-Caddyfile' < "$evidence/Caddyfile.after"
docker exec caddy caddy validate --config /tmp/miniflux-Caddyfile --adapter caddyfile > "$evidence/caddy-validation.txt" 2>&1
export K3S_CONFIG_FILE=/dev/null
kubectl=(/usr/local/bin/k3s kubectl --kubeconfig /home/rossgrat/.kube/potatoserver-k3s.yaml)
stopped=false
route_started=false
cleanup() {
  result=$?
  if ((result != 0)); then
    if "$route_started"; then
      printf 'Cutover failed after routing changed. Preserve K3s data before any rollback.\n' >&2
    elif "$stopped"; then
      "${kubectl[@]}" scale deployment/miniflux -n miniflux --replicas=0 >/dev/null || true
      bash "$script_dir/set-runtime.sh" miniflux docker "$runtime_config"
      docker start miniflux-miniflux-1 >/dev/null
      printf 'Cutover failed before routing changed. Docker Miniflux restarted.\n' >&2
    fi
  fi
}
trap cleanup EXIT
"${kubectl[@]}" scale deployment/miniflux -n miniflux --replicas=0
"${kubectl[@]}" wait --for=delete pod -n miniflux -l app=miniflux --timeout=60s
docker stop --time 30 miniflux-miniflux-1 >/dev/null
stopped=true
bash "$script_dir/backup-database.sh" miniflux-postgres-1 "$evidence/source-database"
bash "$script_dir/restore-database.sh" miniflux "$evidence/source-database"
"${kubectl[@]}" scale deployment/miniflux -n miniflux --replicas=1
"${kubectl[@]}" rollout status deployment/miniflux -n miniflux --timeout=120s
docker run --rm --network caddy-network --read-only -i -v "$evidence:/evidence:ro" \
  --entrypoint node "$(docker inspect --format '{{.Image}}' pages-cms-app-1)" \
  --input-type=module - http://172.18.0.1:30081 < "$script_dir/test-miniflux-http.mjs"
bash "$script_dir/set-runtime.sh" miniflux k3s "$runtime_config"
bash "$script_dir/backup-database.sh" miniflux-postgres-1 "$evidence/k3s-database"
"${kubectl[@]}" get deployments,statefulsets,services,persistentvolumeclaims,networkpolicies,secrets -n miniflux -o yaml > "$evidence/resources.yaml"
route_started=true
cat "$evidence/Caddyfile.after" > "$live"
docker exec caddy caddy reload --config /etc/caddy/Caddyfile --adapter caddyfile > "$evidence/caddy-reload.txt" 2>&1
curl --fail --max-time 15 -sS -o /dev/null -w 'Private RSS HTTP %{http_code} TLS %{ssl_verify_result}\n' https://rss.grattafiori.dev/
docker run --rm --network caddy-network --read-only -i -v "$evidence:/evidence:ro" \
  --entrypoint node "$(docker inspect --format '{{.Image}}' pages-cms-app-1)" \
  --input-type=module - https://rss.grattafiori.dev < "$script_dir/test-miniflux-http.mjs"
"${kubectl[@]}" apply -f "$tools_dir/k3s/miniflux-egress.yaml"
outbound=false
for _ in {1..10}; do
  if "${kubectl[@]}" exec -n miniflux deployment/miniflux -- wget -T 5 -qO /dev/null https://example.com > "$evidence/outbound-https.txt" 2>&1; then outbound=true; break; fi
  sleep 1
done
"$outbound"
"${kubectl[@]}" set env deployment/miniflux -n miniflux DISABLE_SCHEDULER_SERVICE=0
"${kubectl[@]}" rollout status deployment/miniflux -n miniflux --timeout=120s
ready=false
for _ in {1..15}; do
  if curl --fail --max-time 5 -sS -o /dev/null https://rss.grattafiori.dev/healthcheck > "$evidence/private-health.txt" 2>&1; then ready=true; break; fi
  sleep 1
done
"$ready"
docker update --restart=no miniflux-miniflux-1 miniflux-postgres-1 >/dev/null
docker stop --time 30 miniflux-postgres-1 >/dev/null
printf 'Miniflux cutover PASS\n' | tee "$evidence/result.txt"
