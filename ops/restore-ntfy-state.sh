#!/usr/bin/env bash
set -euo pipefail
umask 077
script_dir=$(cd -- "$(dirname -- "$0")" && pwd)
tools_dir=$(dirname "$script_dir")
evidence=${1:?Pass the ntfy snapshot directory}
export K3S_CONFIG_FILE=/dev/null
kubectl=(/usr/local/bin/k3s kubectl --kubeconfig /home/rossgrat/.kube/potatoserver-k3s.yaml)
[[ $("${kubectl[@]}" get deployment/ntfy -n ntfy -o jsonpath='{.spec.replicas}') == 0 ]]
[[ -z $("${kubectl[@]}" get pods -n ntfy -l app=ntfy -o name) ]]
"${kubectl[@]}" apply -f "$tools_dir/k3s/ntfy-state-transfer.yaml"
trap '"${kubectl[@]}" delete pod/state-transfer -n ntfy --ignore-not-found --wait=true >/dev/null' EXIT
"${kubectl[@]}" wait --for=condition=Ready pod/state-transfer -n ntfy --timeout=120s
for name in auth cache; do
  "${kubectl[@]}" exec -n ntfy state-transfer -- sh -ec 'find "$1" -mindepth 1 -maxdepth 1 -exec rm -rf {} +' sh "/$name"
  "${kubectl[@]}" exec -i -n ntfy state-transfer -- tar -C "/$name" -xf - < "$evidence/$name.tar"
  "${kubectl[@]}" exec -n ntfy state-transfer -- tar -C "/$name" -cf - . > "$evidence/restored-$name.tar"
  mkdir "$evidence/source-$name" "$evidence/restored-$name"
  tar -xf "$evidence/$name.tar" -C "$evidence/source-$name" --no-same-owner
  tar -xf "$evidence/restored-$name.tar" -C "$evidence/restored-$name" --no-same-owner
  for side in source restored; do
    (cd "$evidence/$side-$name" && find . -type f -print0 | sort -z | xargs -0 -r sha256sum) > "$evidence/$side-$name.sha256"
  done
  diff -u "$evidence/source-$name.sha256" "$evidence/restored-$name.sha256" > "$evidence/$name.diff"
done
image=$(cat "$tools_dir/k3s/backup-image")
docker run --rm --network none --read-only -i --user "$(id -u):$(id -g)" -v "$evidence:/evidence" \
  --entrypoint node "$image" --input-type=module <<'JS'
import fs from 'node:fs';
import { DatabaseSync } from 'node:sqlite';
const database = new DatabaseSync('/evidence/restored-auth/auth.db', { readOnly: true });
if (database.prepare('PRAGMA integrity_check').get().integrity_check !== 'ok') throw new Error('ntfy SQLite integrity failed');
if (database.prepare('PRAGMA foreign_key_check').all().length) throw new Error('ntfy foreign key integrity failed');
const token = database.prepare('SELECT token FROM user_token WHERE expires = 0 OR expires > unixepoch() ORDER BY expires DESC LIMIT 1').get()?.token;
if (!token || !/^tk_[A-Za-z0-9]+$/.test(token)) throw new Error('No saved ntfy bearer token');
fs.writeFileSync('/evidence/http-auth.json', JSON.stringify({ token }), { mode: 0o600 });
console.log('ntfy restored files, SQLite integrity, and saved token PASS');
JS
