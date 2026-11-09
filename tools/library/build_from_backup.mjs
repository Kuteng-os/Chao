// One-time bootstrap: node tools/library/build_from_backup.mjs <extracted-backup-dir>
// Projects the last server backup through the original public-catalog code so hashes stay valid.
import {readFileSync, mkdirSync, copyFileSync, writeFileSync, existsSync} from 'node:fs';
import {join} from 'node:path';
import {CloudCatalog} from '../../server/src/cloud_catalog.js';
import {Factions} from '../../server/src/factions.js';
import {Emotes} from '../../server/src/emotes.js';
import {registryEntries} from '../../server/src/validation.js';
import {archived} from '../../server/src/content_lifecycle.js';
import {seriesCatalog} from '../../server/src/card_series.js';
import {DATA, FORMAT, saveCatalog} from './catalog_io.mjs';

const backup = process.argv[2];
if (!backup) throw new Error('Usage: build_from_backup.mjs <extracted-backup-dir>');
const state = JSON.parse(readFileSync(join(backup, 'library.json'), 'utf8'));
const store = {state};

const {cards, lifecycle} = new CloudCatalog({store}).cards(null);
const keywords = registryEntries(state.keywords).map(entry => ({definition_hash: entry.definition_hash, definition: structuredClone(entry.definition), archived: archived(state, 'keywords', entry.definition.id), can_manage: false, owned_by_me: false, can_edit: false}));
const factions = new Factions({store}).list(null).factions;
const emotes = Emotes.prototype.list.call({store}).emotes.map(({owner_id, ...entry}) => entry);

const media = {art: new Set(), sounds: new Set(), emotes: new Set(emotes.map(entry => entry.asset_id))};
for (const card of cards) {
  if (card.art?.id) media.art.add(card.art.id);
  for (const art of Object.values(card.token_art ?? {})) if (art?.id) media.art.add(art.id);
  for (const owner of [card.definition, ...(card.definition.tokens ?? [])]) {
    const {sounds = {}, background, music} = owner.media ?? {};
    if (background) media.art.add(background);
    for (const id of [...Object.values(sounds), ...(music ? [music] : [])]) media.sounds.add(id);
  }
}
for (const faction of factions) for (const id of [faction.icon_id, faction.background_id]) if (id) media.art.add(id);

const sources = {art: 'png', sounds: 'wav', emotes: 'png'};
for (const [kind, ids] of Object.entries(media)) {
  mkdirSync(join(DATA, kind), {recursive: true});
  for (const id of ids) {
    const source = join(backup, kind, `${id}.${sources[kind]}`);
    if (!existsSync(source)) throw new Error(`Backup is missing ${kind}/${id}`);
    // .bin keeps the exact bytes: Godot would otherwise re-import PNG/WAV and break the content hash.
    copyFileSync(source, join(DATA, kind, `${id}.bin`));
  }
}
writeFileSync(join(DATA, 'emotes.json'), JSON.stringify({emotes}));
const saved = saveCatalog({format: FORMAT, health: {card_series: seriesCatalog(state)}, keywords, factions, lifecycle, cards});
console.log(JSON.stringify({cards: saved.cards.length, keywords: keywords.length, factions: factions.length, emotes: emotes.length, art: media.art.size, sounds: media.sounds.size}));
