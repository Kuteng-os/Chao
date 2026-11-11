// Checks GitHub Releases for a newer chao-cards plugin and installs it with DSH's own `dsh plugin add`.
// Inside DSH the packaged dsh.cmd is already on the host PATH, so players do not need the command installed globally.
import {spawn} from 'node:child_process';
import {createHash} from 'node:crypto';
import {existsSync, mkdirSync, renameSync, rmSync, writeFileSync} from 'node:fs';
import {homedir} from 'node:os';
import {delimiter, join} from 'node:path';
import {PLUGIN_VERSION} from './cards.mjs';

const RELEASES = 'https://api.github.com/repos/xiangwu738-design/Chao/releases?per_page=50';
const TAG = /^plugin-v(\d+)\.(\d+)\.(\d+)$/;
const ASSET = version => `dsh-plugin-chao-cards-${version}.tgz`;
const DOWNLOAD_PREFIX = 'https://github.com/xiangwu738-design/Chao/releases/download/';
const MAX_BYTES = 20 * 1024 * 1024;
const TIMEOUT_MS = 60000;
const INSTALL_TIMEOUT_MS = 120000;
const MANUAL_COMMAND = 'irm https://raw.githubusercontent.com/xiangwu738-design/Chao/main/tools/update_plugin.ps1 | iex';

const parts = version => version.split('.').map(Number);
export const newerThan = (a, b) => { const x = parts(a), y = parts(b); for (let i = 0; i < 3; i++) if (x[i] !== y[i]) return x[i] > y[i]; return false; };

/** DSH keeps installed tarballs by path, so updates live in one stable folder rather than a temporary one. */
export function pluginDirectory() {
  return process.env.CHAO_PLUGIN_DIR || join(process.env.LOCALAPPDATA || join(homedir(), 'AppData', 'Local'), 'ChaoCards', 'plugins');
}

export async function latestRelease({fetchImpl = globalThis.fetch} = {}) {
  const response = await fetchImpl(RELEASES, {headers: {accept: 'application/vnd.github+json'}, signal: AbortSignal.timeout(TIMEOUT_MS)});
  if (!response.ok) throw new Error(`GitHub 返回 ${response.status}`);
  let best = null;
  for (const release of await response.json()) {
    const match = TAG.exec(release.tag_name ?? '');
    if (!match || release.draft || release.prerelease) continue;
    const version = match.slice(1).join('.');
    const asset = (release.assets ?? []).find(item => item.name === ASSET(version));
    const digest = /^sha256:([0-9a-f]{64})$/.exec(asset?.digest ?? '')?.[1];
    if (!asset || !digest || !String(asset.browser_download_url).startsWith(DOWNLOAD_PREFIX) || asset.size > MAX_BYTES) continue;
    if (!best || newerThan(version, best.version)) best = {version, url: asset.browser_download_url, bytes: asset.size, sha256: digest, notes_url: release.html_url};
  }
  return best;
}

export async function checkUpdate(options) {
  try {
    const latest = await latestRelease(options);
    if (!latest) return {ok: true, current: PLUGIN_VERSION, newer: false, message: 'GitHub 上还没有发布插件。'};
    const newer = newerThan(latest.version, PLUGIN_VERSION);
    return {ok: true, current: PLUGIN_VERSION, latest: latest.version, newer, release_url: latest.notes_url, message: newer ? `有新版插件 ${latest.version}，当前 ${PLUGIN_VERSION}。调用本工具并设置 install=true 即可更新。` : '已是最新版本。'};
  } catch (error) {
    return {ok: false, current: PLUGIN_VERSION, reason: `无法连接 GitHub：${error.message}`, manual_command: MANUAL_COMMAND};
  }
}

function findDsh() {
  if (process.env.CHAO_DSH) return process.env.CHAO_DSH;
  for (const dir of String(process.env.PATH ?? process.env.Path ?? '').split(delimiter)) {
    for (const name of process.platform === 'win32' ? ['dsh.cmd', 'dsh.exe'] : ['dsh']) if (dir && existsSync(join(dir, name))) return join(dir, name);
  }
  return '';
}

/** Runs `dsh plugin --profile desktop add <tarball>`; .cmd shims must go through cmd.exe on Windows, and /s strips one extra pair of outer quotes. */
export function dshRunner() {
  return (dsh, tarball) => new Promise((resolve, reject) => {
    const args = ['plugin', '--profile', 'desktop', 'add', tarball];
    const child = process.platform === 'win32' && /\.cmd$/i.test(dsh)
      ? spawn(process.env.ComSpec || 'cmd.exe', ['/d', '/s', '/c', `""${[dsh, ...args].map(arg => arg.replaceAll('"', '')).join('" "')}""`], {windowsHide: true, windowsVerbatimArguments: true, timeout: INSTALL_TIMEOUT_MS})
      : spawn(dsh, args, {windowsHide: true, timeout: INSTALL_TIMEOUT_MS});
    let output = '';
    child.stdout.setEncoding('utf8').on('data', chunk => { output += chunk; });
    child.stderr.setEncoding('utf8').on('data', chunk => { output += chunk; });
    child.on('error', reject);
    child.on('close', code => code === 0 ? resolve(output) : reject(new Error(output.trim().slice(-400) || `dsh 退出码 ${code}`)));
  });
}

export async function installUpdate({fetchImpl = globalThis.fetch, run = dshRunner(), dsh = findDsh(), directory = pluginDirectory()} = {}) {
  let latest;
  try {
    latest = await latestRelease({fetchImpl});
  } catch (error) {
    return {ok: false, reason: `无法连接 GitHub：${error.message}`, manual_command: MANUAL_COMMAND};
  }
  if (!latest || !newerThan(latest.version, PLUGIN_VERSION)) return {ok: true, updated: false, current: PLUGIN_VERSION, message: '已是最新版本，无需更新。'};
  const target = join(directory, ASSET(latest.version));
  try {
    const response = await fetchImpl(latest.url, {signal: AbortSignal.timeout(TIMEOUT_MS)});
    if (!response.ok) throw new Error(`下载返回 ${response.status}`);
    const bytes = Buffer.from(await response.arrayBuffer());
    // GitHub publishes each asset's SHA-256; a mismatch means the download is not the published file.
    if (bytes.length !== latest.bytes || createHash('sha256').update(bytes).digest('hex') !== latest.sha256) throw new Error('安装包校验失败');
    mkdirSync(directory, {recursive: true});
    writeFileSync(`${target}.part`, bytes);
    rmSync(target, {force: true});
    renameSync(`${target}.part`, target);
  } catch (error) {
    rmSync(`${target}.part`, {force: true});
    return {ok: false, reason: `下载失败：${error.message}`, manual_command: MANUAL_COMMAND};
  }
  if (!dsh) return {ok: false, downloaded: target, reason: '找不到 dsh 命令。', manual_command: `dsh plugin --profile desktop add "${target}"`};
  try {
    await run(dsh, target);
  } catch (error) {
    return {ok: false, downloaded: target, reason: `安装失败：${error.message}`, manual_command: `dsh plugin --profile desktop add "${target}"`};
  }
  return {ok: true, updated: true, from: PLUGIN_VERSION, to: latest.version, installed: target, next: '请完全退出 DSH Desktop 再重新打开，新版插件才会生效。'};
}
