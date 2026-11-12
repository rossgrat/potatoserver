#!/usr/bin/env bash
set -euo pipefail
umask 077

script_dir=$(cd -- "$(dirname -- "$0")" && pwd)
namespace=${1:?Pass miniflux, umami, pages-cms, wubzduh, or job-board}
target=${2:?Pass a new backup directory}
case "$namespace" in
  miniflux | umami | pages-cms | wubzduh | job-board) ;;
  *) exit 2 ;;
esac
case "$target" in
  /home/rossgrat/backups/*) ;;
  *) exit 2 ;;
esac
mkdir "$target"

export K3S_CONFIG_FILE=/dev/null
kubectl=(/usr/local/bin/k3s kubectl --kubeconfig /home/rossgrat/.kube/potatoserver-k3s.yaml)

"${kubectl[@]}" get statefulset/postgres -n "$namespace" -o jsonpath='{.spec.template.spec.containers[0].image}' >"$target/image.txt"

database_exec() {
  local stdin=()
  if [[ "$1" == -i ]]; then
    stdin=(-i)
    shift
  fi
  "${kubectl[@]}" exec "${stdin[@]}" -n "$namespace" -c postgres postgres-0 -- "$@"
}
database_exec sh -c 'printf "%s\n%s\n" "$POSTGRES_USER" "$POSTGRES_DB"' >"$target/connection.txt"
snapshot_pid=

cleanup() {
  if [[ -n "$snapshot_pid" ]]; then
    kill "$snapshot_pid" 2>/dev/null || true
  fi
}
trap cleanup EXIT

coproc SNAPSHOT {
  database_exec -i sh -c 'exec psql -X -qAt -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB"'
}
snapshot_pid=${SNAPSHOT_PID:?}
printf 'BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY;\nSELECT pg_export_snapshot();\n' >&"${SNAPSHOT[1]}"
read -r -t 30 snapshot <&"${SNAPSHOT[0]}"
[[ "$snapshot" =~ ^[0-9A-F]+-[0-9A-F]+-[0-9]+$ ]]
database_exec sh -c 'exec pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Fc --snapshot="$1"' sh "$snapshot" >"$target/database.dump"
database_exec sh -c '
exec pg_dump \
  -U "$POSTGRES_USER" \
  -d "$POSTGRES_DB" \
  --schema-only \
  --no-owner \
  --no-privileges \
  --snapshot="$1"
' sh "$snapshot" >"$target/schema.sql"
cat "$script_dir/lib/database-fingerprint.sql" >&"${SNAPSHOT[1]}"
printf '\n\\echo FINGERPRINT_COMPLETE\n' >&"${SNAPSHOT[1]}"
while read -r -t 180 line <&"${SNAPSHOT[0]}"; do
  if [[ "$line" == FINGERPRINT_COMPLETE ]]; then
    break
  fi
  printf '%s\n' "$line" >>"$target/source-fingerprint.txt"
done
[[ "$line" == FINGERPRINT_COMPLETE ]]
printf 'ROLLBACK;\n\\q\n' >&"${SNAPSHOT[1]}"
wait "$snapshot_pid"
snapshot_pid=
database_exec sh -c 'exec pg_dumpall -U "$POSTGRES_USER" --globals-only' >"$target/globals.sql"
"${kubectl[@]}" get deployments,statefulsets,services,persistentvolumeclaims,networkpolicies,configmaps,secrets -n "$namespace" -o json >"$target/resources.json"
if [[ "$namespace" == umami ]]; then
  cp /home/rossgrat/.config/umami/admin.json "$target/http-auth.json"
fi
printf 'Database backup: %s (k3s)\n' "$namespace"
