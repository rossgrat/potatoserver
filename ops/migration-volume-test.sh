#!/usr/bin/env bash
set -euo pipefail
umask 077
backup_dir=${1:?Pass the completed baseline backup directory}
cd "$backup_dir"
mkdir -p restore-results/volumes
for name in caddy-data caddy-config ntfy-auth ntfy-cache lgtm-data wubzduh-logs; do
  gzip -t "$name.tar.gz"
  mkdir "restore-results/volumes/$name"
  tar -xzf "$name.tar.gz" -C "restore-results/volumes/$name" --no-same-owner --same-permissions
done
tar -tzf media.tar.gz > restore-results/media-files.txt
mkdir -p restore-results/volumes/caddy-logs restore-results/volumes/media
tar -xzf media.tar.gz -C restore-results/volumes/media --no-same-owner
docker run --rm --network none --read-only --user 1000:1000 \
  --env-file "$PWD/restore-results/configuration/repos/network/caddy/.env" \
  -v "$PWD/restore-results/configuration/repos/network/caddy/Caddyfile:/etc/caddy/Caddyfile:ro" \
  -v "$PWD/restore-results/volumes/caddy-data:/data" \
  -v "$PWD/restore-results/volumes/caddy-config:/config" \
  -v "$PWD/restore-results/volumes/caddy-logs:/var/log/caddy" \
  -v "$PWD/restore-results/volumes/media:/srv/media:ro" \
  --entrypoint caddy "$(docker inspect --format '{{.Image}}' caddy)" validate --config /etc/caddy/Caddyfile --adapter caddyfile \
  > restore-results/caddy-validation.txt 2>&1
docker load -i custom-images.tar.gz > restore-results/custom-image-load.txt
cms_image=$(docker inspect --format '{{.Image}}' pages-cms-app-1)
docker run --rm --network none -i -v "$PWD/restore-results/volumes:/volumes" \
  --entrypoint node "$cms_image" --input-type=module > restore-results/sqlite-integrity.txt <<'JS'
import { DatabaseSync } from 'node:sqlite';
import fs from 'node:fs';
for (const file of ['/volumes/ntfy-auth/auth.db', '/volumes/lgtm-data/grafana/data/grafana.db']) {
  if (!fs.existsSync(file)) throw new Error(`Missing restored database: ${file}`);
  const database = new DatabaseSync(file, { readOnly: true });
  const result = database.prepare('PRAGMA integrity_check').all();
  if (result.length !== 1 || result[0].integrity_check !== 'ok') process.exit(1);
  if (database.prepare('PRAGMA foreign_key_check').all().length !== 0) process.exit(1);
  database.close();
  console.log(`${file} PASS`);
}
JS
test_container=
test_network=
cleanup() {
  if [[ -n "$test_container" ]]; then
    docker logs "$test_container" > restore-results/volume-startup.log 2>&1 || true
    docker rm -fv "$test_container" >/dev/null
  fi
  if [[ -n "$test_network" ]]; then docker network rm "$test_network" >/dev/null; fi
}
trap cleanup EXIT
wait_for_service() {
  for _ in {1..60}; do
    [[ $(docker inspect --format '{{.State.Running}}' "$1") == true ]] || return 1
    if docker exec "$@" 2>/dev/null; then return 0; fi
    sleep 1
  done
  return 1
}
test_container=$(docker run -d --label potatoserver.task=k3s-volume-restore --network none --memory 256m \
  -v "$PWD/restore-results/volumes/ntfy-auth:/var/lib/ntfy" \
  -v "$PWD/restore-results/volumes/ntfy-cache:/var/cache/ntfy" \
  -v "$PWD/restore-results/configuration/repos/network/ntfy/server.yml:/etc/ntfy/server.yml:ro" \
  -e NTFY_AUTH_FILE=/var/lib/ntfy/auth.db -e NTFY_AUTH_DEFAULT_ACCESS=deny-all \
  "$(docker inspect --format '{{.Image}}' ntfy)" serve)
wait_for_service "$test_container" wget -q --spider http://127.0.0.1:80/v1/health
printf 'Restored ntfy health PASS\n' > restore-results/ntfy-restored-health.txt
docker rm -fv "$test_container" >/dev/null
test_network=$(docker network create --internal --label potatoserver.task=k3s-volume-restore "k3s-monitoring-recovery-$$")
test_container=$(docker run -d --label potatoserver.task=k3s-volume-restore --network "$test_network" --memory 1g --cpus 1 \
  -e ENABLE_LOGS_PYROSCOPE=true \
  -v "$PWD/restore-results/volumes/lgtm-data:/data" \
  "$(docker inspect --format '{{.Image}}' lgtm)")
wait_for_service "$test_container" /otel-lgtm/docker/healthcheck.sh > /dev/null
docker exec "$test_container" curl -fsS http://127.0.0.1:3000/api/health \
  > restore-results/grafana-restored-health.json
docker logs "$test_container" > restore-results/lgtm-internal-network.log 2>&1
docker rm -fv "$test_container" >/dev/null
test_container=
docker network rm "$test_network" >/dev/null
test_network=
printf 'Persistent volume and image restoration PASS\n' | tee restore-results/volumes-summary.txt
