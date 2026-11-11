#!/usr/bin/env bash
set -euo pipefail
umask 077
url=${1:?Pass the CMS sign-in URL}
evidence=${2:?Pass a new directory for probe results}
mkdir "$evidence"
for attempt in {1..10}; do
  result=0
  status=$(curl --silent --show-error --max-time 5 -o /dev/null -w '%{http_code}' "$url" 2> "$evidence/attempt-$attempt.err") || result=$?
  printf 'CMS public probe %s/10: curl=%s HTTP=%s\n' "$attempt" "$result" "$status" | tee -a "$evidence/results.txt"
  if ((result == 0)) && [[ "$status" == 200 ]]; then exit 0; fi
  if ((attempt < 10)); then sleep 2; fi
done
printf 'CMS public endpoint did not become ready. Probe results: %s\n' "$evidence" >&2
exit 1
