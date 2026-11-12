#!/usr/bin/env bash
set -euo pipefail
umask 077

script_dir=$(cd -- "$(dirname -- "$0")" && pwd)
backup=${1:?Pass a backup directory on potatoserver}

export K3S_CONFIG_FILE=/dev/null
kubectl=(/usr/local/bin/k3s kubectl --kubeconfig /home/rossgrat/.kube/potatoserver-k3s.yaml)

(cd "$backup" && sha256sum --check --quiet DATABASE_SHA256SUMS)
results_dir="$backup/restore-results"
mkdir -p "$results_dir"
namespace=

database_exec() {
  local stdin=()
  if [[ "$1" == -i ]]; then
    stdin=(-i)
    shift
  fi
  "${kubectl[@]}" exec "${stdin[@]}" -n "$namespace" postgres-0 -- "$@"
}

cleanup() {
  if [[ -n "$namespace" ]]; then
    "${kubectl[@]}" logs -n "$namespace" deployment/"$service" >"$results_dir/$backup_label-app.log" 2>&1 || true
    "${kubectl[@]}" delete namespace "$namespace" --wait=true --timeout=90s >/dev/null
  fi
}
trap cleanup EXIT

targets=(miniflux-postgres-1 job-board-postgres wubzduh-postgres-1 umami-postgres-1 pages-cms-postgres-1)
if (($# > 1)); then
  targets=("${@:2}")
fi
for backup_label in "${targets[@]}"; do
  case "$backup_label" in
    miniflux-postgres-1)
      service=miniflux
      health_path=/healthcheck
      ;;
    job-board-postgres)
      service=job-board
      health_path=/login
      ;;
    wubzduh-postgres-1)
      service=wubzduh
      health_path=/feed/
      ;;
    umami-postgres-1)
      service=umami
      health_path=/api/heartbeat
      ;;
    pages-cms-postgres-1)
      service=pages-cms
      health_path=/sign-in
      ;;
    *) exit 2 ;;
  esac
  started=$SECONDS
  namespace="potato-restore-$service-$(date +%s)"
  /usr/local/libexec/potatoserver-runtime/node-24.22.2 "$script_dir/applications.mjs" "$backup" "$backup_label" "$namespace" >"$results_dir/$backup_label-recovery.json"
  "${kubectl[@]}" apply -f "$results_dir/$backup_label-recovery.json" >"$results_dir/$backup_label-start.txt"
  "${kubectl[@]}" rollout status statefulset/postgres -n "$namespace" --timeout=180s
  database_exec -i sh -c '
exec pg_restore \
  -U "$POSTGRES_USER" \
  -d "$POSTGRES_DB" \
  --exit-on-error \
  --single-transaction \
  --no-owner \
  --no-privileges
' <"$backup/$backup_label/database.dump" >"$results_dir/$backup_label-restore.log" 2>&1
  database_exec -i sh -c 'exec psql -X -qAt -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB"' <"$script_dir/../../ops/lib/database-fingerprint.sql" >"$results_dir/$backup_label-fingerprint.txt"
  diff -u "$backup/$backup_label/source-fingerprint.txt" "$results_dir/$backup_label-fingerprint.txt" >"$results_dir/$backup_label-data.diff"
  database_exec sh -c 'exec pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" --schema-only --no-owner --no-privileges' >"$results_dir/$backup_label-schema.sql"
  for side in source restored; do
    file="$backup/$backup_label/schema.sql"
    if [[ "$side" == restored ]]; then
      file="$results_dir/$backup_label-schema.sql"
    fi
    sed '/^--/d; /^\\restrict /d; /^\\unrestrict /d; /^[[:space:]]*$/d' "$file" >"$results_dir/$backup_label-$side-schema.txt"
  done
  diff -u "$results_dir/$backup_label-source-schema.txt" "$results_dir/$backup_label-restored-schema.txt" >"$results_dir/$backup_label-schema.diff"
  database_exec sh -c 'exec pg_amcheck -U "$POSTGRES_USER" --database "$POSTGRES_DB" --install-missing' >"$results_dir/$backup_label-amcheck.txt" 2>&1
  database_exec -i sh -c 'exec psql -X -qAt -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB"' <"$script_dir/sequences.sql" >"$results_dir/$backup_label-sequences.txt"
  sed -n '/^ALTER ROLE /p' "$backup/$backup_label/globals.sql" | database_exec -i sh -c 'exec psql -X -q -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB"' >"$results_dir/$backup_label-roles.txt"
  database_exec sh -c '
PGPASSWORD="$POSTGRES_PASSWORD" psql \
  -X \
  -h postgres \
  -U "$POSTGRES_USER" \
  -d "$POSTGRES_DB" \
  -Atc "SELECT 1"
' >"$results_dir/$backup_label-password.txt"
  if database_exec sh -c '
PGPASSWORD=k3s-deliberately-incorrect psql \
  -X \
  -h postgres \
  -U "$POSTGRES_USER" \
  -d "$POSTGRES_DB" \
  -Atc "SELECT 1"
' >"$results_dir/$backup_label-invalid-password.txt" 2>&1; then
    exit 1
  fi
  grep -q 'password authentication failed' "$results_dir/$backup_label-invalid-password.txt"
  "${kubectl[@]}" scale deployment/"$service" -n "$namespace" --replicas=1 >/dev/null
  "${kubectl[@]}" rollout status deployment/"$service" -n "$namespace" --timeout=240s
  "${kubectl[@]}" wait --for=condition=Ready pod/client -n "$namespace" --timeout=120s
  port=$("${kubectl[@]}" get service/web -n "$namespace" -o jsonpath='{.spec.ports[0].port}')
  "${kubectl[@]}" exec -n "$namespace" client -- node -e '
fetch(process.argv[1], { redirect: "manual", signal: AbortSignal.timeout(10000) }).then((r) => {
  if (r.status < 200 || r.status >= 400) throw Error(`HTTP ${r.status}`);
  console.log(`HTTP ${r.status}`);
});
' "http://web:$port$health_path" >"$results_dir/$backup_label-http.txt"
  "${kubectl[@]}" logs -n "$namespace" deployment/"$service" >"$results_dir/$backup_label-app.log" 2>&1
  "${kubectl[@]}" delete namespace "$namespace" --wait=true --timeout=90s >/dev/null
  namespace=
  printf '%s K3s-native recovery PASS %ss\n' "$backup_label" "$((SECONDS - started))" | tee -a "$results_dir/native-summary.txt"
done
