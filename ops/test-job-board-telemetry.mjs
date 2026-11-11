import fs from 'node:fs';

const pods = JSON.parse(fs.readFileSync('/evidence/pods.json')).items.filter(pod => pod.metadata.labels.app === 'job-board');
for (const pod of pods) {
  const service = `job-board-${pod.metadata.labels.role}`;
  const start = String(BigInt(Date.parse(pod.metadata.creationTimestamp)) * 1000000n);
  const url = new URL('http://lgtm:3100/loki/api/v1/query_range');
  url.searchParams.set('query', `{service_name="${service}"}`);
  url.searchParams.set('start', start);
  url.searchParams.set('limit', '100');
  const response = await fetch(url, { signal: AbortSignal.timeout(10000) });
  if (!response.ok) throw new Error('Loki query failed');
  const data = await response.json();
  fs.writeFileSync(`/evidence/${service}-loki.json`, JSON.stringify(data), { mode: 0o600 });
  const count = data.data.result.reduce((count, stream) => count + stream.values.length, 0);
  if (!count) throw new Error(`${service} has no logs after pod creation`);
  console.log(`${service} logs after K3s startup PASS (${count})`);
}
const url = new URL('http://lgtm:9090/api/v1/query');
url.searchParams.set('query', 'count(fetcher_jobs_fetched_total)');
const response = await fetch(url, { signal: AbortSignal.timeout(10000) });
if (!response.ok) throw new Error('Metrics query failed');
const data = await response.json();
fs.writeFileSync('/evidence/worker-metrics.json', JSON.stringify(data), { mode: 0o600 });
if (!data.data.result.length || Number(data.data.result[0].value[1]) < 1) throw new Error('No fetcher metrics');
console.log('Job Board fetcher metrics query PASS');
