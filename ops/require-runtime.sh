#!/usr/bin/env bash
set -euo pipefail

service=${1:?Pass the service name}
expected=${2:?Pass the required runtime}
case "$service" in
  miniflux | umami | pages-cms | wubzduh | job-board | ntfy | lgtm | caddy) ;;
  *) exit 2 ;;
esac
if [[ "$expected" != k3s ]]; then
  printf '%s runs on K3s. Update its pinned manifest in /home/rossgrat/repos/network/k3s, then run make k3s-apply there.\n' "$service" >&2
  exit 1
fi
