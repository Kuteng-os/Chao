// One-off migration for 0.11.0 (issues #49 #52 #55 #66 #67 #68 #80 #85 #90 #91 #102). Idempotent.
//  - cost, cost_override.value, min_cost and max_cost up to 20 (#66)
//  - value sources: friendly/enemy draws and units played this game, hand_shortfall (#67 #80 #85)
//  - draw.amount and gain_hq_defense.amount take value sources (#67 #85); draw.filter gains faction, sins, classes,
//    cost range and keyword (#102)
//  - cost_reduction.per_draw: cheaper by each card drawn while this card is in hand (#67)
//  - summon picks one of several tokens at random (token_ids) and can enter beside the HQ (#80 #90)
//  - fight from the unit just summoned (#90)
//  - new ops: swap_position, move_unit (#91), redirect_attack (#90), grant_action (#55)
//  - unit triggers own_counter_triggered, any_counter_triggered (#52) and unit_attack_changed with event_filter (#68)
//  - counter triggers enemy_unit_acted, enemy_unit_moved_to_front, enemy_unit_ability_triggered (#49) and
//    unit_attack_changed with counter_filter (#68)
// node tools/schema/add_0110_mechanics.mjs
import {readFileSync, writeFileSync} from 'node:fs';
import {dirname, join} from 'node:path';
import {fileURLToPath} from 'node:url';

const DOCS = join(dirname(fileURLToPath(import.meta.url)), '..', '..', 'docs', 'cards');
const clone = value => structuredClone(value);
const NEW_STATS = ['friendly_draws_this_game', 'enemy_draws_this_game', 'friendly_units_played_this_game', 'enemy_units_played_this_game', 'hand_shortfall'];
const UNIT_TRIGGERS = ['own_counter_triggered', 'any_counter_triggered', 'unit_attack_changed'];
const COUNTER_TRIGGERS = ['enemy_unit_acted', 'enemy_unit_moved_to_front', 'enemy_unit_ability_triggered', 'unit_attack_changed'];
const CLASSES = {type: 'array', items: {enum: ['infantry', 'tank', 'artillery', 'fighter', 'bomber']}, minItems: 1, maxItems: 5, uniqueItems: true};
const SINS = {type: 'array', items: {enum: ['wrath', 'lust', 'sloth', 'gluttony', 'gloom', 'pride', 'envy', null]}, minItems: 1, maxItems: 8, uniqueItems: true};
const KEYWORD_ID = {type: 'string', pattern: '^[a-z][a-z0-9_]*[.][a-z][a-z0-9_]*$', maxLength: 96};
const TOKEN_ID = {type: 'string', pattern: '^[a-z][a-z0-9_]{0,31}$'};
const ATTACK_FILTER = {type: 'object', additionalProperties: false, minProperties: 1, properties: {side: {enum: ['own', 'enemy', 'any']}, row: {enum: ['front', 'support', 'any']}, direction: {enum: ['up', 'down', 'any']}}};
const OPS = {
  swap_position: {type: 'object', additionalProperties: false, properties: {op: {const: 'swap_position'}, target: {enum: ['chosen', 'trigger_unit', 'random_friendly_unit']}, with: {const: 'self'}}, required: ['op', 'target', 'with']},
  move_unit: {type: 'object', additionalProperties: false, properties: {op: {const: 'move_unit'}, target: {enum: ['self', 'chosen', 'trigger_unit', 'summoned']}, row: {enum: ['front', 'support']}}, required: ['op', 'target', 'row']},
  redirect_attack: {type: 'object', additionalProperties: false, properties: {op: {const: 'redirect_attack'}, target: {enum: ['summoned', 'random_friendly_unit']}}, required: ['op', 'target']},
  grant_action: {type: 'object', additionalProperties: false, properties: {op: {const: 'grant_action'}, target: {enum: ['self', 'trigger_unit', 'summoned']}, action: {enum: ['attack', 'move']}, attack_target: {enum: ['trigger_unit', 'enemy_hq', 'random_enemy_unit', 'random_enemy_target']}}, required: ['op', 'target', 'action']},
};

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
const isValueSource = node => Array.isArray(node?.oneOf) && node.oneOf.some(entry => entry?.required?.includes?.('stat')) && node.oneOf.some(entry => entry?.type === 'integer');

