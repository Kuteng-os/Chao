// Stops the agent from publishing a card with general-purpose tools, which would skip the checks inside chao_submit_pr.
// This covers the ordinary routes only; the pull-request workflow and the catalog intake remain the authoritative checks.
const GH = String.raw`\bgh(?:\.exe)?["']?\s+`;
const CHAO_CONTENT = /submissions[\\/](?:inbox|accepted)|data[\\/]catalog\.json|\.card\.json|card-[0-9a-f]{12}|xiangwu738-design[\\/]chao/i;
const CHAO_FILE = /\.card\.json$|submissions[\\/](?:inbox|accepted)[\\/]|data[\\/]catalog\.json$/i;
const GITHUB_WRITE = new RegExp([
  String.raw`${GH}pr\s+(?:create|edit|merge|reopen|review|ready)\b`,
  String.raw`${GH}api\b[^\n]*(?:-X\s*|--method[\s=]+)["']?(?:POST|PUT|PATCH|DELETE)\b`,
  String.raw`${GH}api\b[^\n]*\s(?:-f|-F|--field|--raw-field|--input)[\s=]`,
  String.raw`\bgit\s+push\b`,
  String.raw`api\.github\.com\b[^\n]*(?:\s-X\s*["']?(?:POST|PUT|PATCH|DELETE)\b|\s--data\b|\s-d\s)`,
  String.raw`(?:\s-X\s*["']?(?:POST|PUT|PATCH|DELETE)\b|\s--data\b|\s-d\s)[^\n]*api\.github\.com\b`,
].join('|'), 'i');

const REASON = '巢战卡牌只能通过 chao_submit_pr、chao_update_pr、chao_approve_pr 和 chao_publish_inbox 提交或发布，这些工具会先运行程序校验。校验失败时请修改卡牌，不要用其他方式绕过。';

/** Returns the denial text for a call that would publish a card outside the plugin's tools. */
export function bypassReason(name, args) {
  if (name === 'bash') {
    const command = String(args?.command ?? '');
    return GITHUB_WRITE.test(command) && CHAO_CONTENT.test(command) ? REASON : undefined;
  }
  if (name === 'write' || name === 'edit') return CHAO_FILE.test(String(args?.file_path ?? '')) ? REASON : undefined;
  return undefined;
}
