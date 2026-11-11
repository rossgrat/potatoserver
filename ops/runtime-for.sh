#!/usr/bin/env bash
set -euo pipefail
service=${1:?Pass a service name}
config=${2:?Pass the deployment configuration path}
key=$(printf '%s_RUNTIME' "$service" | tr 'a-z-' 'A-Z_')
runtime=$(awk -F= -v key="$key" '$1 == key {print $2}' "$config")
case "$runtime" in
  docker|k3s) printf '%s\n' "$runtime" ;;
  *) printf 'Invalid deployment runtime for %s\n' "$service" >&2; exit 1 ;;
esac
