import fs from 'node:fs';

const namespace = process.argv[2];
const recoveryImage = fs
  .readFileSync(new URL('../../k3s/recovery-image', import.meta.url), 'utf8')
  .trim();
const startServer = [
  'while [ ! -f /tmp/start ]; do sleep 1; done;',
  'exec /bin/k3s server',
  '--disable-agent',
  '--disable-scheduler',
  '--disable-controller-manager',
  '--disable-cloud-controller',
  '--disable-network-policy',
  '--secrets-encryption',
  '--disable traefik,servicelb,coredns,local-storage,metrics-server,gateway-api-crd,runtimes',
  '--node-ip="$POD_IP"',
  '--advertise-address="$POD_IP"',
  '--bind-address=127.0.0.1',
  '--write-kubeconfig=/tmp/recovery.yaml',
  '--write-kubeconfig-mode=0600',
].join(' ');

const resources = [
  {
    apiVersion: 'v1',
    kind: 'Namespace',
    metadata: {
      name: namespace,
      labels: {
        'pod-security.kubernetes.io/enforce': 'baseline',
        'pod-security.kubernetes.io/enforce-version': 'v1.37',
      },
    },
  },
  {
    apiVersion: 'networking.k8s.io/v1',
    kind: 'NetworkPolicy',
    metadata: { name: 'isolated', namespace },
    spec: { podSelector: {}, policyTypes: ['Ingress', 'Egress'] },
  },
  {
    apiVersion: 'v1',
    kind: 'Pod',
    metadata: { name: 'recovery', namespace },
    spec: {
      restartPolicy: 'Never',
      automountServiceAccountToken: false,
      enableServiceLinks: false,
      terminationGracePeriodSeconds: 1,
      securityContext: { runAsUser: 0, seccompProfile: { type: 'RuntimeDefault' } },
      containers: [
        {
          name: 'server',
          image: recoveryImage,
          command: ['/bin/sh', '-ec'],
          args: [startServer],
          env: [
            { name: 'K3S_CONFIG_FILE', value: '/dev/null' },
            { name: 'POD_IP', valueFrom: { fieldRef: { fieldPath: 'status.podIP' } } },
          ],
          securityContext: { allowPrivilegeEscalation: false, capabilities: { drop: ['ALL'] } },
          resources: {
            requests: { cpu: '100m', memory: '256Mi' },
            limits: { cpu: '2', memory: '2Gi' },
          },
          volumeMounts: [
            { name: 'state', mountPath: '/var/lib/rancher/k3s' },
            { name: 'configuration', mountPath: '/etc/rancher/k3s' },
            { name: 'temporary', mountPath: '/tmp' },
          ],
        },
      ],
      volumes: [
        { name: 'state', emptyDir: {} },
        { name: 'configuration', emptyDir: {} },
        { name: 'temporary', emptyDir: {} },
      ],
    },
  },
];
process.stdout.write(JSON.stringify({ apiVersion: 'v1', kind: 'List', items: resources }));
