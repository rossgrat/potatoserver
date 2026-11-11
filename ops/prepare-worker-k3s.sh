#!/usr/bin/env bash
set -euo pipefail
umask 077
script_dir=$(cd -- "$(dirname -- "$0")" && pwd)
tools_dir=$(dirname "$script_dir")
namespace=${1:?Pass wubzduh or job-board}
case "$namespace" in
  wubzduh) containers=(wubzduh wubzduh-postgres-1); database=wubzduh-postgres-1; port=30084 ;;
  job-board) containers=(job-board-api job-board-worker job-board-postgres); database=job-board-postgres; port=30085 ;;
  *) exit 2 ;;
esac
[[ $(bash "$script_dir/runtime-for.sh" "$namespace" /home/rossgrat/repos/network/deployments.conf) == docker ]]
evidence=/home/rossgrat/backups/$namespace-rehearsal-$(date -u +%Y%m%dT%H%M%SZ)
mkdir "$evidence"
printf '%s\n' "$evidence" > "$tools_dir/state/$namespace-rehearsal"
docker inspect "${containers[@]}" > "$evidence/containers.json"
node "$script_dir/prepare-worker-secrets.mjs" "$namespace" "$evidence"
export K3S_CONFIG_FILE=/dev/null
kubectl=(/usr/local/bin/k3s kubectl --kubeconfig /home/rossgrat/.kube/potatoserver-k3s.yaml)
"${kubectl[@]}" apply -f "$tools_dir/k3s/$namespace.yaml"
"${kubectl[@]}" apply -f "$evidence/database-secret.json" -f "$evidence/application-secret.json"
"${kubectl[@]}" rollout status statefulset/postgres -n "$namespace" --timeout=180s
bash "$script_dir/backup-database.sh" "$database" "$evidence/source-database" docker
bash "$script_dir/restore-database.sh" "$namespace" "$evidence/source-database"
"${kubectl[@]}" scale deployment/"$namespace" -n "$namespace" --replicas=1
"${kubectl[@]}" rollout status deployment/"$namespace" -n "$namespace" --timeout=180s
image=$(cat "$tools_dir/k3s/backup-image")
docker run --rm --network caddy-network --read-only -i --user "$(id -u):$(id -g)" -v "$evidence:/evidence" \
  --entrypoint node "$image" --input-type=module - "$namespace" "http://172.18.0.1:$port" < "$script_dir/test-worker-http.mjs"
"${kubectl[@]}" scale deployment/"$namespace" -n "$namespace" --replicas=0
"${kubectl[@]}" wait --for=delete pod -n "$namespace" -l app="$namespace" --timeout=60s
"${kubectl[@]}" exec -i -n "$namespace" postgres-0 -- sh -c \
  'exec psql -X -qAt -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB"' \
  < "$script_dir/database-fingerprint.sql" > "$evidence/before-replacement-fingerprint.txt"
"${kubectl[@]}" delete pod/postgres-0 -n "$namespace" --wait=true
"${kubectl[@]}" wait --for=condition=Ready pod/postgres-0 -n "$namespace" --timeout=120s
"${kubectl[@]}" exec -i -n "$namespace" postgres-0 -- sh -c \
  'exec psql -X -qAt -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB"' \
  < "$script_dir/database-fingerprint.sql" > "$evidence/replacement-fingerprint.txt"
diff -u "$evidence/before-replacement-fingerprint.txt" "$evidence/replacement-fingerprint.txt" > "$evidence/replacement.diff"
printf '%s preparation PASS. Docker remains live.\n' "$namespace" | tee "$evidence/result.txt"
