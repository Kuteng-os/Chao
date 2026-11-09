import {createHash} from 'node:crypto';

export class ApiError extends Error {
  constructor(code, message, status = 422, details, retryable = false) {
    super(message); Object.assign(this, {code, status, details, retryable});
  }
}
export const fail = (code, message, status = 422, details) => { throw new ApiError(code, message, status, details); };
export function normalizeText(text) {
  for (let i = 0; i < text.length; i++) {
    const c = text.charCodeAt(i);
    if (c >= 0xd800 && c <= 0xdbff) {
      const next = text.charCodeAt(++i);
      if (!(next >= 0xdc00 && next <= 0xdfff)) fail('INVALID_REQUEST', '文本包含无效 Unicode。', 400);
    } else if (c >= 0xdc00 && c <= 0xdfff) fail('INVALID_REQUEST', '文本包含无效 Unicode。', 400);
  }
  return text.replace(/\r\n?/g, '\n').normalize('NFC');
}
export function normalize(value) {
  if (typeof value === 'string') return normalizeText(value);
  if (typeof value === 'number') {
    if (!Number.isSafeInteger(value)) fail('INVALID_REQUEST', '只接受安全范围内整数。', 400);
    return value === 0 ? 0 : value;
  }
  if (Array.isArray(value)) return value.map(normalize);
  if (value && typeof value === 'object') {
    const result = Object.create(null);
    for (const [key, val] of Object.entries(value)) {
      const nk = normalizeText(key);
      if (Object.hasOwn(result, nk)) fail('INVALID_REQUEST', '规范化后存在重复字段。', 400);
      result[nk] = normalize(val);
    }
    return result;
  }
  if (value === null || typeof value === 'boolean') return value;
  fail('INVALID_REQUEST', '无效 JSON 值。', 400);
}
const quoted = text => '"' + text.replace(/["\\\u0000-\u001f]/g, c => c === '"' ? '\\"' : c === '\\' ? '\\\\' : c === '\n' ? '\\n' : c === '\t' ? '\\t' : '\\u' + c.charCodeAt(0).toString(16).padStart(4, '0')) + '"';
export function canonical(input) {
  const encode = value => {
    if (typeof value === 'string') return quoted(value);
    if (Array.isArray(value)) return '[' + value.map(encode).join(',') + ']';
    if (value && typeof value === 'object') return '{' + Object.keys(value).sort().map(k => quoted(k) + ':' + encode(value[k])).join(',') + '}';
    return JSON.stringify(value);
  };
  return encode(normalize(input));
}
export const hash = value => createHash('sha256').update(canonical(value), 'utf8').digest('hex');

// A lexical parser is needed: JSON.parse alone loses duplicate keys and accepts lone surrogates.
export function strictParse(input, maxBytes = 65536, maxDepth = 16) {
  const bytes = Buffer.isBuffer(input) ? input : Buffer.from(input, 'utf8');
  if (bytes.length > maxBytes) fail('INPUT_TOO_LONG', 'JSON 超过大小限制。', 413);
  let text;
  try { text = new TextDecoder('utf-8', {fatal: true, ignoreBOM: true}).decode(bytes); }
  catch { fail('INVALID_REQUEST', 'JSON 必须使用有效 UTF-8。', 400); }
  let i = 0;
  const invalid = () => fail('INVALID_REQUEST', `JSON 格式无效（位置 ${i}）。`, 400);
  const space = () => { while (/[\x20\x09\x0a\x0d]/.test(text[i] || '\uffff')) i++; };
  const string = () => {
    const start = i++;
    while (i < text.length) {
      if (text[i] === '"') { i++; try { const s = JSON.parse(text.slice(start, i)); normalizeText(s); return s; } catch (e) { if (e instanceof ApiError) throw e; invalid(); } }
      if (text[i] === '\\') i += 2; else i++;
    }
    invalid();
  };
  const value = depth => {
    if (depth > maxDepth) fail('INVALID_REQUEST', 'JSON 嵌套超过 16 层。', 400);
    space(); const c = text[i];
    if (c === '"') return string();
    if (c === '{') {
      i++; space(); const out = Object.create(null), keys = new Set();
      if (text[i] === '}') { i++; return out; }
      while (true) {
        space(); if (text[i] !== '"') invalid(); const key = string();
        if (keys.has(key)) fail('INVALID_REQUEST', 'JSON 包含重复字段。', 400);
        keys.add(key); space(); if (text[i++] !== ':') invalid(); out[key] = value(depth + 1); space();
        if (text[i] === '}') { i++; return out; }
        if (text[i++] !== ',') invalid();
      }
    }
    if (c === '[') {
      i++; space(); const out = []; if (text[i] === ']') { i++; return out; }
      while (true) { out.push(value(depth + 1)); space(); if (text[i] === ']') { i++; return out; } if (text[i++] !== ',') invalid(); }
    }
    for (const [word, parsed] of [['true', true], ['false', false], ['null', null]]) if (text.startsWith(word, i)) { i += word.length; return parsed; }
    const match = /^-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?/.exec(text.slice(i));
    if (!match) invalid(); i += match[0].length;
    const n = Number(match[0]); if (!Number.isSafeInteger(n)) fail('INVALID_REQUEST', 'JSON 数值必须为安全整数。', 400);
    return n;
  };
  const result = value(0); space(); if (i !== text.length) invalid(); return result;
}
