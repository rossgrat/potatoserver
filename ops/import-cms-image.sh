#!/usr/bin/env bash
set -euo pipefail
umask 077
((EUID == 0))
script_dir=$(cd -- "$(dirname -- "$0")" && pwd)
archive=$(realpath -e "${1:?Pass a server-local CMS image archive built for Linux amd64}")
test -f "$archive"
state_dir=/home/rossgrat/.local/state/potatoserver
exec 9> "$state_dir/operations.lock"
flock -n 9
export K3S_CONFIG_FILE=/dev/null
K=(/usr/local/bin/k3s kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml)
image=$("${K[@]}" create --dry-run=client -f "$script_dir/../k3s/pages-cms.yaml" -o jsonpath='{.spec.template.spec.containers[?(@.name=="pages-cms")].image}')
[[ "$image" == docker.io/library/potatoserver-pages-cms:* && "$image" != *:latest ]]
expected=$(/usr/local/libexec/potatoserver-runtime/node-24.22.2 "$script_dir/lib/image-archive.mjs" "$archive" "$image")
if [[ -f "$state_dir/pages-cms-imported-image-ref" && $(cat "$state_dir/pages-cms-imported-image-ref") == "$image" && $(cat "$state_dir/pages-cms-imported-image-id") != "$expected" ]]; then
  printf 'Advance the CMS image tag in the Makefile and manifest before importing changed contents.\n' >&2
  exit 1
fi
target=/home/rossgrat/backups/k3s-cms-image-$(date -u +%Y%m%dT%H%M%SZ)
install -d -m 700 -o rossgrat -g rossgrat "$target"
cp --reflink=auto "$archive" "$target/image.tar"
(cd "$target" && sha256sum image.tar > SHA256SUMS)
/usr/local/bin/k3s ctr -n k8s.io images import "$target/image.tar"
mapfile -t recovery_images < <({
  printf '%s\n' "$image"
  "${K[@]}" get deployment/pages-cms -n pages-cms -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
  "${K[@]}" get deployment/caddy -n caddy -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
} | sort -u)
/usr/local/bin/k3s ctr -n k8s.io images export "$state_dir/custom-images.tar.new" "${recovery_images[@]}"
chmod 600 "$state_dir/custom-images.tar.new"
chown rossgrat:rossgrat "$state_dir/custom-images.tar.new"
mv "$state_dir/custom-images.tar.new" "$state_dir/custom-images.tar"
printf '%s\n' "$expected" > "$state_dir/pages-cms-imported-image-id"
printf '%s\n' "$image" > "$state_dir/pages-cms-imported-image-ref"
chown rossgrat:rossgrat "$state_dir/pages-cms-imported-image-id" "$state_dir/pages-cms-imported-image-ref"
chown -R rossgrat:rossgrat "$target"
printf 'Pinned CMS image imported. Recovery archive: %s\n' "$target"
