#!/usr/bin/env bash
set -euo pipefail
umask 077
script_dir=$(cd -- "$(dirname -- "$0")" && pwd)
backup_dir=${1:?Pass a backup directory on potatoserver}
cd "$backup_dir"
sha256sum --check --quiet DATABASE_SHA256SUMS
mkdir -p restore-results/configuration
tar -xzf configuration.tar.gz -C restore-results/configuration --no-same-owner --same-permissions
cms_image=$(docker inspect --format '{{.Image}}' pages-cms-app-1)
restore_container=
restore_network=
app_file=
project=
cleanup() {
  if [[ -n "$app_file" ]]; then
    docker compose -p "$project" -f "$app_file" logs --no-color > "restore-results/$target-app.log" 2>&1 || true
    docker compose -p "$project" -f "$app_file" down --volumes >/dev/null 2>&1
  fi
  if [[ -n "$restore_container" ]]; then docker rm -fv "$restore_container" >/dev/null; fi
  if [[ -n "$restore_network" ]]; then docker network rm "$restore_network" >/dev/null; fi
}
trap cleanup EXIT
normalize_schema() {
  sed '/^--/d; /^\\restrict /d; /^\\unrestrict /d; /^[[:space:]]*$/d' "$1"
}
targets=(miniflux-postgres-1 job-board-postgres wubzduh-postgres-1 umami-postgres-1 pages-cms-postgres-1)
if (($# > 1)); then targets=("${@:2}"); fi
for target in "${targets[@]}"; do
  started=$SECONDS
  role=$(sed -n '1p' "$target/connection.txt")
  database=$(sed -n '2p' "$target/connection.txt")
  image=$(cat "$target/image.txt")
  restore_network=$(docker network create --internal --label potatoserver.task=k3s-restore "k3s-restore-$target-$$")
  restore_container=$(docker run -d --label potatoserver.task=k3s-restore \
    --network "$restore_network" --network-alias postgres --memory 512m --cpus 1 \
    -e POSTGRES_HOST_AUTH_METHOD=trust -e "POSTGRES_USER=$role" -e "POSTGRES_DB=$database" \
    "$image")
  ready=false
  attempts=0
  while ((attempts < 60)); do
    if docker exec "$restore_container" psql -X -h 127.0.0.1 -U "$role" -d "$database" -Atc 'SELECT 1' >/dev/null 2>&1; then ready=true; break; fi
    sleep 1
    attempts=$((attempts+1))
  done
  "$ready"
  docker exec -i "$restore_container" pg_restore -U "$role" -d "$database" \
    --exit-on-error --single-transaction --no-owner --no-privileges \
    < "$target/database.dump" > "restore-results/$target-restore.log" 2>&1
  docker exec -i "$restore_container" psql -X -qAt -v ON_ERROR_STOP=1 -U "$role" -d "$database" \
    < "$script_dir/database-fingerprint.sql" > "restore-results/$target-fingerprint.txt"
  diff -u "$target/source-fingerprint.txt" "restore-results/$target-fingerprint.txt" \
    > "restore-results/$target-data.diff"
  docker exec "$restore_container" pg_dump -U "$role" -d "$database" \
    --schema-only --no-owner --no-privileges > "restore-results/$target-schema.sql"
  normalize_schema "$target/schema.sql" > "restore-results/$target-source-schema.txt"
  normalize_schema "restore-results/$target-schema.sql" > "restore-results/$target-restored-schema.txt"
  diff -u "restore-results/$target-source-schema.txt" "restore-results/$target-restored-schema.txt" \
    > "restore-results/$target-schema.diff"
  docker exec "$restore_container" pg_amcheck -U "$role" --database "$database" --install-missing \
    > "restore-results/$target-amcheck.txt" 2>&1
  docker exec -i "$restore_container" psql -X -qAt -v ON_ERROR_STOP=1 -U "$role" -d "$database" \
    < "$script_dir/sequence-check.sql" > "restore-results/$target-sequences.txt"
  docker run --rm --network none --read-only -i --user "$(id -u):$(id -g)" \
    -v "$PWD:/backup" --entrypoint node "$cms_image" --input-type=module - "$PWD" "$target" "$restore_network" \
    < "$script_dir/restore-application.mjs"
  sed -n '/^ALTER ROLE /p' "$target/globals.sql" | docker exec -i "$restore_container" \
    psql -X -q -v ON_ERROR_STOP=1 -U "$role" -d "$database" > "restore-results/$target-roles.txt"
  docker exec "$restore_container" sh -c 'sed -i "s/^host all all all trust$/host all all all scram-sha-256/" "$PGDATA/pg_hba.conf"'
  docker exec "$restore_container" psql -X -qAt -U "$role" -d "$database" -c 'SELECT pg_reload_conf()' > /dev/null
  docker run --rm --network "$restore_network" --env-file "restore-results/$target-password.env" \
    --entrypoint psql "$image" -X -h postgres -U "$role" -d "$database" -Atc 'SELECT 1' \
    > "restore-results/$target-password.txt"
  if docker run --rm --network "$restore_network" -e PGPASSWORD=k3s-deliberately-incorrect \
    --entrypoint psql "$image" -X -h postgres -U "$role" -d "$database" -Atc 'SELECT 1' \
    > "restore-results/$target-invalid-password.txt" 2>&1; then exit 1; fi
  grep -q 'password authentication failed' "restore-results/$target-invalid-password.txt"
  app_file="$PWD/restore-results/$target-app.json"
  project="k3s-recovery-$target-$$"
  docker compose -p "$project" -f "$app_file" up -d --no-build \
    > "restore-results/$target-app-start.txt" 2>&1
  docker run --rm --network "$restore_network" -i --entrypoint node "$cms_image" \
    --input-type=module - "$(cat "restore-results/$target-url.txt")" \
    > "restore-results/$target-http.txt" 2>&1 <<'JS'
const url = process.argv[2];
for (let attempt = 0; attempt < 30; attempt++) {
  try {
    const response = await fetch(url, { redirect: 'manual', signal: AbortSignal.timeout(2000) });
    if (response.status >= 200 && response.status < 400) {
      console.log(`PASS HTTP ${response.status}`);
      process.exit(0);
    }
  } catch {}
  await new Promise(resolve => setTimeout(resolve, 1000));
}
process.exit(1);
JS
  docker compose -p "$project" -f "$app_file" logs --no-color > "restore-results/$target-app.log" 2>&1
  docker compose -p "$project" -f "$app_file" down --volumes > /dev/null 2>&1
  rm "$app_file" "restore-results/$target-password.env" "restore-results/$target-url.txt"
  app_file=
  printf '%s PASS %ss\n' "$target" "$((SECONDS-started))" | tee -a restore-results/summary.txt
  docker rm -fv "$restore_container" >/dev/null
  restore_container=
  docker network rm "$restore_network" >/dev/null
  restore_network=
done
rm -rf -- restore-results/configuration
