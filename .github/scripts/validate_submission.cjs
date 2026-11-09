const {mkdtempSync, writeFileSync} = require('node:fs');
const {execFileSync} = require('node:child_process');
const {join} = require('node:path');
const os = require('node:os');

const ALLOWED = /^submissions\/inbox\/card-[0-9a-f]{12}\.(card\.json|png)$/;
const MAX_FILES = 40;
const MAX_BYTES = 2 * 1024 * 1024;
const fence = text => '```text\n' + String(text).replaceAll('```', "'''") + '\n```';

async function issueFor({github, owner, repo, title}) {
  const open = await github.paginate(github.rest.issues.listForRepo, {owner, repo, state: 'open', creator: 'github-actions[bot]', per_page: 100});
  return open.find(issue => issue.title === title);
}

module.exports = async ({github, context, core}) => {
  const {owner, repo} = context.repo;
  const pr = context.payload.pull_request;
  const title = `[报错] 卡牌提交 #${pr.number} 校验失败`;
  const errors = [];

  const files = await github.paginate(github.rest.pulls.listFiles, {owner, repo, pull_number: pr.number, per_page: 100});
  const directory = mkdtempSync(join(os.tmpdir(), 'submission-'));
  const cards = [];
  if (files.length > MAX_FILES) errors.push(`一次最多提交 ${MAX_FILES} 个文件。`);
  for (const file of files.slice(0, MAX_FILES)) {
    if (!ALLOWED.test(file.filename) || file.status === 'removed') {
      errors.push(`不允许修改这个路径：${file.filename}`);
      continue;
    }
    // Blobs serve files above the 1 MiB contents-API cutoff; the size is checked before writing.
    const {data} = await github.rest.git.getBlob({owner: pr.head.repo.owner.login, repo: pr.head.repo.name, file_sha: file.sha});
    if (data.size > MAX_BYTES) {
      errors.push(`文件过大：${file.filename}`);
      continue;
    }
    const target = join(directory, file.filename.split('/').pop());
    writeFileSync(target, Buffer.from(data.content, 'base64'));
    if (target.endsWith('.card.json')) cards.push(target);
  }
  if (!cards.length) errors.push('没有找到 card-*.card.json 文件。');

  if (cards.length) {
    let output;
    try {
      output = execFileSync('node', ['tools/library/validate_submission.mjs', ...cards], {encoding: 'utf8'});
    } catch (failure) {
      output = failure.stdout;
      if (!output) errors.push(`校验程序异常：${failure.message}`);
    }
    if (output) for (const result of JSON.parse(output).results) for (const message of result.errors) errors.push(`${result.file}: ${message}`);
  }

  const existing = await issueFor({github, owner, repo, title});
  if (!errors.length) {
    if (existing) {
      await github.rest.issues.createComment({owner, repo, issue_number: existing.number, body: `PR 最新提交 ${pr.head.sha.slice(0, 7)} 已通过校验。`});
      await github.rest.issues.update({owner, repo, issue_number: existing.number, state: 'closed'});
    }
    core.info('Submission is valid.');
    return;
  }

  const body = `PR #${pr.number} 的卡牌没有通过校验（提交 ${pr.head.sha.slice(0, 7)}）。\n\n${fence(errors.join('\n'))}`;
  let issueNumber = existing?.number;
  if (existing) {
    await github.rest.issues.createComment({owner, repo, issue_number: existing.number, body});
  } else {
    const created = await github.rest.issues.create({owner, repo, title, body});
    issueNumber = created.data.number;
    await github.rest.issues.createComment({owner, repo, issue_number: pr.number, body: `校验未通过，详情见 #${issueNumber}。修改后重新提交会自动复查。`});
  }
  core.setFailed(`Validation failed, see issue #${issueNumber}.`);
};
