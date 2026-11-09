import {hash, fail} from './codec.js';

const DIGEST = /^[0-9a-f]{64}$/;
const ID = /^[0-9a-f-]{36}$/;
// Fingerprints describe public projections, including artwork, author and archive edits.
// Client-owned manifests survive service restarts; unchanged definitions are not sent again.
export function catalogUpdates(known, {cards, keywords, factions, lifecycle}) {
  if (!known || typeof known !== 'object' || Array.isArray(known) || Object.keys(known).some(k => !['cards','keywords','factions','lifecycle'].includes(k))) fail('INVALID_REQUEST','卡库同步清单无效。',400);
  const previous = known.cards ?? {};
  if (!previous || typeof previous !== 'object' || Array.isArray(previous) || Object.keys(previous).length > 20000 || Object.entries(previous).some(([id,digest]) => !ID.test(id) || typeof digest !== 'string' || !DIGEST.test(digest))) fail('INVALID_REQUEST','卡牌同步清单无效。',400);
  for (const key of ['keywords','factions','lifecycle']) if (known[key] !== undefined && (typeof known[key] !== 'string' || (known[key] !== '' && !DIGEST.test(known[key])))) fail('INVALID_REQUEST','卡库同步版本无效。',400);
  const fingerprints = {cards:{},keywords:hash(keywords),factions:hash(factions),lifecycle:hash(lifecycle)};
  const changed = [];
  for (const card of cards) {
    const digest = hash(card);
    fingerprints.cards[card.card_id] = digest;
    if (previous[card.card_id] !== digest) changed.push(card);
  }
  return {
    fingerprints, cards:changed,
    removed:Object.keys(previous).filter(id => !Object.hasOwn(fingerprints.cards,id)),
    keywords:known.keywords === fingerprints.keywords ? null : keywords,
    factions:known.factions === fingerprints.factions ? null : factions,
    lifecycle:known.lifecycle === fingerprints.lifecycle ? null : lifecycle,
  };
}
