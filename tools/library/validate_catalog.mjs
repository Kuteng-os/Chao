// Re-derives every bundled card and verifies all referenced media before a release.
import {existsSync, readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {join} from 'node:path';
import {compileCard} from '../../server/src/validation.js';
import {DATA, fingerprints, loadCatalog, registry} from './catalog_io.mjs';

const catalog = loadCatalog(), problems = [], keywords = registry(catalog);
if (JSON.stringify(fingerprints(catalog)) !== JSON.stringify(catalog.fingerprints)) problems.push('fingerprints 与卡库内容不一致。');
const media = (kind, id, owner) => {
  const path = join(DATA, kind, `${id}.bin`);
  if (!existsSync(path)) problems.push(`${owner}: 缺少 ${kind}/${id}`);
  else if (createHash('sha256').update(readFileSync(path)).digest('hex') !== id) problems.push(`${owner}: ${kind}/${id} 哈希不符`);
};
for (const card of catalog.cards) {
  const name = `${card.definition.name} (${card.card_id})`;
  try {
    if (compileCard(card.definition, keywords).definition_hash !== card.definition_hash) problems.push(`${name}: 定义哈希不符`);
  } catch (error) {
    problems.push(`${name}: ${error.message}`);
  }
  if (card.art?.id) media('art', card.art.id, name);
  for (const art of Object.values(card.token_art ?? {})) if (art?.id) media('art', art.id, name);
}
for (const faction of catalog.factions) for (const id of [faction.icon_id, faction.background_id]) if (id) media('art', id, faction.name);
console.log(JSON.stringify({cards: catalog.cards.length, problems: problems.length}));
for (const problem of problems) console.error(problem);
process.exit(problems.length ? 1 : 0);
