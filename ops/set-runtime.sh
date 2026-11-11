#!/usr/bin/env bash
set -euo pipefail
service=${1:?Pass a service name}
runtime=${2:?Pass docker or k3s}
config=${3:?Pass the deployment configuration path}
script_dir=$(cd -- "$(dirname -- "$0")" && pwd)
bash "$script_dir/runtime-for.sh" "$service" "$config" > /dev/null
case "$runtime" in docker|k3s) ;; *) exit 1 ;; esac
staged=$(mktemp "$(dirname "$config")/.deployments.XXXXXXXX")
trap 'rm -f "$staged"' EXIT
key=$(printf '%s_RUNTIME' "$service" | tr 'a-z-' 'A-Z_')
awk -F= -v OFS='=' -v key="$key" -v runtime="$runtime" '$1 == key {$2 = runtime} {print}' "$config" > "$staged"
chmod --reference="$config" "$staged"
mv "$staged" "$config"
