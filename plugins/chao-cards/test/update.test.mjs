// node --test test/update.test.mjs — GitHub and dsh are faked, so nothing is downloaded or installed.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {existsSync, mkdtempSync, readFileSync, rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {after, test} from 'node:test';
import {PLUGIN_VERSION} from '../lib/cards.mjs';
import {checkUpdate, installUpdate, latestRelease, newerThan} from '../lib/update.mjs';

const work = mkdtempSync(join(tmpdir(), 'chao-update-test-'));
after(() => rmSync(work, {recursive: true, force: true}));
const base = 'https://github.com/xiangwu738-design/Chao/releases/download/';
const sha = bytes => createHash('sha256').update(bytes).digest('hex');
const payload = Buffer.from('new plugin');

function release(tag, version, {bytes = payload, digest = sha(bytes), prerelease = false, name = `dsh-plugin-chao-cards-${version}.tgz`} = {}) {
  return {tag_name: tag, draft: false, prerelease, html_url: `https://example.test/${tag}`, assets: [{name, size: bytes.length, digest: digest && `sha256:${digest}`, browser_download_url: `${base}${tag}/${name}`}]};
}
function fakeFetch(releases, files = {}) {
  const calls = [];
  const fetchImpl = async url => {
    calls.push(url);
    if (url.includes('/releases?')) return {ok: true, status: 200, json: async () => releases};
    const body = files[url];
    return body ? {ok: true, status: 200, arrayBuffer: async () => body} : {ok: false, status: 404};
  };
  return {fetchImpl, calls};
}

test('version comparison is numeric', () => {
  assert.equal(newerThan('0.10.0', '0.9.9'), true);
  assert.equal(newerThan('0.5.1', '0.5.1'), false);
  assert.equal(newerThan('0.4.9', '0.5.0'), false);
});

test('only stable chao-cards plugin releases with a digest are considered', async () => {
  const {fetchImpl} = fakeFetch([
    release('studio-v9.0.0', '9.0.0', {name: 'dsh-plugin-chao-card-studio-9.0.0.tgz'}),
    release('plugin-v9.1.0', '9.1.0', {prerelease: true}),
    release('plugin-v9.2.0', '9.2.0', {digest: null}),
    release('plugin-v1.2.0', '1.2.0'),
    release('plugin-v1.10.0', '1.10.0'),
    release('v0.9.10', '0.9.10'),
  ]);
  assert.equal((await latestRelease({fetchImpl})).version, '1.10.0');
});

test('checking reports a newer version without downloading', async () => {
  const {fetchImpl, calls} = fakeFetch([release('plugin-v99.0.0', '99.0.0')]);
  const result = await checkUpdate({fetchImpl});
  assert.equal(result.newer, true);
  assert.equal(result.current, PLUGIN_VERSION);
  assert.equal(calls.length, 1);
});

test('nothing happens when already up to date', async () => {
  let ran = false;
  const {fetchImpl, calls} = fakeFetch([release(`plugin-v${PLUGIN_VERSION}`, PLUGIN_VERSION)]);
  const result = await installUpdate({fetchImpl, run: async () => { ran = true; }, dsh: 'dsh.cmd', directory: join(work, 'same')});
  assert.equal(result.updated, false);
  assert.equal(ran, false);
  assert.equal(calls.length, 1);
});

test('a download that does not match the published digest is never installed', async () => {
  let ran = false;
  const entry = release('plugin-v99.0.0', '99.0.0', {digest: '0'.repeat(64)});
  const {fetchImpl} = fakeFetch([entry], {[entry.assets[0].browser_download_url]: payload});
  const directory = join(work, 'tampered');
  const result = await installUpdate({fetchImpl, run: async () => { ran = true; }, dsh: 'dsh.cmd', directory});
  assert.equal(result.ok, false);
  assert.match(result.reason, /校验失败/);
  assert.equal(ran, false);
  assert.equal(existsSync(join(directory, 'dsh-plugin-chao-cards-99.0.0.tgz')), false);
});

test('a verified download is saved in the stable folder and installed with dsh', async () => {
  const runs = [];
  const entry = release('plugin-v99.0.0', '99.0.0');
  const {fetchImpl} = fakeFetch([entry], {[entry.assets[0].browser_download_url]: payload});
  const directory = join(work, 'ok');
  const result = await installUpdate({fetchImpl, run: async (dsh, tarball) => { runs.push([dsh, tarball]); }, dsh: 'C:/dsh/bin/dsh.cmd', directory});
  assert.equal(result.ok, true);
  assert.equal(result.to, '99.0.0');
  assert.deepEqual(runs, [['C:/dsh/bin/dsh.cmd', join(directory, 'dsh-plugin-chao-cards-99.0.0.tgz')]]);
  assert.deepEqual(readFileSync(join(directory, 'dsh-plugin-chao-cards-99.0.0.tgz')), payload);
  assert.match(result.next, /重启|重新打开/);
});

test('without dsh the verified file is kept and the manual command is returned', async () => {
  const entry = release('plugin-v99.0.0', '99.0.0');
  const {fetchImpl} = fakeFetch([entry], {[entry.assets[0].browser_download_url]: payload});
  const result = await installUpdate({fetchImpl, dsh: '', directory: join(work, 'nodsh')});
  assert.equal(result.ok, false);
  assert.match(result.manual_command, /dsh plugin --profile desktop add/);
  assert.equal(existsSync(result.downloaded), true);
});
