#!/usr/bin/env bash
set -euo pipefail
umask 077
script_dir=$(cd -- "$(dirname -- "$0")" && pwd)
tools_dir=$(dirname "$script_dir")
exec 9> "$tools_dir/state/operations.lock"
flock -n 9
runtime_config=/home/rossgrat/repos/network/deployments.conf
[[ $(bash "$script_dir/runtime-for.sh" umami "$runtime_config") == docker ]]
rehearsal=$(cat "$tools_dir/state/umami-rehearsal")
test -s "$rehearsal/result.txt"
test -f "$rehearsal/k3s-database/recovery.diff"
test ! -s "$rehearsal/k3s-database/recovery.diff"
evidence=/home/rossgrat/backups/umami-cutover-$(date -u +%Y%m%dT%H%M%SZ)
mkdir "$evidence"
printf '%s\n' "$evidence" > "$tools_dir/state/umami-cutover"
cp "$rehearsal/http-auth.json" "$rehearsal/source-http.json" "$evidence/"
docker inspect umami umami-postgres-1 > "$evidence/containers.json"
live=/home/rossgrat/repos/network/caddy/Caddyfile
cp "$live" "$evidence/Caddyfile.before"
[[ $(grep -Fc 'reverse_proxy umami:3000' "$live") == 1 ]]
sed 's/reverse_proxy umami:3000/reverse_proxy 172.18.0.1:30082/' "$live" > "$evidence/Caddyfile.after"
docker exec -i caddy sh -c 'umask 077; cat > /tmp/umami-Caddyfile' < "$evidence/Caddyfile.after"
docker exec caddy caddy validate --config /tmp/umami-Caddyfile --adapter caddyfile > "$evidence/caddy-validation.txt" 2>&1
export K3S_CONFIG_FILE=/dev/null
kubectl=(/usr/local/bin/k3s kubectl --kubeconfig /home/rossgrat/.kube/potatoserver-k3s.yaml)
image=$(cat "$tools_dir/k3s/backup-image")
http_test() {
  docker run --rm --network caddy-network --read-only -i --user "$(id -u):$(id -g)" -v "$evidence:/evidence" \
    --entrypoint node "$image" --input-type=module - "$@" < "$script_dir/test-umami-http.mjs"
}
stopped=false
route_started=false
cleanup() {
  result=$?
  if ((result != 0)); then
    if "$route_started"; then
      printf 'Cutover failed after routing changed. Preserve K3s data before any rollback.\n' >&2
    elif "$stopped"; then
      "${kubectl[@]}" scale deployment/umami -n umami --replicas=0 >/dev/null || true
      bash "$script_dir/set-runtime.sh" umami docker "$runtime_config"
      docker start umami >/dev/null
      printf 'Cutover failed before routing changed. Docker Umami restarted.\n' >&2
    fi
  fi
}
trap cleanup EXIT
"${kubectl[@]}" scale deployment/umami -n umami --replicas=0
"${kubectl[@]}" wait --for=delete pod -n umami -l app=umami --timeout=60s
docker stop --time 30 umami >/dev/null
stopped=true
bash "$script_dir/backup-database.sh" umami-postgres-1 "$evidence/source-database"
bash "$script_dir/restore-database.sh" umami "$evidence/source-database"
"${kubectl[@]}" scale deployment/umami -n umami --replicas=1
"${kubectl[@]}" rollout status deployment/umami -n umami --timeout=180s
http_test http://172.18.0.1:30082 test
bash "$script_dir/set-runtime.sh" umami k3s "$runtime_config"
bash "$script_dir/backup-database.sh" umami-postgres-1 "$evidence/k3s-database"
"${kubectl[@]}" get deployments,statefulsets,services,persistentvolumeclaims,networkpolicies,secrets -n umami -o yaml > "$evidence/resources.yaml"
route_started=true
cat "$evidence/Caddyfile.after" > "$live"
docker exec caddy caddy reload --config /etc/caddy/Caddyfile --adapter caddyfile > "$evidence/caddy-reload.txt" 2>&1
ready=false
for _ in {1..15}; do
  if curl --fail --max-time 5 -sS -o /dev/null https://stats.grattafiori.dev/api/heartbeat > "$evidence/public-health.txt" 2>&1; then ready=true; break; fi
  sleep 1
done
"$ready"
http_test https://stats.grattafiori.dev collect
docker run --rm --network none --read-only -i --user "$(id -u):$(id -g)" -v "$evidence:/evidence" \
  --entrypoint node "$image" --input-type=module < "$script_dir/verify-umami-collection.mjs"
"${kubectl[@]}" exec -i -n umami postgres-0 -- sh -c \
  'exec psql -X -qAt -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB"' < "$evidence/collection-check.sql"
docker update --restart=no umami umami-postgres-1 >/dev/null
docker stop --time 30 umami-postgres-1 >/dev/null
docker exec caddy rm /tmp/umami-Caddyfile
printf 'Umami cutover PASS\n' | tee "$evidence/result.txt"
manifest=$(mktemp)
(cd "$evidence" && find . -type f ! -name SHA256SUMS -print0 | sort -z | xargs -0 sha256sum) > "$manifest"
mv "$manifest" "$evidence/SHA256SUMS"
