#!/usr/bin/env bash
set -euo pipefail
umask 077
script_dir=$(cd -- "$(dirname -- "$0")" && pwd)
tools_dir=$(dirname "$script_dir")
exec 9> "$tools_dir/state/operations.lock"
flock -n 9
runtime_config=/home/rossgrat/repos/network/deployments.conf
[[ $(bash "$script_dir/runtime-for.sh" ntfy "$runtime_config") == docker ]]
rehearsal=$(cat "$tools_dir/state/ntfy-rehearsal")
test -s "$rehearsal/result.txt"
evidence=/home/rossgrat/backups/ntfy-cutover-$(date -u +%Y%m%dT%H%M%SZ)
mkdir "$evidence"
printf '%s\n' "$evidence" > "$tools_dir/state/ntfy-cutover"
docker inspect ntfy > "$evidence/container.json"
live=/home/rossgrat/repos/network/caddy/Caddyfile
cp "$live" "$evidence/Caddyfile.before"
[[ $(grep -Fc 'reverse_proxy ntfy:80' "$live") == 1 ]]
sed 's/reverse_proxy ntfy:80/reverse_proxy 172.18.0.1:30086/' "$live" > "$evidence/Caddyfile.after"
docker exec -i caddy sh -c 'umask 077; cat > /tmp/ntfy-Caddyfile' < "$evidence/Caddyfile.after"
docker exec caddy caddy validate --config /tmp/ntfy-Caddyfile --adapter caddyfile > "$evidence/caddy-validation.txt" 2>&1
export K3S_CONFIG_FILE=/dev/null
kubectl=(/usr/local/bin/k3s kubectl --kubeconfig /home/rossgrat/.kube/potatoserver-k3s.yaml)
image=$(cat "$tools_dir/k3s/backup-image")
stopped=false
handover=false
cleanup() {
  result=$?
  if ((result != 0)); then
    if "$handover"; then
      printf 'ntfy handover stopped. Preserve the K3s state before any rollback.\n' >&2
    elif "$stopped"; then
      "${kubectl[@]}" scale deployment/ntfy -n ntfy --replicas=0 >/dev/null || true
      docker start ntfy >/dev/null
      printf 'ntfy handover failed before the route changed. Docker restarted.\n' >&2
    fi
  fi
}
trap cleanup EXIT
"${kubectl[@]}" scale deployment/ntfy -n ntfy --replicas=0
"${kubectl[@]}" wait --for=delete pod -n ntfy -l app=ntfy --timeout=60s
docker stop --time 30 ntfy >/dev/null
stopped=true
for entry in /var/lib/ntfy:auth /var/cache/ntfy:cache; do
  mount=${entry%:*}; name=${entry#*:}
  docker run --rm --network none --read-only --volumes-from ntfy:ro --entrypoint tar "$image" -C "$mount" -cf - . > "$evidence/$name.tar"
done
bash "$script_dir/restore-ntfy-state.sh" "$evidence"
"${kubectl[@]}" scale deployment/ntfy -n ntfy --replicas=1
"${kubectl[@]}" rollout status deployment/ntfy -n ntfy --timeout=120s
docker run --rm --network caddy-network --read-only -i --user "$(id -u):$(id -g)" -v "$evidence:/evidence:ro" \
  --entrypoint node "$image" --input-type=module - http://172.18.0.1:30086 < "$script_dir/test-ntfy-http.mjs"
bash "$script_dir/set-runtime.sh" ntfy k3s "$runtime_config"
handover=true
cat "$evidence/Caddyfile.after" > "$live"
docker exec caddy caddy reload --config /etc/caddy/Caddyfile --adapter caddyfile > "$evidence/caddy-reload.txt" 2>&1
"${kubectl[@]}" apply -f "$tools_dir/k3s/ntfy-egress.yaml"
docker run --rm --network caddy-network --read-only -i --user "$(id -u):$(id -g)" -v "$evidence:/evidence:ro" \
  --entrypoint node "$image" --input-type=module - https://alerts.grattafiori.dev < "$script_dir/test-ntfy-http.mjs"
bash "$script_dir/backup-ntfy.sh" "$evidence"
docker update --restart=no ntfy >/dev/null
"${kubectl[@]}" get deployments,services,persistentvolumeclaims,networkpolicies,configmaps,secrets -n ntfy -o yaml > "$evidence/resources.yaml"
docker exec caddy rm /tmp/ntfy-Caddyfile
printf 'ntfy cutover PASS\n' | tee "$evidence/result.txt"
(cd "$evidence" && find . -type f ! -name SHA256SUMS -print0 | sort -z | xargs -0 sha256sum > SHA256SUMS)
