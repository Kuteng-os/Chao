// Publishes cards through the player's own GitHub CLI login; the plugin never sees a GitHub credential.
import {spawn} from 'node:child_process';
import {existsSync, readFileSync} from 'node:fs';
import {basename} from 'node:path';
import {setTimeout as delay} from 'node:timers/promises';
import {PLUGIN_VERSION, issueLink, savePack} from './cards.mjs';

export const UPSTREAM = 'xiangwu738-design/Chao';
const UPSTREAM_OWNER = UPSTREAM.split('/')[0];
const BOT = 'github-actions[bot]';
const WINDOWS_GH = 'C:\\Program Files\\GitHub CLI\\gh.exe';
const GH_TIMEOUT_MS = 60000;
const FORK_RETRIES = 10;
const FORK_RETRY_MS = 3000;
const STATUS_POLL_MS = 8000;
const STATUS_WAIT_MS = 120000;
export const CARD_FILE = /^submissions\/inbox\/(pack-[0-9a-f]{12}\.pack\.json|pack-[0-9a-f]{12}-[0-9a-f]{12}\.png|card-[0-9a-f]{12}\.(card\.json|png))$/;
const MARKER = /^<!-- chao-validation sha:([0-9a-f]+) status:(ok|failed) -->/;

class GhError extends Error {
  constructor(message, {status = 0, missing = false} = {}) {
    super(message);
    this.status = status;
    this.missing = missing;
  }
}

/** Finds gh even when Desktop started before the installer updated PATH. */
function ghCommand() {
  if (process.env.CHAO_GH) return process.env.CHAO_GH;
  return process.platform === 'win32' && existsSync(WINDOWS_GH) ? WINDOWS_GH : 'gh';
}

export function ghRunner() {
  return (args, {input, signal} = {}) => new Promise((resolve, reject) => {
    const child = spawn(ghCommand(), args, {windowsHide: true, timeout: GH_TIMEOUT_MS, signal});
    let stdout = '', stderr = '';
    // Without a decoder, a multi-byte character split across two chunks would corrupt large responses.
    child.stdout.setEncoding('utf8');
    child.stderr.setEncoding('utf8');
    child.stdout.on('data', chunk => { stdout += chunk; });
    child.stderr.on('data', chunk => { stderr += chunk; });
    child.on('error', error => reject(new GhError(error.message, {missing: error.code === 'ENOENT'})));
    child.on('close', code => {
      if (code === 0) return resolve(stdout);
      const status = Number(/HTTP (\d{3})/.exec(stderr)?.[1] ?? 0);
      reject(new GhError(stderr.trim().slice(0, 300) || `gh 退出码 ${code}`, {status}));
    });
    child.stdin.on('error', () => {});
    child.stdin.end(input ?? '');
  });
}

export async function api(run, method, path, body, signal) {
  const args = ['api', '--method', method, path];
  if (body !== undefined) args.push('--input', '-');
  const output = await run(args, {input: body === undefined ? undefined : JSON.stringify(body), signal});
  return output.trim() ? JSON.parse(output) : null;
}

export function reasonFor(error) {
  if (error.missing) return '本机没有安装 GitHub CLI（gh）。可以运行 winget install GitHub.cli 安装，再运行 gh auth login 登录。';
  if (error.status === 401 || /gh auth login|not logged/i.test(error.message)) return 'GitHub CLI 还没有登录，请运行 gh auth login。';
  return `GitHub 操作失败：${error.message}`;
}

const sameLogin = (left, right) => String(left).toLowerCase() === String(right).toLowerCase();

async function headRepository(run, login, signal) {
  if (sameLogin(login, UPSTREAM_OWNER)) return UPSTREAM;
  const fork = await api(run, 'POST', `repos/${UPSTREAM}/forks`, {}, signal);
  for (let attempt = 0; ; attempt++) {
    try {
      await api(run, 'GET', `repos/${fork.full_name}/git/ref/heads/main`, undefined, signal);
      break;
    } catch (error) {
      if (attempt >= FORK_RETRIES) throw error;
      await delay(FORK_RETRY_MS, undefined, {signal});
    }
  }
  // A stale fork still produces a correct PR, so a failed sync is not fatal.
  await api(run, 'POST', `repos/${fork.full_name}/merge-upstream`, {branch: 'main'}, signal).catch(() => {});
  return fork.full_name;
}

