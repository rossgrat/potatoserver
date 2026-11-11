#!/usr/bin/env bash
set -euo pipefail
umask 077
script_dir=$(cd -- "$(dirname -- "$0")" && pwd)
tools_dir=$(dirname "$script_dir")
namespace=${1:?Pass wubzduh or job-board}
case "$namespace" in
  wubzduh) containers=(wubzduh); database=wubzduh-postgres-1; upstream=wubzduh:8080; port=30084; domain=wubzduh ;;
  job-board) containers=(job-board-worker job-board-api); database=job-board-postgres; upstream=job-board-api:8080; port=30085; domain=jobs ;;
  *) exit 2 ;;
esac
exec 9> "$tools_dir/state/operations.lock"
flock -n 9
runtime_config=/home/rossgrat/repos/network/deployments.conf
[[ $(bash "$script_dir/runtime-for.sh" "$namespace" "$runtime_config") == docker ]]
rehearsal=$(cat "$tools_dir/state/$namespace-rehearsal")
test -s "$rehearsal/result.txt"
test -f "$rehearsal/replacement.diff"
test ! -s "$rehearsal/replacement.diff"
evidence=/home/rossgrat/backups/$namespace-cutover-$(date -u +%Y%m%dT%H%M%SZ)
mkdir "$evidence"
printf '%s\n' "$evidence" > "$tools_dir/state/$namespace-cutover"
if [[ "$namespace" == job-board ]]; then cp "$rehearsal/http-auth.json" "$evidence/"; fi
docker inspect "${containers[@]}" "$database" > "$evidence/containers.json"
live=/home/rossgrat/repos/network/caddy/Caddyfile
cp "$live" "$evidence/Caddyfile.before"
[[ $(grep -Fc "reverse_proxy $upstream" "$live") == 1 ]]
sed "s/reverse_proxy $upstream/reverse_proxy 172.18.0.1:$port/" "$live" > "$evidence/Caddyfile.after"
docker exec -i caddy sh -c 'umask 077; cat > /tmp/worker-Caddyfile' < "$evidence/Caddyfile.after"
docker exec caddy caddy validate --config /tmp/worker-Caddyfile --adapter caddyfile > "$evidence/caddy-validation.txt" 2>&1
export K3S_CONFIG_FILE=/dev/null
kubectl=(/usr/local/bin/k3s kubectl --kubeconfig /home/rossgrat/.kube/potatoserver-k3s.yaml)
image=$(cat "$tools_dir/k3s/backup-image")
stopped=false
handover=false
cleanup() {
  result=$?
  if [[ "$namespace" == wubzduh ]]; then "${kubectl[@]}" delete pod/log-transfer -n wubzduh --ignore-not-found --wait=true >/dev/null || true; fi
  if ((result != 0)); then
    if "$handover"; then
      printf 'Cutover stopped after worker handover. Preserve the K3s database before any rollback.\n' >&2
    elif "$stopped"; then
      docker start "${containers[@]}" >/dev/null
      printf 'Cutover failed before worker handover. Original Docker services restarted.\n' >&2
    fi
  fi
}
trap cleanup EXIT
"${kubectl[@]}" scale deployment/"$namespace" -n "$namespace" --replicas=0
if [[ "$namespace" == job-board ]]; then "${kubectl[@]}" scale deployment/worker -n "$namespace" --replicas=0; fi
"${kubectl[@]}" wait --for=delete pod -n "$namespace" -l app="$namespace" --timeout=60s
docker stop --time 30 "${containers[@]}" >/dev/null
stopped=true
bash "$script_dir/backup-database.sh" "$database" "$evidence/source-database" docker
bash "$script_dir/restore-database.sh" "$namespace" "$evidence/source-database"
if [[ "$namespace" == wubzduh ]]; then
  helper_image=$(cat "$evidence/source-database/image.txt")
  docker run --rm --network none --read-only --volumes-from wubzduh:ro --entrypoint tar "$helper_image" \
    -C /var/log/wubzduh -cf - . > "$evidence/source-logs.tar"
  "${kubectl[@]}" apply -f "$tools_dir/k3s/wubzduh-log-transfer.yaml"
  "${kubectl[@]}" wait --for=condition=Ready pod/log-transfer -n wubzduh --timeout=120s
  "${kubectl[@]}" exec -i -n wubzduh log-transfer -- tar -C /logs -xf - < "$evidence/source-logs.tar"
  "${kubectl[@]}" exec -n wubzduh log-transfer -- tar -C /logs -cf - . > "$evidence/restored-logs.tar"
  for side in source restored; do
    mkdir "$evidence/$side-logs"
    tar -xf "$evidence/$side-logs.tar" -C "$evidence/$side-logs" --no-same-owner
    (cd "$evidence/$side-logs" && find . -type f -print0 | sort -z | xargs -0 sha256sum) > "$evidence/$side-logs.sha256"
  done
  diff -u "$evidence/source-logs.sha256" "$evidence/restored-logs.sha256" > "$evidence/logs.diff"
  "${kubectl[@]}" delete pod/log-transfer -n wubzduh --wait=true
fi
"${kubectl[@]}" apply -f "$tools_dir/k3s/$namespace-egress.yaml"
bash "$script_dir/set-runtime.sh" "$namespace" k3s "$runtime_config"
handover=true
"${kubectl[@]}" scale deployment/"$namespace" -n "$namespace" --replicas=1
"${kubectl[@]}" rollout status deployment/"$namespace" -n "$namespace" --timeout=180s
docker run --rm --network caddy-network --read-only -i --user "$(id -u):$(id -g)" -v "$evidence:/evidence" \
  --entrypoint node "$image" --input-type=module - "$namespace" "http://172.18.0.1:$port" < "$script_dir/test-worker-http.mjs"
if [[ "$namespace" == job-board ]]; then
  "${kubectl[@]}" scale deployment/worker -n "$namespace" --replicas=1
  "${kubectl[@]}" rollout status deployment/worker -n "$namespace" --timeout=180s
fi
cat "$evidence/Caddyfile.after" > "$live"
docker exec caddy caddy reload --config /etc/caddy/Caddyfile --adapter caddyfile > "$evidence/caddy-reload.txt" 2>&1
docker run --rm --network caddy-network --read-only -i --user "$(id -u):$(id -g)" -v "$evidence:/evidence" \
  --entrypoint node "$image" --input-type=module - "$namespace" "https://$domain.grattafiori.dev" < "$script_dir/test-worker-http.mjs"
bash "$script_dir/backup-database.sh" "$database" "$evidence/k3s-database"
"${kubectl[@]}" get deployments,statefulsets,services,persistentvolumeclaims,networkpolicies,configmaps,secrets -n "$namespace" -o yaml > "$evidence/resources.yaml"
docker update --restart=no "${containers[@]}" "$database" >/dev/null
docker stop --time 30 "$database" >/dev/null
docker exec caddy rm /tmp/worker-Caddyfile
printf '%s cutover PASS\n' "$namespace" | tee "$evidence/result.txt"
(cd "$evidence" && find . -type f ! -name SHA256SUMS -print0 | sort -z | xargs -0 sha256sum > SHA256SUMS)
