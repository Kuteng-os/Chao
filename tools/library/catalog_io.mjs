// Shared helpers for the bundled catalog (data/catalog.json), the game's only card source.
import {readFileSync, writeFileSync, existsSync} from 'node:fs';
import {dirname, join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {hash} from '../../server/src/codec.js';

export const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
export const DATA = join(ROOT, 'data');
export const CATALOG_PATH = join(DATA, 'catalog.json');
export const FORMAT = 'chao-bundled-catalog-v1';

export function fingerprints({cards, keywords, factions, lifecycle}) {
  return {cards: Object.fromEntries(cards.map(card => [card.card_id, hash(card)])), keywords: hash(keywords), factions: hash(factions), lifecycle: hash(lifecycle)};
}

export function loadCatalog() {
  if (!existsSync(CATALOG_PATH)) throw new Error(`Missing ${CATALOG_PATH}`);
  const catalog = JSON.parse(readFileSync(CATALOG_PATH, 'utf8'));
  if (catalog.format !== FORMAT) throw new Error('Unexpected catalog format.');
  return catalog;
}

/** One card per line keeps Git diffs reviewable when a single card changes. */
export function catalogText(catalog) {
  catalog.cards.sort((a, b) => a.card_id.localeCompare(b.card_id));
  // Clients only accept a higher version, so every write must advance it.
  const version = (catalog.catalog_version ?? 0) + 1;
  const next = {...catalog, catalog_version: version, fingerprints: fingerprints(catalog)};
  const {cards, ...head} = next;
  const headText = JSON.stringify(head).slice(0, -1);
  return {next, version, text: `${headText},"cards":[\n${cards.map(card => JSON.stringify(card)).join(',\n')}\n]}\n`};
}

export function saveCatalog(catalog) {
  const {next, text} = catalogText(catalog);
  writeFileSync(CATALOG_PATH, text);
  return next;
}

/** Rebuilds the registry shape compileCard expects from the public keyword entries. */
export function registry(catalog) {
  return Object.fromEntries(catalog.keywords.map(entry => [`${entry.definition.id}@${entry.definition.version}`, {definition: entry.definition, definition_hash: entry.definition_hash, registry_status: 'approved'}]));
}
