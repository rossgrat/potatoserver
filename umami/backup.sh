#!/usr/bin/env bash
set -euo pipefail
umask 077
script_dir=$(cd -- "$(dirname -- "$0")" && pwd)
backup_dir=${1:?Pass an absolute backup directory outside the repository}
case "$backup_dir" in /*) ;; *) exit 2 ;; esac
mkdir -p "$backup_dir"
cd "$script_dir"
docker compose exec -T postgres pg_dump -U umami -d umami -Fc > "$backup_dir/database.dump"
test -s "$backup_dir/database.dump"
cp .env "$backup_dir/app.env"
printf 'Backup saved to %s\n' "$backup_dir"
