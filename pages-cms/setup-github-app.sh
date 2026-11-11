#!/usr/bin/env bash
set -euo pipefail
umask 077
script_dir=$(cd -- "$(dirname -- "$0")" && pwd)
setup_dir=$(mktemp -d)
trap 'rm -rf "$setup_dir"' EXIT
helper="$setup_dir/setup.mjs"
curl -fsSL https://raw.githubusercontent.com/hunvreus/pagescms/6f4e860a35d934406580287e7042e5e111e207a1/scripts/setup-github-app.mjs -o "$helper"
printf '%s  %s\n' f67679d8dea2e3e02533e423ceed7b750c309e3d1ec0097d76739b9ac744b5f5 "$helper" | shasum -a 256 -c -
node --input-type=module - "$helper" <<'JS'
import fs from 'node:fs';
const path = process.argv[2];
let source = fs.readFileSync(path, 'utf8');
for (const [before, after] of [
  ['  const webhookSecret = randomBytes(32).toString("base64url");\n', ''],
  ['      secret: webhookSecret,\n', ''],
  ['email_addresses: "read",', 'emails: "read",'],
  ['GITHUB_APP_WEBHOOK_SECRET: webhookSecret,', 'GITHUB_APP_WEBHOOK_SECRET: converted.webhook_secret,'],
]) {
  if (!source.includes(before)) throw new Error('Unexpected upstream helper source');
  source = source.replace(before, after);
}
fs.writeFileSync(path, source);
JS
node "$helper" --base-url https://cms.grattafiori.dev --app-name 'Ross Blog CMS' --env "$script_dir/.env" --no-open
