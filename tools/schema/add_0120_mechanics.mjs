// One-off migration for 0.12.0 (issues #108 #126 #128 #131 #132 #133). Idempotent.
//  - value sources friendly_kredit_slots / enemy_kredit_slots (#132)
//  - unit triggers own_counter_returned (#128), own_kredit_slot_gained / enemy_kredit_slot_gained (#132)
//  - modify_hand_cost: selection event_card and cost_set 0-20 as an alternative to cost_delta (#128)
//  - selected_units (from select_units) as the target of damage, heal, modify_stats, grant_keyword, remove_keyword,
//    suppress and return_to_hand (#133)
//  - new ops: forbid_play (#126), modify_play_cost (#131, auras only), remove_abilities (#108)
// node tools/schema/add_0120_mechanics.mjs
import {readFileSync, writeFileSync} from 'node:fs';
import {dirname, join} from 'node:path';
import {fileURLToPath} from 'node:url';

const DOCS = join(dirname(fileURLToPath(import.meta.url)), '..', '..', 'docs', 'cards');
const clone = value => structuredClone(value);
const NEW_STATS = ['friendly_kredit_slots', 'enemy_kredit_slots'];
const UNIT_TRIGGERS = ['own_counter_returned', 'own_kredit_slot_gained', 'enemy_kredit_slot_gained'];
const SELECTED_OPS = ['damage', 'heal', 'modify_stats', 'grant_keyword', 'remove_keyword', 'suppress', 'return_to_hand'];
const MUTABLE_TRIGGERS = ['on_death', 'on_leave', 'on_attack', 'after_attack', 'on_attacked', 'after_attacked', 'on_damaged', 'on_kill', 'after_move', 'after_action', 'own_turn_start', 'own_turn_end'];
const KINDS = {type: 'array', items: {enum: ['unit', 'order', 'counter', 'field']}, minItems: 1, maxItems: 4, uniqueItems: true};

function eachArray(value, visit) {
  if (Array.isArray(value)) { visit(value); value.forEach(item => eachArray(item, visit)); }
  else if (value && typeof value === 'object') for (const key of Object.keys(value)) eachArray(value[key], visit);
}
function eachObject(value, visit) {
  if (Array.isArray(value)) value.forEach(item => eachObject(item, visit));
  else if (value && typeof value === 'object') { visit(value); for (const key of Object.keys(value)) eachObject(value[key], visit); }
}
const opOf = entry => entry?.properties?.op?.const;
const hasOp = (list, op) => list.some(entry => opOf(entry) === op);

function migrate(schema) {
  const counts = {stats: 0, triggers: 0, hand_cost: 0, selected: 0, ops: 0};
  let handFilter = null, keywordTargets = null;
  eachObject(schema, node => {
    if (!handFilter && opOf(node) === 'modify_hand_cost') handFilter = node.properties.filter;
    if (!keywordTargets && opOf(node) === 'remove_keyword') keywordTargets = node.properties.target;
  });
  // keyword.schema.json has a smaller effect set; ops whose fields are copied from missing ones are left out there.
  const targets = keywordTargets ? clone(keywordTargets) : null;
  if (targets && !targets.enum.includes('selected_units')) targets.enum.push('selected_units');
  const OPS = {
    forbid_play: {type: 'object', additionalProperties: false, properties: {op: {const: 'forbid_play'}, player: {enum: ['opponent', 'owner']}, card_kinds: clone(KINDS)}, required: ['op', 'player', 'card_kinds']},
    modify_play_cost: handFilter && {type: 'object', additionalProperties: false, properties: {op: {const: 'modify_play_cost'}, cost_delta: {type: 'integer', minimum: -5, maximum: 5}, filter: clone(handFilter), first_each_turn: {const: true}}, required: ['op', 'cost_delta']},
    remove_abilities: targets && {type: 'object', additionalProperties: false, properties: {op: {const: 'remove_abilities'}, target: targets, trigger: {enum: MUTABLE_TRIGGERS}, duration: {enum: ['battle', 'end_of_turn']}}, required: ['op', 'target', 'trigger', 'duration']},
  };
  eachObject(schema, node => {
    if (Array.isArray(node?.enum) && node.enum.includes('friendly_turn_number')) for (const stat of NEW_STATS) if (!node.enum.includes(stat)) { node.enum.push(stat); counts.stats++; }
    if (Array.isArray(node?.enum) && node.enum.includes('on_activate') && node.enum.includes('on_keyword_lost')) for (const trigger of UNIT_TRIGGERS) if (!node.enum.includes(trigger)) { node.enum.push(trigger); counts.triggers++; }
    const op = opOf(node);
    if (op === 'modify_hand_cost') {
      if (!node.properties.selection.enum.includes('event_card')) { node.properties.selection.enum.push('event_card'); counts.hand_cost++; }
      if (!node.properties.cost_set) { node.properties.cost_set = {type: 'integer', minimum: 0, maximum: 20}; node.required = node.required.filter(key => key !== 'cost_delta'); counts.hand_cost++; }
    }
    if (SELECTED_OPS.includes(op) && Array.isArray(node.properties.target?.enum) && !node.properties.target.enum.includes('selected_units')) { node.properties.target.enum.push('selected_units'); counts.selected++; }
  });
  eachArray(schema, list => {
    if (!hasOp(list, 'retreat') || !hasOp(list, 'fight')) return;
    for (const [op, entry] of Object.entries(OPS)) if (entry && !hasOp(list, op)) { list.push(clone(entry)); counts.ops++; }
  });
  return counts;
}

for (const file of ['card.schema.json', 'keyword.schema.json']) {
  const path = join(DOCS, file), raw = readFileSync(path, 'utf8');
  const schema = JSON.parse(raw);
  const counts = migrate(schema);
  const indent = raw.startsWith('{\n  ') || raw.startsWith('{\r\n  ') ? 2 : undefined;
  writeFileSync(path, JSON.stringify(schema, null, indent) + (raw.endsWith('\n') ? '\n' : ''));
  console.log(file, JSON.stringify(counts));
}
