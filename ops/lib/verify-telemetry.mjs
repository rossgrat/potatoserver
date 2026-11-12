import fs from 'node:fs';

const [evidence, collector] = process.argv.slice(2);
if (!evidence || !collector) throw Error('Pass an evidence directory and collector IP');
const pods = JSON.parse(fs.readFileSync(`${evidence}/pods.json`)).items.filter(pod => pod.metadata.labels.app === 'job-board');
for (const pod of pods) {
  const service = `job-board-${pod.metadata.labels.role}`;
  const started = pod.status.containerStatuses[0]?.state.running?.startedAt;
  if (!started) throw new Error(`${service} is not running`);
  const windowStart = Math.max(Date.parse(started), Date.now() - 2 * 60 * 60 * 1000);
  const start = String(BigInt(windowStart) * 1000000n);
  const url = new URL(`http://${collector}:3100/loki/api/v1/query_range`);
  url.searchParams.set('query', `{service_name="${service}"}`);
  url.searchParams.set('start', start);
  url.searchParams.set('limit', '100');
  const response = await fetch(url, { signal: AbortSignal.timeout(10000) });
  if (!response.ok) throw new Error('Loki query failed');
  const data = await response.json();
  fs.writeFileSync(`${evidence}/${service}-loki.json`, JSON.stringify(data), { mode: 0o600 });
  const count = data.data.result.reduce((count, stream) => count + stream.values.length, 0);
  if (!count) throw new Error(`${service} has no logs since ${new Date(windowStart).toISOString()}`);
  console.log(`${service} logs after K3s startup PASS (${count})`);
}
const url = new URL(`http://${collector}:9090/api/v1/query`);
url.searchParams.set('query', 'count(fetcher_jobs_fetched_total)');
const response = await fetch(url, { signal: AbortSignal.timeout(10000) });
if (!response.ok) throw new Error('Metrics query failed');
const data = await response.json();
fs.writeFileSync(`${evidence}/worker-metrics.json`, JSON.stringify(data), { mode: 0o600 });
if (!data.data.result.length || Number(data.data.result[0].value[1]) < 1) throw new Error('No fetcher metrics');
console.log('Job Board fetcher metrics query PASS');
