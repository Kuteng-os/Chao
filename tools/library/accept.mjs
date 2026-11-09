// Turns a checked submission into catalog records. Shared by add_card and the DSH plugin's publish step.
import {createHash, randomUUID} from 'node:crypto';
import {publicCard} from '../../server/src/cloud_catalog.js';
import {latestCards} from '../../server/src/derived_cards.js';
import {rulesText} from '../../server/src/validation.js';
import {registry} from './catalog_io.mjs';
import {pngSize} from './submission.mjs';

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
