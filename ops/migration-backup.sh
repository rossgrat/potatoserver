#!/usr/bin/env bash
set -euo pipefail
umask 077
script_dir=$(cd -- "$(dirname -- "$0")" && pwd)
mkdir -p "$script_dir/../state"
exec 9> "$script_dir/../state/operations.lock"
flock -n 9
backup_dir=${1:?Pass a new absolute backup directory on potatoserver}
case "$backup_dir" in /home/rossgrat/backups/*) ;; *) exit 2 ;; esac
if [[ ${2:-} != --resume-volumes ]]; then mkdir "$backup_dir"; fi
backup_dir=$(cd "$backup_dir" && pwd)
paused=
helper_cid=
cleanup() {
  if [[ -n "$helper_cid" && -s "$helper_cid" ]]; then docker rm -f "$(cat "$helper_cid")" >/dev/null 2>&1 || true; fi
  if [[ -n "$paused" ]]; then docker unpause "$paused" >/dev/null; fi
}
trap cleanup EXIT
if [[ ${2:-} != --resume-volumes ]]; then
date -u +%FT%TZ > "$backup_dir/started.txt"
mapfile -t containers < <(docker ps -aq)
docker inspect "${containers[@]}" > "$backup_dir/containers.json"
docker ps -a --format '{{.Names}} {{.Image}} {{.Status}}' > "$backup_dir/runtime.txt"
free -h > "$backup_dir/memory.txt"
df -h / > "$backup_dir/disk.txt"
cp "$script_dir/database-fingerprint.sql" "$backup_dir/"

for container in miniflux-postgres-1 job-board-postgres wubzduh-postgres-1 umami-postgres-1 pages-cms-postgres-1; do
  bash "$script_dir/backup-database.sh" "$container" "$backup_dir/$container"
done

for namespace in miniflux umami pages-cms wubzduh job-board ntfy; do
if [[ $(bash "$script_dir/runtime-for.sh" "$namespace" /home/rossgrat/repos/network/deployments.conf) == k3s ]]; then
  K3S_CONFIG_FILE=/dev/null /usr/local/bin/k3s kubectl --kubeconfig /home/rossgrat/.kube/potatoserver-k3s.yaml \
    get deployments,statefulsets,services,persistentvolumeclaims,networkpolicies,configmaps,secrets -n "$namespace" -o yaml \
    > "$backup_dir/$namespace-resources.yaml"
fi
done
tar -czf "$backup_dir/migration-tools.tar.gz" -C "$(dirname "$script_dir")" \
  --exclude=k3s-assets ops k3s systemd state
tar -czf "$backup_dir/configuration.tar.gz" -C /home/rossgrat \
  --exclude='.git' --exclude='caddy/logs' --exclude='caddy/media' \
  repos/network .config/umami/admin.json services/job-board-v2/docker-compose.yml services/job-board-v2/.env \
  services/wubzduh/docker-compose.yml services/wubzduh/.env services/wubzduh/config.yaml
tar -czf "$backup_dir/media.tar.gz" -C /home/rossgrat/repos/network/caddy/media .
tar -czf "$backup_dir/host-configuration.tar.gz" -C / \
  etc/cloudflared/config.yml etc/systemd/system/cloudflared.service \
  etc/systemd/system/systemd-networkd-wait-online.service.d
fi
test -s "$backup_dir/configuration.tar.gz"
for container in miniflux-postgres-1 job-board-postgres wubzduh-postgres-1 umami-postgres-1 pages-cms-postgres-1; do
  test -s "$backup_dir/$container/database.dump"
  test -s "$backup_dir/$container/source-fingerprint.txt"
done
(
  cd "$backup_dir"
  sha256sum -- configuration.tar.gz containers.json ./*/database.dump ./*/schema.sql ./*/globals.sql \
    ./*/image.txt ./*/connection.txt ./*/source-fingerprint.txt > DATABASE_SHA256SUMS
)
helper_image=$(cat "$backup_dir/miniflux-postgres-1/image.txt")
if [[ $(bash "$script_dir/runtime-for.sh" ntfy /home/rossgrat/repos/network/deployments.conf) == k3s && ! -f "$backup_dir/ntfy-auth.tar.gz" ]]; then
  bash "$script_dir/backup-ntfy.sh" "$backup_dir"
fi
for entry in caddy:/data:caddy-data caddy:/config:caddy-config ntfy:/var/lib/ntfy:ntfy-auth ntfy:/var/cache/ntfy:ntfy-cache lgtm:/data:lgtm-data wubzduh:/var/log/wubzduh:wubzduh-logs; do
  IFS=: read -r container mount name <<< "$entry"
  if [[ -f "$backup_dir/$name.tar.gz" ]]; then gzip -t "$backup_dir/$name.tar.gz"; continue; fi
  if [[ "$container" == wubzduh && $(bash "$script_dir/runtime-for.sh" wubzduh /home/rossgrat/repos/network/deployments.conf) == k3s ]]; then
    K3S_CONFIG_FILE=/dev/null /usr/local/bin/k3s kubectl --kubeconfig /home/rossgrat/.kube/potatoserver-k3s.yaml \
      exec -n wubzduh deployment/wubzduh -- tar -C "$mount" -cf - . > "$backup_dir/$name.tar"
    gzip -1 "$backup_dir/$name.tar"
    printf 'Volume backup: %s (k3s)\n' "$name"
    continue
  fi
  paused=$container
  docker pause "$container" >/dev/null
  touch "$backup_dir/$name.tar"
  helper_cid="$backup_dir/.$name.cid"
  if [[ -f "$helper_cid" ]]; then
    if docker inspect "$(cat "$helper_cid")" >/dev/null 2>&1; then exit 1; fi
    rm "$helper_cid"
  fi
  timeout --kill-after=5 600 docker run --rm --cidfile "$helper_cid" --log-driver none \
    --network none --read-only --volumes-from "$container:ro" -v "$backup_dir:/backup" \
    --entrypoint tar "$helper_image" -C "$mount" -cf "/backup/$name.tar" .
  docker unpause "$container" >/dev/null
  paused=
  rm "$helper_cid"
  helper_cid=
  gzip -1 "$backup_dir/$name.tar"
  printf 'Volume backup: %s\n' "$name"
done
if [[ ${2:-} == --resume-volumes && -f "$backup_dir/custom-images.tar.gz" ]]; then
  gzip -t "$backup_dir/custom-images.tar.gz"
else
  docker save "$(docker inspect --format '{{.Image}}' caddy)" "$(docker inspect --format '{{.Image}}' pages-cms-app-1)" \
    | gzip -1 > "$backup_dir/custom-images.tar.gz"
fi
find "$backup_dir" -type f -exec chmod 600 {} +
cd "$backup_dir"
manifest=$(mktemp)
find . -path ./restore-results -prune -o -type f ! -name SHA256SUMS -print0 | sort -z | xargs -0 sha256sum > "$manifest"
mv "$manifest" SHA256SUMS
date -u +%FT%TZ
printf 'Backup saved to %s\n' "$backup_dir"
