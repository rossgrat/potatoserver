#!/usr/bin/env bash
set -euo pipefail
umask 077
script_dir=$(cd -- "$(dirname -- "$0")" && pwd)
tools_dir=$(dirname "$script_dir")
evidence=$(cat "$tools_dir/state/ntfy-rehearsal")
export K3S_CONFIG_FILE=/dev/null
kubectl=(/usr/local/bin/k3s kubectl --kubeconfig /home/rossgrat/.kube/potatoserver-k3s.yaml)
"${kubectl[@]}" apply -f "$tools_dir/k3s/ntfy.yaml"
bash "$script_dir/restore-ntfy-state.sh" "$evidence"
"${kubectl[@]}" scale deployment/ntfy -n ntfy --replicas=1
"${kubectl[@]}" rollout status deployment/ntfy -n ntfy --timeout=120s
node -e 'require("fs").writeFileSync(process.argv[1],require("crypto").randomBytes(24).toString("hex")+"\n",{mode:0o600})' "$evidence/test-password"
"${kubectl[@]}" exec -i -n ntfy deployment/ntfy -- sh -ec \
  'read -r NTFY_PASSWORD; export NTFY_PASSWORD; ntfy user add --role=admin k3s-recovery-test' \
  < "$evidence/test-password" > "$evidence/test-identity.txt" 2>&1
image=$(cat "$tools_dir/k3s/backup-image")
docker run --rm --network caddy-network --read-only -i --user "$(id -u):$(id -g)" -v "$evidence:/evidence:ro" \
  --entrypoint node "$image" --input-type=module - http://172.18.0.1:30086 isolated < "$script_dir/test-ntfy-http.mjs"
"${kubectl[@]}" delete pod -n ntfy -l app=ntfy --wait=true
"${kubectl[@]}" rollout status deployment/ntfy -n ntfy --timeout=120s
docker run --rm --network caddy-network --read-only -i --user "$(id -u):$(id -g)" -v "$evidence:/evidence:ro" \
  --entrypoint node "$image" --input-type=module - http://172.18.0.1:30086 < "$script_dir/test-ntfy-http.mjs"
"${kubectl[@]}" scale deployment/ntfy -n ntfy --replicas=0
"${kubectl[@]}" wait --for=delete pod -n ntfy -l app=ntfy --timeout=60s
printf 'ntfy isolated restoration, authentication, publication, subscription, and pod replacement PASS\n' | tee "$evidence/result.txt"
