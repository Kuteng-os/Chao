// Assembles the read-only card viewer for GitHub Pages: node tools/site/build_viewer.mjs [output-dir]
// Only viewer.html and the files it actually reaches are published, so the old workshop and its server code stay out.
import {mkdirSync, readFileSync, rmSync, writeFileSync} from 'node:fs';
import {dirname, join, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..', '..');
const WEB = join(ROOT, 'web');
const output = resolve(process.argv[2] ?? join(ROOT, 'build', 'site'));

const html = readFileSync(join(WEB, 'viewer.html'), 'utf8');
const pending = [...html.matchAll(/(?:href|src)="([\w.-]+\.(?:css|mjs))"/g)].map(match => match[1]);
const files = new Set();
while (pending.length) {
  const file = pending.pop();
  if (files.has(file)) continue;
  files.add(file);
  if (file.endsWith('.mjs')) {
    const source = readFileSync(join(WEB, file), 'utf8');
    pending.push(...[...source.matchAll(/from\s*['"]\.\/([\w.-]+)['"]/g)].map(match => match[1]));
  }
}

rmSync(output, {recursive: true, force: true});
mkdirSync(output, {recursive: true});
writeFileSync(join(output, 'index.html'), html);
for (const file of files) writeFileSync(join(output, file), readFileSync(join(WEB, file)));
console.log(`viewer: ${files.size + 1} files in ${output}`);
