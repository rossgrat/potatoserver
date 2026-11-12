import fs from 'node:fs';
const [backup, namespace] = process.argv.slice(2);
const source = JSON.parse(fs.readFileSync(`${backup}/ntfy-resources.json`)).items;
const spec = structuredClone(source.find(item => item.kind === 'Deployment' && item.metadata.name === 'ntfy').spec.template.spec);
for (const volume of spec.volumes) {
  if (volume.persistentVolumeClaim) { delete volume.persistentVolumeClaim; volume.emptyDir = {}; }
}
const application = spec.containers[0];
application.command = ['sh', '-ec'];
application.args = ['while [ ! -f /tmp/start-ntfy ]; do sleep 1; done; exec ntfy serve'];
delete application.livenessProbe;
spec.restartPolicy = 'Never';
spec.terminationGracePeriodSeconds = 1;
spec.containers.push({
  name: 'client', image: fs.readFileSync(new URL('../k3s/backup-image', import.meta.url), 'utf8').trim(),
  command: ['node', '-e', 'setInterval(() => {}, 1000)'],
  securityContext: { allowPrivilegeEscalation: false, readOnlyRootFilesystem: true, capabilities: { drop: ['ALL'] } },
  resources: { requests: { cpu: '10m', memory: '32Mi' }, limits: { cpu: '100m', memory: '128Mi' } },
  volumeMounts: [{ name: 'auth', mountPath: '/auth' }, { name: 'cache', mountPath: '/cache' }, { name: 'temporary', mountPath: '/tmp' }],
});
const resources = [
  { apiVersion: 'v1', kind: 'Namespace', metadata: { name: namespace, labels: { 'pod-security.kubernetes.io/enforce': 'restricted', 'pod-security.kubernetes.io/enforce-version': 'v1.37' } } },
  { apiVersion: 'networking.k8s.io/v1', kind: 'NetworkPolicy', metadata: { name: 'isolated', namespace }, spec: { podSelector: {}, policyTypes: ['Ingress', 'Egress'] } },
  ...source.filter(item => item.kind === 'ConfigMap' && item.metadata.name !== 'kube-root-ca.crt').map(item => ({ apiVersion: 'v1', kind: 'ConfigMap', metadata: { name: item.metadata.name, namespace }, data: item.data })),
  { apiVersion: 'v1', kind: 'Pod', metadata: { name: 'recovery', namespace }, spec },
];
process.stdout.write(JSON.stringify({ apiVersion: 'v1', kind: 'List', items: resources }));
