const namespace = process.argv[2];
if (!['caddy', 'lgtm'].includes(namespace)) throw Error('Pass caddy or lgtm');
const names = namespace === 'caddy' ? ['data', 'config', 'media', 'logs'] : ['data'];
console.log(JSON.stringify({
  apiVersion: 'v1', kind: 'Pod', metadata: { name: 'state-backup', namespace },
  spec: {
    restartPolicy: 'Never', automountServiceAccountToken: false, terminationGracePeriodSeconds: 1,
    securityContext: { runAsUser: namespace === 'caddy' ? 1000 : 0, seccompProfile: { type: 'RuntimeDefault' } },
    containers: [{
      name: 'transfer',
      image: 'node:24.22.2-bookworm-slim@sha256:01d566e8d94d8c619591d78652babfccd3c6992a3dffa9ed5ab39e11cf6c70e9',
      command: ['sh', '-c', 'sleep 900'],
      securityContext: { allowPrivilegeEscalation: false, readOnlyRootFilesystem: true, capabilities: { drop: ['ALL'] } },
      resources: { requests: { cpu: '10m', memory: '16Mi' }, limits: { cpu: '500m', memory: '128Mi' } },
      volumeMounts: [...names.map(name => ({ name, mountPath: `/${name}`, readOnly: true })), { name: 'temporary', mountPath: '/tmp' }],
    }],
    volumes: [...names.map(name => ({ name, persistentVolumeClaim: { claimName: name, readOnly: true } })), { name: 'temporary', emptyDir: {} }],
  },
}));
