// tools/publish_client.mjs signs release/client.json, the manifest 0.9.10+ clients read to update from GitHub Releases.
// A real signature needs the offline key: set FRONTLINE_UPDATE_PRIVATE_KEY to its path to run the signing test too.
import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp, writeFile, readFile, rm} from 'node:fs/promises';
import {existsSync, readFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join, resolve} from 'node:path';
import {createPublicKey, generateKeyPairSync, verify} from 'node:crypto';
import {promisify} from 'node:util';
import {execFile} from 'node:child_process';

const run = promisify(execFile);
const root = resolve(import.meta.dirname, '..', '..');
const script = join(root, 'tools', 'publish_client.mjs');

async function installers(t) {
  const dir = await mkdtemp(join(tmpdir(), 'frontline-release-'));
  t.after(() => rm(dir, {recursive: true, force: true}));
  await writeFile(join(dir, 'Frontline-0.9.10.exe'), 'exe-bytes');
  await writeFile(join(dir, 'Frontline-0.9.10.apk'), 'apk-bytes');
  return dir;
}
const args = (dir, key, extra = []) => [script, '--version', '0.9.10', '--build', '910', '--exe', join(dir, 'Frontline-0.9.10.exe'), '--apk', join(dir, 'Frontline-0.9.10.apk'), '--key', key, '--out', join(dir, 'client.json'), ...extra];

test('a key that does not match the client public key is refused', async t => {
  const dir = await installers(t);
  const {privateKey} = generateKeyPairSync('rsa', {modulusLength: 2048});
  const key = join(dir, 'other.pem');
  await writeFile(key, privateKey.export({type: 'pkcs8', format: 'pem'}));
  await assert.rejects(run(process.execPath, args(dir, key)), error => /不匹配/.test(error.stderr));
  assert.equal(existsSync(join(dir, 'client.json')), false);
});

test('the signed manifest names GitHub release downloads and refuses rollback', {skip: !process.env.FRONTLINE_UPDATE_PRIVATE_KEY && 'FRONTLINE_UPDATE_PRIVATE_KEY not set'}, async t => {
  const dir = await installers(t), key = process.env.FRONTLINE_UPDATE_PRIVATE_KEY;
  await run(process.execPath, args(dir, key));
  const envelope = JSON.parse(await readFile(join(dir, 'client.json'), 'utf8'));
  const publicKey = createPublicKey(readFileSync(join(root, 'assets', 'update_public.pem')));
  assert(verify('RSA-SHA256', Buffer.from(envelope.payload), publicKey, Buffer.from(envelope.signature, 'base64')));
  const release = JSON.parse(envelope.payload);
  assert.equal(release.schema, 2);
  assert.equal(release.files.exe.url, 'https://github.com/xiangwu738-design/Chao/releases/download/v0.9.10/Frontline-0.9.10.exe');
  assert.equal(release.files.apk.bytes, 9);
  await assert.rejects(run(process.execPath, args(dir, key)), error => /build 必须大于/.test(error.stderr));
});
