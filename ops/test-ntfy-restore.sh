#!/usr/bin/env bash
set -euo pipefail
umask 077
script_dir=$(cd -- "$(dirname -- "$0")" && pwd)
backup=${1:?Pass a completed ntfy backup directory}
target="$backup/restore-results/ntfy"
mkdir -p "$target/auth" "$target/cache"
tar -xzf "$backup/ntfy-auth.tar.gz" -C "$target/auth" --no-same-owner
tar -xzf "$backup/ntfy-cache.tar.gz" -C "$target/cache" --no-same-owner
image=$(cat "$script_dir/../k3s/backup-image")
docker run --rm --network none --read-only -i --user "$(id -u):$(id -g)" -v "$target:/evidence" \
  --entrypoint node "$image" --input-type=module <<'JS'
import fs from 'node:fs';
import { DatabaseSync } from 'node:sqlite';
const database = new DatabaseSync('/evidence/auth/auth.db', { readOnly: true });
if (database.prepare('PRAGMA integrity_check').get().integrity_check !== 'ok') throw new Error('ntfy recovery integrity failed');
if (database.prepare('PRAGMA foreign_key_check').all().length) throw new Error('ntfy recovery foreign key check failed');
const token = database.prepare('SELECT token FROM user_token WHERE expires = 0 OR expires > unixepoch() ORDER BY expires DESC LIMIT 1').get()?.token;
if (!token || !/^tk_[A-Za-z0-9]+$/.test(token)) throw new Error('No saved token in the ntfy backup');
fs.writeFileSync('/evidence/token', token + '\n', { mode: 0o600 });
JS
container=
cleanup() {
  if [[ -n "$container" ]]; then
    docker logs "$container" > "$target/startup.log" 2>&1 || true
    docker rm -fv "$container" >/dev/null
  fi
  rm -f "$target/token"
}
trap cleanup EXIT
container=$(docker run -d --network none --read-only --memory 256m --user "$(id -u):$(id -g)" \
  --tmpfs /tmp:rw,noexec,nosuid,size=16m \
  -v "$target/auth:/var/lib/ntfy" -v "$target/cache:/var/cache/ntfy" \
  -v /home/rossgrat/repos/network/ntfy/server.yml:/etc/ntfy/server.yml:ro \
  -e NTFY_AUTH_FILE=/var/lib/ntfy/auth.db -e NTFY_AUTH_DEFAULT_ACCESS=deny-all -e NTFY_LISTEN_HTTP=:8080 \
  binwiederhier/ntfy:v2.34.0@sha256:901e14503d3f605f445be0e68f2ac71f0aa73391897ce6ceb599f8c48d8b3792 serve)
ready=false
for _ in {1..30}; do
  if docker exec "$container" wget -q --spider http://127.0.0.1:8080/v1/health > "$target/readiness.txt" 2>&1; then ready=true; break; fi
  sleep 1
done
"$ready"
docker exec -i "$container" sh -ec \
  'read -r token; wget -qO /dev/null --header "Authorization: Bearer $token" "http://127.0.0.1:8080/k3s-isolated-recovery-test/json?poll=1"' \
  < "$target/token"
if docker exec "$container" wget -qO /dev/null 'http://127.0.0.1:8080/k3s-isolated-recovery-test/json?poll=1' > "$target/anonymous.txt" 2>&1; then exit 1; fi
grep -Eq '40[13]' "$target/anonymous.txt"
printf 'ntfy online backup, isolated startup, saved token, and anonymous rejection PASS\n' | tee "$target/result.txt"
