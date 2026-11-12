#!/usr/bin/env bash
set -euo pipefail
umask 077
script_dir=$(cd -- "$(dirname -- "$0")" && pwd)
backup=${1:?Pass a backup directory on potatoserver}
export K3S_CONFIG_FILE=/dev/null
K=(/usr/local/bin/k3s kubectl --kubeconfig /home/rossgrat/.kube/potatoserver-k3s.yaml)
(cd "$backup" && sha256sum --check --quiet DATABASE_SHA256SUMS)
mkdir -p "$backup/restore-results"
namespace=
cleanup() {
  if [[ -n "$namespace" ]]; then
    "${K[@]}" logs -n "$namespace" deployment/"$service" > "$backup/restore-results/$target-app.log" 2>&1 || true
    "${K[@]}" delete namespace "$namespace" --wait=true --timeout=90s >/dev/null
  fi
}
trap cleanup EXIT
targets=(miniflux-postgres-1 job-board-postgres wubzduh-postgres-1 umami-postgres-1 pages-cms-postgres-1)
if (($# > 1)); then targets=("${@:2}"); fi
for target in "${targets[@]}"; do
  case "$target" in
    miniflux-postgres-1) service=miniflux; path=/healthcheck ;;
    job-board-postgres) service=job-board; path=/login ;;
    wubzduh-postgres-1) service=wubzduh; path=/feed/ ;;
    umami-postgres-1) service=umami; path=/api/heartbeat ;;
    pages-cms-postgres-1) service=pages-cms; path=/sign-in ;;
    *) exit 2 ;;
  esac
  started=$SECONDS
  namespace="potato-restore-$service-$(date +%s)"
  /usr/local/libexec/potatoserver-runtime/node-24.22.2 "$script_dir/applications.mjs" "$backup" "$target" "$namespace" > "$backup/restore-results/$target-recovery.json"
  "${K[@]}" apply -f "$backup/restore-results/$target-recovery.json" > "$backup/restore-results/$target-start.txt"
  "${K[@]}" rollout status statefulset/postgres -n "$namespace" --timeout=180s
  "${K[@]}" exec -i -n "$namespace" postgres-0 -- sh -c 'exec pg_restore -U "$POSTGRES_USER" -d "$POSTGRES_DB" --exit-on-error --single-transaction --no-owner --no-privileges' < "$backup/$target/database.dump" > "$backup/restore-results/$target-restore.log" 2>&1
  "${K[@]}" exec -i -n "$namespace" postgres-0 -- sh -c 'exec psql -X -qAt -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB"' < "$script_dir/../../ops/lib/database-fingerprint.sql" > "$backup/restore-results/$target-fingerprint.txt"
  diff -u "$backup/$target/source-fingerprint.txt" "$backup/restore-results/$target-fingerprint.txt" > "$backup/restore-results/$target-data.diff"
  "${K[@]}" exec -n "$namespace" postgres-0 -- sh -c 'exec pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" --schema-only --no-owner --no-privileges' > "$backup/restore-results/$target-schema.sql"
  for side in source restored; do
    file="$backup/$target/schema.sql"
    if [[ "$side" == restored ]]; then file="$backup/restore-results/$target-schema.sql"; fi
    sed '/^--/d; /^\\restrict /d; /^\\unrestrict /d; /^[[:space:]]*$/d' "$file" > "$backup/restore-results/$target-$side-schema.txt"
  done
  diff -u "$backup/restore-results/$target-source-schema.txt" "$backup/restore-results/$target-restored-schema.txt" > "$backup/restore-results/$target-schema.diff"
  "${K[@]}" exec -n "$namespace" postgres-0 -- sh -c 'exec pg_amcheck -U "$POSTGRES_USER" --database "$POSTGRES_DB" --install-missing' > "$backup/restore-results/$target-amcheck.txt" 2>&1
  "${K[@]}" exec -i -n "$namespace" postgres-0 -- sh -c 'exec psql -X -qAt -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB"' < "$script_dir/sequences.sql" > "$backup/restore-results/$target-sequences.txt"
  sed -n '/^ALTER ROLE /p' "$backup/$target/globals.sql" | "${K[@]}" exec -i -n "$namespace" postgres-0 -- sh -c 'exec psql -X -q -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB"' > "$backup/restore-results/$target-roles.txt"
  "${K[@]}" exec -n "$namespace" postgres-0 -- sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" psql -X -h postgres -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Atc "SELECT 1"' > "$backup/restore-results/$target-password.txt"
  if "${K[@]}" exec -n "$namespace" postgres-0 -- sh -c 'PGPASSWORD=k3s-deliberately-incorrect psql -X -h postgres -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Atc "SELECT 1"' > "$backup/restore-results/$target-invalid-password.txt" 2>&1; then exit 1; fi
  grep -q 'password authentication failed' "$backup/restore-results/$target-invalid-password.txt"
  "${K[@]}" scale deployment/"$service" -n "$namespace" --replicas=1 >/dev/null
  "${K[@]}" rollout status deployment/"$service" -n "$namespace" --timeout=240s
  "${K[@]}" wait --for=condition=Ready pod/client -n "$namespace" --timeout=120s
  port=$("${K[@]}" get service/web -n "$namespace" -o jsonpath='{.spec.ports[0].port}')
  "${K[@]}" exec -n "$namespace" client -- node -e 'fetch(process.argv[1],{redirect:"manual",signal:AbortSignal.timeout(10000)}).then(r=>{if(r.status<200||r.status>=400)throw Error(`HTTP ${r.status}`);console.log(`HTTP ${r.status}`)})' "http://web:$port$path" > "$backup/restore-results/$target-http.txt"
  "${K[@]}" logs -n "$namespace" deployment/"$service" > "$backup/restore-results/$target-app.log" 2>&1
  "${K[@]}" delete namespace "$namespace" --wait=true --timeout=90s >/dev/null
  namespace=
  printf '%s K3s-native recovery PASS %ss\n' "$target" "$((SECONDS-started))" | tee -a "$backup/restore-results/native-summary.txt"
done
