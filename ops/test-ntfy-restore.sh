#!/usr/bin/env bash
set -euo pipefail
umask 077
script_dir=$(cd -- "$(dirname -- "$0")" && pwd)
backup=${1:?Pass a completed ntfy backup directory}
target="$backup/restore-results/ntfy"
mkdir -p "$target"
export K3S_CONFIG_FILE=/dev/null
K=(/usr/local/bin/k3s kubectl --kubeconfig /home/rossgrat/.kube/potatoserver-k3s.yaml)
namespace=potato-ntfy-recovery-$(date +%s)
cleanup() {
  "${K[@]}" logs -n "$namespace" recovery -c ntfy > "$target/startup.log" 2>&1 || true
  "${K[@]}" delete namespace "$namespace" --ignore-not-found --wait=true --timeout=90s >/dev/null
}
trap cleanup EXIT
/usr/local/libexec/potatoserver-runtime/node-24.22.2 "$script_dir/ntfy-recovery-resources.mjs" "$backup" "$namespace" > "$target/resources.json"
"${K[@]}" apply -f "$target/resources.json" > "$target/apply.txt"
"${K[@]}" wait --for=jsonpath='{.status.phase}'=Running pod/recovery -n "$namespace" --timeout=120s
for name in auth cache; do
  gzip -dc "$backup/ntfy-$name.tar.gz" | "${K[@]}" exec -i -n "$namespace" recovery -c client -- tar --no-same-owner --strip-components=1 -C "/$name" -xf -
done
"${K[@]}" exec -n "$namespace" recovery -c client -- touch /tmp/start-ntfy
"${K[@]}" wait --for=condition=Ready pod/recovery -n "$namespace" --timeout=90s
"${K[@]}" exec -i -n "$namespace" recovery -c client -- node --input-type=module <<'JS'
import { DatabaseSync } from 'node:sqlite';
const database = new DatabaseSync('/auth/auth.db', { readOnly: true });
if (database.prepare('PRAGMA integrity_check').get().integrity_check !== 'ok') throw Error('ntfy SQLite integrity failed');
if (database.prepare('PRAGMA foreign_key_check').all().length) throw Error('ntfy foreign key check failed');
const token = database.prepare('SELECT token FROM user_token WHERE expires = 0 OR expires > unixepoch() ORDER BY expires DESC LIMIT 1').get()?.token;
if (!token || !/^tk_[A-Za-z0-9]+$/.test(token)) throw Error('No saved bearer token');
database.close();
const request = (suffix, headers = {}) => fetch('http://127.0.0.1:8080' + suffix, { headers, signal: AbortSignal.timeout(10000) });
if ((await request('/v1/health')).status !== 200) throw Error('ntfy health failed');
const topic = '/k3s-isolated-recovery-test/json?poll=1';
if ((await request(topic, { Authorization: 'Bearer ' + token })).status !== 200) throw Error('Saved bearer token rejected');
for (const headers of [{}, { Authorization: 'Bearer tk_deliberatelyincorrect' }]) {
  if (![401, 403].includes((await request(topic, headers)).status)) throw Error('Unauthenticated request accepted');
}
console.log('K3s-native ntfy restore, SQLite integrity, saved token, and unauthorized rejection PASS');
JS
printf 'K3s-native isolated ntfy recovery PASS\n' > "$target/result.txt"