async function putFile(run, repo, path, branch, content, message, signal) {
  let sha;
  try {
    sha = (await api(run, 'GET', `repos/${repo}/contents/${path}?ref=${branch}`, undefined, signal)).sha;
  } catch (error) {
    if (error.status !== 404) throw error;
  }
  await api(run, 'PUT', `repos/${repo}/contents/${path}`, {message, content, branch, ...(sha ? {sha} : {})}, signal);
}

function fallback(saved, error) {
  const {ok, pack, checked, digest, ...link} = saved;
  return {...link, ok: false, fallback: true, reason: reasonFor(error), next: '把 upload_url 和 submit_note 交给玩家，由玩家在浏览器里上传整个卡包文件夹。'};
}

const notSubmitted = saved => ({...saved, blocked: true, next: '卡包没有通过程序校验，没有提交。按 errors 修改并重新校验；不能用其他方式提交。'});
const encoded = path => readFileSync(path).toString('base64');
const packFiles = saved => [...saved.art_files, saved.pack_file];

function pullBody(saved) {
  const lines = [`由巢战 DSH 制卡插件 ${PLUGIN_VERSION} 提交的卡包。`, `**卡包：** 《${saved.name}》，${saved.card_count} 张`, `**署名：** ${saved.pack.author}`];
  if (saved.pack.description) lines.push(`**简介：** ${saved.pack.description}`);
  for (const card of saved.cards) {
    lines.push(`### ${card.name}${card.has_art ? '（附卡面）' : ''}`);
    if (card.replaced) lines.push(`修改旧卡《${card.replaced.name}》v${card.replaced.revision}（原作者：${card.replaced.author || '未署名'}）\n\n原规则：${card.replaced.rules_text}`);
    lines.push(`规则：${card.rules_text}`);
  }
  return lines.join('\n\n');
}

export async function submitPack(spec, {run = ghRunner(), signal, ...options} = {}) {
  const saved = await savePack(spec, options);
  if (!saved.ok) return notSubmitted(saved);
  const branch = basename(saved.pack_file).replace('.pack.json', '');
  try {
    const login = (await api(run, 'GET', 'user', undefined, signal)).login;
    const repo = await headRepository(run, login, signal);
    const head = (await api(run, 'GET', `repos/${repo}/git/ref/heads/main`, undefined, signal)).object.sha;
    await api(run, 'POST', `repos/${repo}/git/refs`, {ref: `refs/heads/${branch}`, sha: head}, signal).catch(error => {
      if (error.status !== 422) throw error;
    });
    // Art first and the pack last, so the validation run triggered by the final commit sees every file.
    for (const file of packFiles(saved)) await putFile(run, repo, `submissions/inbox/${basename(file)}`, branch, encoded(file), `提交卡包：${saved.name}`, signal);
    const headRef = repo === UPSTREAM ? branch : `${login}:${branch}`;
    let pull;
    try {
      pull = await api(run, 'POST', `repos/${UPSTREAM}/pulls`, {title: `卡包：${saved.name}（${saved.card_count} 张）`, head: headRef, base: 'main', maintainer_can_modify: true, body: pullBody(saved)}, signal);
    } catch (error) {
      if (error.status !== 422) throw error;
      [pull] = await api(run, 'GET', `repos/${UPSTREAM}/pulls?state=open&head=${encodeURIComponent(`${login}:${branch}`)}`, undefined, signal);
      if (!pull) throw error;
    }
    return {ok: true, name: saved.name, card_count: saved.card_count, pr_number: pull.number, pr_url: pull.html_url, folder: saved.folder, next: '调用 chao_pr_status 并设置 wait=true，查看校验结果。'};
  } catch (error) {
    return fallback(saved, error);
  }
}

