import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
const [archive, reference] = process.argv.slice(2);
const extract = file => {
  const result = spawnSync('tar', ['-xOf', archive, file], { maxBuffer: 16 * 1024 * 1024 });
  if (result.status !== 0) throw Error('Image archive metadata is missing');
  return result.stdout;
};
const normalize = value => value.replace(/^docker[.]io\/library\//, '');
const names = spawnSync('tar', ['-tf', archive], { encoding: 'utf8', maxBuffer: 16 * 1024 * 1024 });
if (names.status !== 0) throw Error('Image archive is unreadable');
let configuration;
if (names.stdout.split('\n').includes('index.json')) {
  const index = JSON.parse(extract('index.json'));
  const descriptor = index.manifests.find(item => Object.values(item.annotations ?? {}).some(value => normalize(value) === normalize(reference)));
  if (!descriptor) throw Error('Declared image is missing from the OCI archive');
  const blob = digest => 'blobs/' + digest.replace(':', '/');
  let manifest = JSON.parse(extract(blob(descriptor.digest)));
  if (manifest.manifests) {
    const platform = manifest.manifests.find(item => item.platform?.os === 'linux' && item.platform?.architecture === 'amd64');
    if (!platform) throw Error('Linux amd64 image is missing');
    manifest = JSON.parse(extract(blob(platform.digest)));
  }
  configuration = extract(blob(manifest.config.digest));
} else {
  const manifest = JSON.parse(extract('manifest.json')).find(item => item.RepoTags?.some(value => normalize(value) === normalize(reference)));
  if (!manifest) throw Error('Declared image is missing from the Docker archive');
  configuration = extract(manifest.Config);
}
const metadata = JSON.parse(configuration);
if (metadata.os !== 'linux' || metadata.architecture !== 'amd64') throw Error('The image must target Linux amd64');
process.stdout.write('sha256:' + createHash('sha256').update(configuration).digest('hex') + '\n');
