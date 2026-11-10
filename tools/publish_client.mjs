// Signs release/client.json, the manifest clients use to find and verify new builds on GitHub Releases.
// node tools/publish_client.mjs --version 0.9.10 --build 910 --exe build/Frontline-0.9.10.exe --apk build/Frontline-0.9.10.apk --key <private.pem> [--notes notes.md] [--out <path>]
// Upload the two installers to the release tag v<version> first; the manifest only names their download URLs.
// Keep the private key outside the repository: anyone holding it can ship a client to every player.
import {createHash, createPublicKey, sign, verify} from 'node:crypto';
import {existsSync, mkdirSync, readFileSync, renameSync, writeFileSync} from 'node:fs';
import {basename, dirname, join} from 'node:path';
import {fileURLToPath} from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const DEFAULT_MANIFEST = join(ROOT, 'release', 'client.json');
const DOWNLOADS = 'https://github.com/xiangwu738-design/Chao/releases/download/';
const args = process.argv.slice(2);
const option = name => { const index = args.indexOf(name); return index < 0 ? null : args[index + 1]; };
const fail = message => { console.error(message); process.exit(1); };

const MANIFEST = option('--out') ?? DEFAULT_MANIFEST;
const version = option('--version'), build = Number(option('--build')), keyFile = option('--key'), notesFile = option('--notes');
if (!/^\d+\.\d+\.\d+$/.test(version ?? '')) fail('--version 需为 x.y.z。');
if (!Number.isSafeInteger(build) || build < 900) fail('--build 需为不小于 900 的整数。');
if (!keyFile || !existsSync(keyFile)) fail('--key 需指向签名私钥。');
const key = readFileSync(keyFile);
const publicKey = createPublicKey(key);
if (publicKey.export({type: 'spki', format: 'pem'}).toString().trim() !== readFileSync(join(ROOT, 'assets', 'update_public.pem'), 'utf8').replace(/\r/g, '').trim()) fail('私钥与客户端内置的 assets/update_public.pem 不匹配。');

if (existsSync(MANIFEST)) {
  const previous = JSON.parse(readFileSync(MANIFEST, 'utf8'));
  if (!verify('RSA-SHA256', Buffer.from(previous.payload), publicKey, Buffer.from(previous.signature, 'base64'))) fail('现有 release/client.json 签名无效。');
  if (build <= JSON.parse(previous.payload).build) fail('build 必须大于已发布的版本。');
}

const file = (option('--exe') && option('--apk')) ? extension => {
  const path = option(`--${extension}`), name = basename(path);
  if (!existsSync(path)) fail(`找不到 ${path}`);
  if (!new RegExp(`^Frontline-[A-Za-z0-9.-]+\\.${extension}$`).test(name)) fail(`${name} 的文件名需为 Frontline-<版本>.${extension}`);
  const data = readFileSync(path);
  return {url: `${DOWNLOADS}v${version}/${name}`, bytes: data.length, sha256: createHash('sha256').update(data).digest('hex')};
} : fail('需要 --exe 和 --apk。');

const notes = notesFile ? readFileSync(notesFile, 'utf8').slice(0, 4000) : '';
const payload = JSON.stringify({schema: 2, version, build, published_at: new Date().toISOString(), notes, files: {exe: file('exe'), apk: file('apk')}});
const signature = sign('RSA-SHA256', Buffer.from(payload), key).toString('base64');
mkdirSync(dirname(MANIFEST), {recursive: true});
writeFileSync(`${MANIFEST}.tmp`, `${JSON.stringify({payload, signature})}\n`);
renameSync(`${MANIFEST}.tmp`, MANIFEST);
console.log(JSON.stringify({version, build, files: JSON.parse(payload).files}, null, 1));
