#!/usr/bin/env bash
set -euo pipefail
umask 077
script_dir=$(cd -- "$(dirname -- "$0")" && pwd)
target=${1:?Pass the existing backup directory}
export K3S_CONFIG_FILE=/dev/null
kubectl=(/usr/local/bin/k3s kubectl --kubeconfig /home/rossgrat/.kube/potatoserver-k3s.yaml)
"${kubectl[@]}" apply -f "$script_dir/ntfy-backup.yaml"
trap '"${kubectl[@]}" delete pod/state-backup -n ntfy --ignore-not-found --wait=true >/dev/null' EXIT
"${kubectl[@]}" wait --for=condition=Ready pod/state-backup -n ntfy --timeout=120s
"${kubectl[@]}" exec -i -n ntfy state-backup -- node --input-type=module <<'JS'
import fs from 'node:fs';
import { DatabaseSync, backup } from 'node:sqlite';
fs.mkdirSync('/tmp/auth', { mode: 0o700 });
const source = new DatabaseSync('/auth/auth.db', { readOnly: true });
await backup(source, '/tmp/auth/auth.db');
source.close();
const restored = new DatabaseSync('/tmp/auth/auth.db', { readOnly: true });
if (restored.prepare('PRAGMA integrity_check').get().integrity_check !== 'ok') throw new Error('ntfy backup integrity failed');
restored.close();
console.log('Consistent ntfy SQLite backup PASS');
JS
"${kubectl[@]}" exec -n ntfy state-backup -- tar -C /tmp/auth -cf - . > "$target/ntfy-auth.tar"
"${kubectl[@]}" exec -n ntfy state-backup -- tar -C /cache -cf - . > "$target/ntfy-cache.tar"
gzip -1 "$target/ntfy-auth.tar" "$target/ntfy-cache.tar"
