// One-off migration for 0.9.10: adds the max_unit_stat amount, the shuffle_into_deck and tax_opponent_plays
// effects, template parameters in compare premises, and the parameterised core.revive builtin to both schemas.
// The schemas inline every definition many times, so this edits them structurally rather than by hand.
// node tools/schema/add_0910_mechanics.mjs   (idempotent)
import {readFileSync, writeFileSync} from 'node:fs';
import {dirname, join} from 'node:path';
import {fileURLToPath} from 'node:url';

const DOCS = join(dirname(fileURLToPath(import.meta.url)), '..', '..', 'docs', 'cards');
const clone = value => structuredClone(value);
const MAX_UNIT_STAT = {type: 'object', additionalProperties: false, properties: {max_unit_stat: {type: 'object', additionalProperties: false, properties: {side: {enum: ['ally', 'enemy']}, stat: {enum: ['attack', 'health']}}, required: ['side', 'stat']}}, required: ['max_unit_stat']};
const TAX = {type: 'object', additionalProperties: false, properties: {op: {const: 'tax_opponent_plays'}, card_kind: {enum: ['unit', 'order', 'any']}, amount: {type: 'integer', minimum: 1, maximum: 5}, refund_per: {type: 'integer', minimum: 1, maximum: 5}}, required: ['op', 'card_kind', 'amount']};

/** Visits every array so new alternatives can be appended beside the entries they extend. */
function eachArray(value, visit) {
  if (Array.isArray(value)) { visit(value); value.forEach(item => eachArray(item, visit)); }
  else if (value && typeof value === 'object') for (const key of Object.keys(value)) eachArray(value[key], visit);
}
const opOf = entry => entry?.properties?.op?.const;
const hasOp = (list, op) => list.some(entry => opOf(entry) === op);

function migrate(schema, isKeyword) {
  const counts = {max_unit_stat: 0, shuffle_into_deck: 0, tax_opponent_plays: 0};
  eachArray(schema, list => {
    if (list.some(entry => entry?.required?.includes?.('unit_stat')) && !list.some(entry => entry?.required?.includes?.('max_unit_stat'))) {
      list.push(clone(MAX_UNIT_STAT));
      counts.max_unit_stat++;
    }
    const remove = list.find(entry => opOf(entry) === 'remove');
    if (remove && !hasOp(list, 'shuffle_into_deck')) {
      const shuffle = clone(remove);
      shuffle.properties.op = {const: 'shuffle_into_deck'};
      shuffle.properties.deck = {enum: ['caster', 'owner']};
      shuffle.properties.position = {enum: ['random', 'top', 'bottom']};
      list.push(shuffle);
      counts.shuffle_into_deck++;
    }
    if (hasOp(list, 'gain_kredits') && !hasOp(list, 'tax_opponent_plays')) {
      list.push(clone(TAX));
      counts.tax_opponent_plays++;
    }
  });
  if (isKeyword) {
    const param = schema.properties.implementation.oneOf[1].properties.abilities.items.properties.effects.items.oneOf[0].properties.amount.oneOf[1];
    if (!param?.required?.includes('param')) throw new Error('template parameter shape not found');
    const compare = schema.definitions.premise.oneOf[0].properties;
    for (const side of ['left', 'right']) if (!compare[side].oneOf.some(entry => entry?.required?.includes?.('param'))) compare[side].oneOf.push(clone(param));
    // A builtin's parameters must equal its registered definition; both validators compare them exactly.
    schema.allOf = (schema.allOf ?? []).filter(rule => rule?.then?.properties?.parameters?.maxProperties !== 0);
    if (!schema.allOf.length) delete schema.allOf;
    const builtins = schema.properties.implementation.oneOf[0].properties.builtin_id.enum;
    if (!builtins.includes('core.revive.v1')) builtins.push('core.revive.v1');
  }
  return counts;
}

for (const [file, isKeyword] of [['card.schema.json', false], ['keyword.schema.json', true]]) {
  const path = join(DOCS, file), raw = readFileSync(path, 'utf8');
  const schema = JSON.parse(raw);
  const counts = migrate(schema, isKeyword);
  const indent = raw.startsWith('{\n  ') || raw.startsWith('{\r\n  ') ? 2 : undefined;
  writeFileSync(path, JSON.stringify(schema, null, indent) + (raw.endsWith('\n') ? '\n' : ''));
  console.log(file, JSON.stringify(counts));
}
