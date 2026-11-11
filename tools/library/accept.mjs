// Turns checked submissions into catalog records. Shared by add_card, sync_inbox and the DSH plugin's publish step.
import {createHash, randomUUID} from 'node:crypto';
import {readFileSync} from 'node:fs';
import {publicCard} from '../../server/src/cloud_catalog.js';
import {latestCards} from '../../server/src/derived_cards.js';
import {rulesText} from '../../server/src/validation.js';
import {registry} from './catalog_io.mjs';
import {checkPack, checkSubmission, pngSize} from './submission.mjs';

/**
 * Returns the next catalog plus what changed. A revision keeps the card's id, pack, author and registration date,
 * and rebuilds its derived token cards so they cannot go stale against the new definition.
 */
export function acceptSubmission(catalog, {compiled, submission, artBytes = null, replaceId = null, series = null}) {
  const previous = replaceId ? catalog.cards.find(card => card.card_id === replaceId) : null;
  if (replaceId && !previous) throw new Error(`卡库中没有 ${replaceId}。`);
  if (previous?.derived_from) throw new Error(`衍生卡不能单独修改，请修改来源卡《${previous.derived_from.name}》。`);

  let art = previous?.art;
  if (artBytes) art = {id: createHash('sha256').update(artBytes).digest('hex'), ...pngSize(artBytes)};
  const author = submission.author.trim(), owner = `github:${author}`, keywords = registry(catalog);
  const stored = {
    card_id: previous?.card_id ?? randomUUID(),
    revision: (previous?.revision ?? 0) + 1,
    series: series ?? previous?.series ?? catalog.health.card_series.current,
    ...compiled,
    rules_text: rulesText(compiled.definition),
    interpreter_version: 'interpreter-1',
    compiler_version: 'card-compiler-1',
    provenance: {source_kind: 'github_submission'},
    owner_id: owner,
    created_at: previous?.created_at ?? new Date().toISOString(),
    ...(art ? {art} : {}),
    token_art: previous?.token_art ?? {},
  };
  const toPublic = card => ({
    ...publicCard(card, null, false, {keywords, identities: {[owner]: {display_name: author}}, content_lifecycle: catalog.lifecycle}),
    ...(previous?.author ? {author: previous.author} : {}),
  });
  const records = (previous ? latestCards({cards: {[stored.card_id]: [stored]}, keywords}) : [stored]).map(toPublic);
  const current = new Set(records.map(card => card.card_id));
  const isDerivedFromThis = card => card.derived_from?.card_id === stored.card_id;
  // A token the new revision dropped stays resolvable for existing decks, but no longer appears as live content.
  const retired = catalog.cards
    .filter(card => isDerivedFromThis(card) && !current.has(card.card_id))
    .map(card => ({...card, archived: true, derived_from: {...card.derived_from, retired: true}}));
  const untouched = catalog.cards.filter(card => card.card_id !== stored.card_id && !isDerivedFromThis(card));
  return {catalog: {...catalog, cards: [...untouched, ...records, ...retired]}, record: records[0], art: artBytes ? art : null, previous};
}

/** The reviewer-facing description of a revision, or null for a new card. */
export function replacedSummary(previous) {
  return previous ? {card_id: previous.card_id, name: previous.definition.name, revision: previous.revision, author: previous.author?.name ?? '', rules_text: previous.rules_text ?? ''} : null;
}

/**
 * Accepts one inbox file, a card pack or a legacy single card, against the given catalog without writing anything.
 * Returns {errors} or {catalog, results: [{record, art, artBytes, artPath, previous}], files, name, author}.
 * A pack is all-or-nothing: one failing card rejects the whole pack.
 */
export function acceptFile(path, catalog, {skipMedia = false, series = null, replaceId = null} = {}) {
  if (path.endsWith('.pack.json')) {
    const checked = checkPack(path, catalog, {skipMedia});
    if (checked.errors.length) return {errors: checked.errors};
    let next = catalog;
    const results = [];
    for (const card of checked.cards) {
      const artBytes = card.artPath ? readFileSync(card.artPath) : null;
      const accepted = acceptSubmission(next, {compiled: card.compiled, submission: {author: checked.pack.author}, artBytes, replaceId: card.entry.replaces?.card_id ?? null, series});
      next = accepted.catalog;
      results.push({...accepted, artBytes, artPath: card.artPath});
    }
    return {errors: [], catalog: next, results, files: [path, ...results.map(result => result.artPath).filter(Boolean)], name: checked.pack.name, author: checked.pack.author.trim()};
  }
  const checked = checkSubmission(path, catalog, {skipMedia});
  if (checked.errors.length) return {errors: checked.errors};
  const artBytes = checked.artPath ? readFileSync(checked.artPath) : null;
  const accepted = acceptSubmission(catalog, {compiled: checked.compiled, submission: checked.submission, artBytes, replaceId: replaceId ?? checked.submission.replaces?.card_id ?? null, series});
  return {errors: [], catalog: accepted.catalog, results: [{...accepted, artBytes, artPath: checked.artPath}], files: [path, ...(checked.artPath ? [checked.artPath] : [])], name: accepted.record.definition.name, author: checked.submission.author.trim()};
}