function migrate(schema) {
  const counts = {cost: 0, stats: 0, draw: 0, hq_defense: 0, per_draw: 0, summon: 0, fight: 0, ops: 0, triggers: 0, counters: 0, filters: 0};
  // A value source to copy: damage.amount is a oneOf of an integer and every value source.
  let valueSource = null;
  eachObject(schema, node => { if (!valueSource && opOf(node) === 'damage' && isValueSource(node.properties.amount)) valueSource = node.properties.amount; });
  if (!valueSource) throw new Error('damage.amount value source not found');
  eachObject(schema, node => {
    const props = node?.properties;
    if (props) {
      for (const key of ['cost', 'min_cost', 'max_cost']) if (props[key]?.maximum === 12) { props[key].maximum = 20; counts.cost++; }
      if (props.cost_override?.properties?.value?.maximum === 12) { props.cost_override.properties.value.maximum = 20; counts.cost++; }
    }
    if (Array.isArray(node?.enum) && node.enum.includes('friendly_turn_number')) for (const stat of NEW_STATS) if (!node.enum.includes(stat)) { node.enum.push(stat); counts.stats++; }
    if (Array.isArray(node?.enum) && node.enum.includes('on_activate') && node.enum.includes('on_keyword_lost')) for (const trigger of UNIT_TRIGGERS) if (!node.enum.includes(trigger)) { node.enum.push(trigger); counts.triggers++; }
    if (Array.isArray(node?.enum) && node.enum.includes('enemy_hq_attacked') && node.enum.includes('enemy_order_played')) for (const trigger of COUNTER_TRIGGERS) if (!node.enum.includes(trigger)) { node.enum.push(trigger); counts.counters++; }
    const op = opOf(node);
    if (op === 'draw') {
      if (node.properties.amount?.type === 'integer') { const amount = clone(valueSource); amount.oneOf = amount.oneOf.map(entry => entry.type === 'integer' ? {type: 'integer', minimum: 1, maximum: 10} : entry); node.properties.amount = amount; counts.draw++; }
      const filter = node.properties.filter?.properties;
      if (filter && !filter.faction_id) { Object.assign(filter, {unit_classes: clone(CLASSES), faction_id: {type: 'string', pattern: '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'}, sins: clone(SINS), min_cost: {type: 'integer', minimum: 0, maximum: 20}, max_cost: {type: 'integer', minimum: 0, maximum: 20}, keyword_id: clone(KEYWORD_ID)}); counts.draw++; }
    }
    if (op === 'gain_hq_defense' && node.properties.amount?.type === 'integer') { node.properties.amount = clone(valueSource); counts.hq_defense++; }
    if (op === 'summon' && !node.properties.token_ids) {
      node.properties.token_ids = {type: 'array', items: clone(TOKEN_ID), minItems: 2, maxItems: 4, uniqueItems: true};
      node.properties.position = {enum: ['end', 'beside_hq']};
      node.required = node.required.filter(key => key !== 'token_id');
      counts.summon++;
    }
    if (op === 'fight' && !node.properties.source) { node.properties.source = {enum: ['self', 'summoned']}; counts.fight++; }
    if (props?.per_unit && Array.isArray(node.required) && node.required.includes('per_unit') && node.required.includes('amount')) {
      props.per_draw = {const: true};
      node.required = ['amount'];
      counts.per_draw++;
    }
    if (props?.trigger?.enum?.includes?.('on_activate') && !props.event_filter) { props.event_filter = clone(ATTACK_FILTER); counts.filters++; }
    if (props?.counter_trigger && !props.counter_filter) { props.counter_filter = {oneOf: [clone(ATTACK_FILTER), {type: 'null'}]}; counts.filters++; }
  });
  eachArray(schema, list => {
    if (!hasOp(list, 'retreat') || !hasOp(list, 'fight')) return;
    for (const [op, entry] of Object.entries(OPS)) if (!hasOp(list, op)) { list.push(clone(entry)); counts.ops++; }
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
