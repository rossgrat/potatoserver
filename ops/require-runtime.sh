#!/usr/bin/env bash
set -euo pipefail
script_dir=$(cd -- "$(dirname -- "$0")" && pwd)
service=${1:?Pass the service name}
expected=${2:?Pass the required runtime}
actual=$(bash "$script_dir/runtime-for.sh" "$service" "$(dirname "$script_dir")/deployments.conf")
if [[ "$actual" != "$expected" ]]; then
  printf '%s runs on %s. Update its pinned manifest in /home/rossgrat/repos/network/k3s, then run make k3s-apply there.\n' "$service" "$actual" >&2
  exit 1
fi
