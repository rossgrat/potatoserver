import fs from 'node:fs';

const [backupDirectory, backupLabel, namespace] = process.argv.slice(2);
const serviceNames = {
  'miniflux-postgres-1': 'miniflux',
  'job-board-postgres': 'job-board',
  'wubzduh-postgres-1': 'wubzduh',
  'umami-postgres-1': 'umami',
  'pages-cms-postgres-1': 'pages-cms',
};
const service = serviceNames[backupLabel];
const savedResources = JSON.parse(
  fs.readFileSync(`${backupDirectory}/${service}-resources.json`),
).items;
const copyWorkloadSpec = (kind, name) =>
  structuredClone(
    savedResources.find((item) => item.kind === kind && item.metadata.name === name).spec,
  );
const databaseSpec = copyWorkloadSpec('StatefulSet', 'postgres');
databaseSpec.replicas = 1;
delete databaseSpec.volumeClaimTemplates;
databaseSpec.template.spec.volumes.push({ name: 'data', emptyDir: {} });
databaseSpec.template.spec.containers[0].resources = {
  requests: { cpu: '100m', memory: '128Mi' },
  limits: { cpu: '1', memory: '512Mi' },
};
const applicationSpec = copyWorkloadSpec('Deployment', service);
applicationSpec.replicas = 0;
for (const volume of applicationSpec.template.spec.volumes ?? []) {
  if (volume.persistentVolumeClaim) {
    delete volume.persistentVolumeClaim;
    volume.emptyDir = {};
  }
}
if (service === 'miniflux') {
  const container = applicationSpec.template.spec.containers[0];
  container.env = (container.env ?? []).filter(
    (variable) =>
      !['RUN_MIGRATIONS', 'CREATE_ADMIN', 'DISABLE_SCHEDULER_SERVICE'].includes(variable.name),
  );
  container.env.push(
    { name: 'RUN_MIGRATIONS', value: '0' },
    { name: 'CREATE_ADMIN', value: '0' },
    { name: 'DISABLE_SCHEDULER_SERVICE', value: '1' },
  );
}
const metadata = (name) => ({ name, namespace });
const resources = [
  {
    apiVersion: 'v1',
    kind: 'Namespace',
    metadata: {
      name: namespace,
      labels: {
        'pod-security.kubernetes.io/enforce': 'restricted',
        'pod-security.kubernetes.io/enforce-version': 'v1.37',
      },
    },
  },
  ...savedResources
    .filter(
      (item) =>
        ['Secret', 'ConfigMap'].includes(item.kind) && item.metadata.name !== 'kube-root-ca.crt',
    )
    .map((item) => ({
      apiVersion: 'v1',
      kind: item.kind,
      metadata: metadata(item.metadata.name),
      ...(item.kind === 'Secret' ? { type: item.type } : {}),
      data: item.data,
    })),
  {
    apiVersion: 'v1',
    kind: 'Service',
    metadata: metadata('postgres'),
    spec: { clusterIP: 'None', selector: { app: 'postgres' }, ports: [{ port: 5432 }] },
  },
  {
    apiVersion: 'apps/v1',
    kind: 'StatefulSet',
    metadata: metadata('postgres'),
    spec: databaseSpec,
  },
  { apiVersion: 'apps/v1', kind: 'Deployment', metadata: metadata(service), spec: applicationSpec },
  {
    apiVersion: 'v1',
    kind: 'Service',
    metadata: metadata('web'),
    spec: {
      selector: applicationSpec.selector.matchLabels,
      ports: [{ port: applicationSpec.template.spec.containers[0].ports[0].containerPort }],
    },
  },
  {
    apiVersion: 'networking.k8s.io/v1',
    kind: 'NetworkPolicy',
    metadata: metadata('isolated'),
    spec: {
      podSelector: {},
      policyTypes: ['Ingress', 'Egress'],
      ingress: [{ from: [{ podSelector: {} }] }],
      egress: [
        { to: [{ podSelector: {} }] },
        {
          to: [
            {
              namespaceSelector: { matchLabels: { 'kubernetes.io/metadata.name': 'kube-system' } },
              podSelector: { matchLabels: { 'k8s-app': 'kube-dns' } },
            },
          ],
          ports: [
            { protocol: 'UDP', port: 53 },
            { protocol: 'TCP', port: 53 },
          ],
        },
      ],
    },
  },
  {
    apiVersion: 'v1',
    kind: 'Pod',
    metadata: metadata('client'),
    spec: {
      restartPolicy: 'Never',
      automountServiceAccountToken: false,
      securityContext: {
        runAsNonRoot: true,
        runAsUser: 1000,
        runAsGroup: 1000,
        seccompProfile: { type: 'RuntimeDefault' },
      },
      containers: [
        {
          name: 'client',
          image: fs.readFileSync(new URL('../../k3s/backup-image', import.meta.url), 'utf8').trim(),
          command: ['node', '-e', 'setInterval(() => {}, 1000)'],
          securityContext: {
            allowPrivilegeEscalation: false,
            readOnlyRootFilesystem: true,
            capabilities: { drop: ['ALL'] },
          },
          resources: {
            requests: { cpu: '10m', memory: '32Mi' },
            limits: { cpu: '100m', memory: '128Mi' },
          },
        },
      ],
    },
  },
];
process.stdout.write(JSON.stringify({ apiVersion: 'v1', kind: 'List', items: resources }));