/** Replaces every file of the player's own pack PR with the new version of the pack. */
export async function updatePack(number, spec, {run = ghRunner(), signal, ...options} = {}) {
  const saved = await savePack(spec, options);
  if (!saved.ok) return notSubmitted(saved);
  const wanted = new Set(packFiles(saved).map(file => `submissions/inbox/${basename(file)}`));
  try {
    const login = (await api(run, 'GET', 'user', undefined, signal)).login;
    const pull = await api(run, 'GET', `repos/${UPSTREAM}/pulls/${number}`, undefined, signal);
    if (pull.state !== 'open' || !pull.head.repo) return {ok: false, errors: [{path: 'pr', message: '这个 PR 已经关闭，不能更新。'}]};
    if (!sameLogin(pull.head.repo.owner.login, login)) return {ok: false, errors: [{path: 'pr', message: '只能更新自己提交的 PR。'}]};
    const repo = pull.head.repo.full_name, branch = pull.head.ref;
    const files = (await api(run, 'GET', `repos/${UPSTREAM}/pulls/${number}/files?per_page=100`, undefined, signal)).filter(file => CARD_FILE.test(file.filename));
    // A revision dropped by accident would turn into a brand-new duplicate card, so every old replaces must survive.
    const kept = new Set(saved.pack.cards.filter(card => card.replaces).map(card => card.replaces.card_id));
    for (const file of files.filter(item => item.filename.endsWith('.pack.json'))) {
      const blob = await api(run, 'GET', `repos/${repo}/git/blobs/${file.sha}`, undefined, signal);
      const old = JSON.parse(Buffer.from(blob.content, 'base64').toString('utf8'));
      const lost = (old.cards ?? []).filter(card => card.replaces && !kept.has(card.replaces.card_id));
      if (lost.length) return {ok: false, errors: [{path: 'cards', message: `原卡包修改了《${lost.map(card => card.definition?.name).join('、')}》，新版本缺少对应的 replaces，否则会变成新牌。`}]};
    }
    for (const file of packFiles(saved)) await putFile(run, repo, `submissions/inbox/${basename(file)}`, branch, encoded(file), `更新卡包：${saved.name}`, signal);
    for (const file of files) {
      if (wanted.has(file.filename)) continue;
      await api(run, 'DELETE', `repos/${repo}/contents/${file.filename}`, {message: '移除旧版本', sha: file.sha, branch}, signal);
    }
    return {ok: true, name: saved.name, card_count: saved.card_count, pr_number: number, pr_url: pull.html_url, next: '调用 chao_pr_status 并设置 wait=true，查看新的校验结果。'};
  } catch (error) {
    return fallback(saved, error);
  }
}

export async function readStatus(run, number, signal) {
  const pull = await api(run, 'GET', `repos/${UPSTREAM}/pulls/${number}`, undefined, signal);
  const comments = await api(run, 'GET', `repos/${UPSTREAM}/issues/${number}/comments?per_page=100`, undefined, signal);
  // Only the workflow's own comment counts; a PR author could otherwise forge the marker.
  const latest = comments.filter(comment => comment.user?.login === BOT && MARKER.test(comment.body)).at(-1);
  const match = latest ? MARKER.exec(latest.body) : null;
  const current = match && match[1] === pull.head.sha;
  return {ok: true, pr_number: number, pr_url: pull.html_url, state: pull.state, merged: Boolean(pull.merged), validation: current ? match[2] : 'pending', details: current ? latest.body.replace(MARKER, '').trim() : ''};
}

export async function prStatus(number, {run = ghRunner(), signal, wait = false, pollMs = STATUS_POLL_MS, maxWaitMs = STATUS_WAIT_MS} = {}) {
  const deadline = Date.now() + maxWaitMs;
  try {
    for (;;) {
      const status = await readStatus(run, number, signal);
      if (!wait || status.validation !== 'pending' || status.state !== 'open' || Date.now() >= deadline) return status;
      await delay(pollMs, undefined, {signal});
    }
  } catch (error) {
    return {ok: false, reason: reasonFor(error)};
  }
}

export async function reportIssue(title, details, card, {submit = false, run = ghRunner(), signal} = {}) {
  const link = issueLink(title, details, card);
  if (!submit) return link;
  const fenced = card ? `\n\n### 卡牌 JSON\n\n\`\`\`json\n${card.replaceAll('```', "'''")}\n\`\`\`` : '';
  try {
    const issue = await api(run, 'POST', `repos/${UPSTREAM}/issues`, {title: `[报错] ${title}`, body: `### 游戏版本\n\ndsh-plugin-${PLUGIN_VERSION}\n\n### 报错内容\n\n${details}${fenced}`}, signal);
    return {ok: true, issue_number: issue.number, issue_url: issue.html_url};
  } catch (error) {
    return {...link, ok: false, fallback: true, reason: reasonFor(error)};
  }
}
