#!/usr/bin/env bash
set -euo pipefail
umask 077
script_dir=$(cd -- "$(dirname -- "$0")" && pwd)
namespace=${1:?Pass the target namespace}
backup=${2:?Pass a database backup directory}
export K3S_CONFIG_FILE=/dev/null
kubectl=(/usr/local/bin/k3s kubectl --kubeconfig /home/rossgrat/.kube/potatoserver-k3s.yaml)
[[ $("${kubectl[@]}" get deployment/"$namespace" -n "$namespace" -o jsonpath='{.spec.replicas}') == 0 ]]
[[ -z $("${kubectl[@]}" get pods -n "$namespace" -l app="$namespace" -o name) ]]
"${kubectl[@]}" exec -n "$namespace" postgres-0 -- sh -ec \
  'dropdb -U "$POSTGRES_USER" --force "$POSTGRES_DB"; createdb -U "$POSTGRES_USER" -O "$POSTGRES_USER" "$POSTGRES_DB"'
"${kubectl[@]}" exec -i -n "$namespace" postgres-0 -- sh -c \
  'exec pg_restore -U "$POSTGRES_USER" -d "$POSTGRES_DB" --exit-on-error --single-transaction --no-owner --no-privileges' \
  < "$backup/database.dump" > "$backup/restore.log" 2>&1
"${kubectl[@]}" exec -i -n "$namespace" postgres-0 -- sh -c \
  'exec psql -X -qAt -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB"' \
  < "$script_dir/database-fingerprint.sql" > "$backup/restored-fingerprint.txt"
diff -u "$backup/source-fingerprint.txt" "$backup/restored-fingerprint.txt" > "$backup/data.diff"
"${kubectl[@]}" exec -n "$namespace" postgres-0 -- sh -c \
  'exec pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" --schema-only --no-owner --no-privileges' > "$backup/restored-schema.sql"
normalize_schema() {
  sed '/^--/d; /^\\restrict /d; /^\\unrestrict /d; /^[[:space:]]*$/d' "$1"
}
normalize_schema "$backup/schema.sql" > "$backup/source-schema.txt"
normalize_schema "$backup/restored-schema.sql" > "$backup/restored-schema.txt"
diff -u "$backup/source-schema.txt" "$backup/restored-schema.txt" > "$backup/schema.diff"
"${kubectl[@]}" exec -n "$namespace" postgres-0 -- sh -c \
  'exec pg_amcheck -U "$POSTGRES_USER" --database "$POSTGRES_DB" --install-missing' > "$backup/amcheck.txt" 2>&1
"${kubectl[@]}" exec -i -n "$namespace" postgres-0 -- sh -c \
  'exec psql -X -qAt -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB"' \
  < "$script_dir/sequence-check.sql" > "$backup/sequences.txt"
printf '%s data, schema, indexes, and sequences PASS\n' "$namespace"
