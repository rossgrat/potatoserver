#!/usr/bin/env bash
set -euo pipefail
test "$(id -u)" -eq 0
test "$(hostname)" = potatoserver
curl --fail --silent --max-time 10 http://127.0.0.1:3030/sign-in > /dev/null
config=/etc/cloudflared/config.yml
if grep -q 'hostname: cms.grattafiori.dev' "$config"; then
  printf '%s\n' 'The CMS tunnel route already exists.'
  exit 0
fi
staged=$(mktemp)
trap 'rm -f "$staged"' EXIT
awk '
/^  - service: http_status:404$/ {
  print "  - hostname: cms.grattafiori.dev"
  print "    service: http://127.0.0.1:3030"
}
{ print }
' "$config" > "$staged"
grep -q 'hostname: cms.grattafiori.dev' "$staged"
cloudflared tunnel --config "$staged" ingress validate
backup_dir=/var/backups/pages-cms
install -d -m 700 "$backup_dir"
backup="$backup_dir/cloudflared-$(date -u +%Y%m%dT%H%M%SZ).yml"
cp -p "$config" "$backup"
chmod 600 "$backup"
install -m 644 "$staged" "$config"
if systemctl restart cloudflared; then
  for attempt in {1..15}; do
    if curl --fail --silent --max-time 2 http://127.0.0.1:20241/ready > /dev/null; then
      printf 'CMS route installed. Previous configuration: %s\n' "$backup"
      exit 0
    fi
    sleep 2
  done
fi
cp "$backup" "$config"
systemctl restart cloudflared
printf '%s\n' 'Tunnel readiness failed. The previous configuration was restored.' >&2
exit 1
