import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
const [archivePath, imageReference] = process.argv.slice(2);
const extractFile = (file) => {
  const result = spawnSync('tar', ['-xOf', archivePath, file], { maxBuffer: 16 * 1024 * 1024 });
  if (result.status !== 0) {
    throw Error('Image archive metadata is missing');
  }
  return result.stdout;
};
const normalizeReference = (value) => value.replace(/^docker[.]io\/library\//, '');
const archiveListing = spawnSync('tar', ['-tf', archivePath], {
  encoding: 'utf8',
  maxBuffer: 16 * 1024 * 1024,
});
if (archiveListing.status !== 0) {
  throw Error('Image archive is unreadable');
}
let configurationBytes;
if (archiveListing.stdout.split('\n').includes('index.json')) {
  const index = JSON.parse(extractFile('index.json'));
  const descriptor = index.manifests.find((item) =>
    Object.values(item.annotations ?? {}).some(
      (value) => normalizeReference(value) === normalizeReference(imageReference),
    ),
  );
  if (!descriptor) {
    throw Error('Declared image is missing from the OCI archive');
  }
  const blobPath = (digest) => 'blobs/' + digest.replace(':', '/');
  let manifest = JSON.parse(extractFile(blobPath(descriptor.digest)));
  if (manifest.manifests) {
    const platform = manifest.manifests.find(
      (item) => item.platform?.os === 'linux' && item.platform?.architecture === 'amd64',
    );
    if (!platform) {
      throw Error('Linux amd64 image is missing');
    }
    manifest = JSON.parse(extractFile(blobPath(platform.digest)));
  }
  configurationBytes = extractFile(blobPath(manifest.config.digest));
} else {
  const manifest = JSON.parse(extractFile('manifest.json')).find((item) =>
    item.RepoTags?.some(
      (value) => normalizeReference(value) === normalizeReference(imageReference),
    ),
  );
  if (!manifest) {
    throw Error('Declared image is missing from the Docker archive');
  }
  configurationBytes = extractFile(manifest.Config);
}
const imageConfiguration = JSON.parse(configurationBytes);
if (imageConfiguration.os !== 'linux' || imageConfiguration.architecture !== 'amd64') {
  throw Error('The image must target Linux amd64');
}
process.stdout.write(
  'sha256:' + createHash('sha256').update(configurationBytes).digest('hex') + '\n',
);
