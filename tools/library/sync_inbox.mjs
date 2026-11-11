// One-command intake: node tools/library/sync_inbox.mjs [--all] [--dry-run]
// Pulls merged submissions, asks about each card, then validates, commits and pushes after a final confirmation.
import {execFileSync} from 'node:child_process';
import {readFileSync, readdirSync} from 'node:fs';
import {join} from 'node:path';
import {createInterface} from 'node:readline';
import {ROOT} from './catalog_io.mjs';

const INBOX = join(ROOT, 'submissions', 'inbox');
const TOOLS = join(ROOT, 'tools', 'library');
const PATHS = ['data', 'submissions'];
const args = new Set(process.argv.slice(2));
const unknown = [...args].filter(arg => !['--all', '--dry-run'].includes(arg));
if (unknown.length) {
  console.error(`未知参数：${unknown.join(' ')}\n用法：node tools/library/sync_inbox.mjs [--all] [--dry-run]`);
  process.exit(1);
}
const takeAll = args.has('--all'), dryRun = args.has('--dry-run');

const git = (...command) => execFileSync('git', command, {cwd: ROOT, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe']}).trim();
const node = (script, ...command) => execFileSync(process.execPath, [join(TOOLS, script), ...command], {cwd: ROOT, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe']});
const stop = message => { console.error(message); process.exit(1); };

const rl = createInterface({input: process.stdin});
const lines = rl[Symbol.asyncIterator]();
async function confirm(question) {
  process.stdout.write(`${question} [y/N] `);
  const {value, done} = await lines.next();
  if (done) console.log('');
  return !done && /^y(es)?$/i.test(value.trim());
}

/** Undoes only this run's changes; the clean-tree check below guarantees nothing else lives there. */
function discardChanges() {
  git('restore', '--staged', '--worktree', '--', ...PATHS);
  git('clean', '-fdq', '--', ...PATHS);
}

/** One inbox file: a card pack, or a single card from an older pull request. */
function describe(file) {
  const path = join(INBOX, file);
  let preview;
  try {
    preview = JSON.parse(node('add_card.mjs', path, '--dry-run'));
  } catch (error) {
    return {file, path, errors: String(error.stderr || error.message).trim()};
  }
  const source = JSON.parse(readFileSync(path, 'utf8'));
  const definitions = source.cards ? source.cards.map(entry => entry.definition) : [source.definition];
  const cards = preview.cards.map((card, index) => {
    const {kind, unit_class: unitClass, cost, attack, health} = definitions[index];
    return {...card, stats: `${kind}${unitClass ? `/${unitClass}` : ''} 费用 ${cost} 攻防 ${attack}/${health}`};
  });
  return {file, path, pack: file.endsWith('.pack.json'), name: preview.name, author: preview.author, description: source.description ?? '', cards};
}

function show(item, index, total) {
  console.log(`\n[${index}/${total}] ${item.pack ? `卡包《${item.name}》，${item.cards.length} 张` : item.name}（${item.file}）`);
  console.log(`  作者：${item.author}${item.description ? `　简介：${item.description}` : ''}`);
  for (const card of item.cards) {
    console.log(`  · ${card.name}　${card.stats}`);
    if (card.replaces) console.log(`    修改旧卡：《${card.replaces.name}》v${card.replaces.revision}（原作者：${card.replaces.author || '未署名'}）\n    原规则：${card.replaces.rules_text || '（无效果）'}`);
    console.log(`    规则：${card.rules_text || '（无效果）'}`);
  }
}

async function main() {
  if (!dryRun && git('status', '--porcelain', '--', ...PATHS)) stop('data 或 submissions 目录有未提交的改动，请先提交或还原后再运行，以免混进这次发布。');
  console.log('拉取已合并的投稿…');
  try {
    git('pull', '--ff-only');
  } catch (error) {
    stop(`git pull 失败：${String(error.stderr || error.message).trim()}`);
  }

  const files = readdirSync(INBOX).filter(name => name.endsWith('.pack.json') || name.endsWith('.card.json')).sort();
  if (!files.length) {
    console.log('投稿目录是空的，没有需要入库的卡包。');
    return;
  }
  const cards = files.map(describe);
  const valid = cards.filter(card => !card.errors), invalid = cards.filter(card => card.errors);
  for (const card of invalid) console.log(`\n跳过 ${card.file}：\n  ${card.errors.replaceAll('\n', '\n  ')}`);

  if (dryRun) {
    valid.forEach((card, index) => show(card, index + 1, valid.length));
    console.log(`\n预览结束：${valid.length} 个可入库，${invalid.length} 个校验失败。没有写入任何内容。`);
    return;
  }

  const accepted = [];
  for (const [index, card] of valid.entries()) {
    show(card, index + 1, valid.length);
    if (!takeAll && !await confirm(card.pack ? '收录这个卡包（整包）？' : '收录这张卡？')) continue;
    try {
      node('add_card.mjs', card.path);
      accepted.push(card);
    } catch (error) {
      console.error(`入库失败：${String(error.stderr || error.message).trim()}`);
    }
  }
  if (!accepted.length) {
    console.log('\n没有收录任何卡包，未作改动。');
    return;
  }

  try {
    node('validate_catalog.mjs');
  } catch (error) {
    discardChanges();
    stop(`卡库完整性检查失败，已撤销这次入库：\n${String(error.stderr || error.message).trim()}`);
  }

  const names = accepted.flatMap(item => item.cards.map(card => card.name));
  console.log(`\n本次收录 ${accepted.length} 个投稿、${names.length} 张卡：${names.join('、')}`);
  if (invalid.length) console.log(`校验失败未收录 ${invalid.length} 个投稿，文件仍在投稿目录。`);
  if (!await confirm('提交并推送给所有玩家？')) {
    console.log('已保留本地改动，没有推送。放弃这次入库可运行：git restore . ; git clean -fd data submissions');
    return;
  }
  git('add', '--', ...PATHS);
  git('commit', '-m', `收录卡牌：${names.join('、').slice(0, 60)}`);
  try {
    git('push');
  } catch (error) {
    stop(`提交成功，但推送失败，请稍后运行 git push：${String(error.stderr || error.message).trim()}`);
  }
  console.log('已发布，玩家下次启动游戏会自动更新。');
}

main().catch(error => stop(error.stack ?? String(error))).finally(() => rl.close());
