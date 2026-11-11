#!/usr/bin/env bash
set -euo pipefail
umask 077
((EUID == 0))
[[ $(hostname) == potatoserver ]]
script_dir=$(cd -- "$(dirname -- "$0")" && pwd)
tools_dir=$(dirname "$script_dir")
exec 9> "$tools_dir/state/operations.lock"
flock -n 9
rehearsal=$(cat "$tools_dir/state/pages-cms-rehearsal")
test -s "$rehearsal/database-result.txt"
test -s "$rehearsal/proxy-result.txt"
assets="$tools_dir/images/pages-cms"
image=$(cat "$assets/image-name")
expected=$(cat "$assets/image-id")
printf 'Verifying the CMS image archive\n'
[[ "$expected" == $(docker image inspect --format '{{.Id}}' "$image") ]]
(cd "$assets" && sha256sum --check --quiet SHA256SUMS)
imported=
if [[ -f "$tools_dir/state/pages-cms-imported-image-id" ]]; then imported=$(cat "$tools_dir/state/pages-cms-imported-image-id"); fi
if [[ "$imported" == "$expected" ]] && /usr/local/bin/k3s ctr -n k8s.io images list -q | grep -Fx "$image" > /dev/null; then
  printf 'The CMS image is already imported\n'
else
  printf 'Importing the CMS image into K3s\n'
  /usr/local/bin/k3s ctr -n k8s.io images import "$assets/pages-cms.tar"
fi
/usr/local/bin/k3s ctr -n k8s.io images list -q | grep -Fx "$image"
kubectl=(/usr/local/bin/k3s kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml)
job=
staged=$(mktemp)
cleanup() {
  rm -f "$staged"
  if [[ -n "$job" ]]; then "${kubectl[@]}" delete job "$job" -n pages-cms --wait=true --timeout=60s >/dev/null || true; fi
}
trap cleanup EXIT
printf 'Testing the imported image\n'
job=$("${kubectl[@]}" create -f "$tools_dir/k3s/pages-cms-image-check.yaml" -o jsonpath='{.metadata.name}')
"${kubectl[@]}" wait --for=condition=Complete job/"$job" -n pages-cms --timeout=90s
[[ $("${kubectl[@]}" logs job/"$job" -n pages-cms) == v24.22.2 ]]
printf '%s\n' "$expected" > "$tools_dir/state/pages-cms-imported-image-id"
chown rossgrat:rossgrat "$tools_dir/state/pages-cms-imported-image-id"
curl --fail --silent --max-time 10 -H 'Host: cms.grattafiori.dev' http://127.0.0.1/sign-in > /dev/null
config=/etc/cloudflared/config.yml
origin=$(awk '/^  - hostname: cms[.]grattafiori[.]dev$/ {getline; print $2}' "$config")
evidence=/home/rossgrat/backups/k3s-cms-preparation-$(date -u +%Y%m%dT%H%M%SZ)
install -d -m 700 -o rossgrat -g rossgrat "$evidence"
case "$origin" in
  http://127.0.0.1:3030)
    printf 'Preparing the CMS tunnel route through Caddy\n'
    awk -f "$script_dir/cms-tunnel-route.awk" "$config" > "$staged"
    cloudflared tunnel --config "$staged" ingress validate > "$evidence/ingress-validation.txt" 2>&1
    cp "$config" "$evidence/cloudflared.before.yml"
    install -m 644 "$staged" "$config"
    ready=false
    tunnel_started=$(date -u '+%Y-%m-%d %H:%M:%S UTC')
    printf 'Restarting the tunnel and waiting for readiness\n'
    if systemctl restart cloudflared; then
      for attempt in {1..15}; do
        result=0
        status=$(curl --silent --show-error --max-time 2 -o /dev/null -w '%{http_code}' http://127.0.0.1:20241/ready 2> "$evidence/tunnel-ready-$attempt.err") || result=$?
        printf 'Tunnel readiness probe %s/15: curl=%s HTTP=%s\n' "$attempt" "$result" "$status" | tee -a "$evidence/tunnel-readiness.txt"
        if ((result == 0)) && [[ "$status" == 200 ]]; then ready=true; break; fi
        if ((attempt < 15)); then sleep 2; fi
      done
    fi
    if ! "$ready" || ! bash "$script_dir/verify-cms-public.sh" https://cms.grattafiori.dev/sign-in "$evidence/public-probes"; then
      systemctl show cloudflared -p Result -p ActiveState -p SubState > "$evidence/tunnel-state.txt"
      journalctl -u cloudflared --since "$tunnel_started" --no-pager > "$evidence/tunnel.log" 2>&1 || true
      cp "$evidence/cloudflared.before.yml" "$config"
      systemctl restart cloudflared
      chown -R rossgrat:rossgrat "$evidence"
      printf 'CMS proxy preparation failed. The original tunnel configuration was restored.\n' >&2
      exit 1
    fi
    ;;
  http://127.0.0.1:80) ;;
  *) printf 'Unexpected CMS tunnel origin. No routing changes made.\n' >&2; exit 1 ;;
esac
printf 'Saving routing configuration and protected host state\n'
cp /home/rossgrat/repos/network/caddy/Caddyfile "$evidence/Caddyfile"
cp /home/rossgrat/repos/network/pages-cms/docker-compose.yml "$evidence/cms-compose.yml"
tar -czf "$evidence/migration-tools.tar.gz" -C "$tools_dir" ops k3s systemd state
bash "$script_dir/backup-host-secrets.sh" "$evidence"
printf 'Backing up cluster state\n'
systemctl start potatoserver-k3s-backup.service
cluster_backup=$(find /home/rossgrat/backups -maxdepth 1 -name 'k3s-state-*' -type d | sort | tail -1)
printf 'Testing isolated cluster recovery\n'
runuser -u rossgrat -- bash "$script_dir/test-cluster-restore.sh" "$cluster_backup"
chown -R rossgrat:rossgrat "$evidence"
printf 'CMS image and proxy preparation PASS. The application still runs on Docker.\n'
