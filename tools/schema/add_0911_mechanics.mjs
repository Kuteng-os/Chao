// One-off migration for 0.9.11 (issues #26-#38): remove_keyword and forbid_deploy effects, the keyword_param value
// source (also accepted by set_stacks.amount), pin up to 5 turns, immediate temporary removal, per_stack operation
// cost changes, and keyword filters on modify_hand_cost. Idempotent.
// node tools/schema/add_0911_mechanics.mjs
import {readFileSync, writeFileSync} from 'node:fs';
import {dirname, join} from 'node:path';
import {fileURLToPath} from 'node:url';

const DOCS = join(dirname(fileURLToPath(import.meta.url)), '..', '..', 'docs', 'cards');
const clone = value => structuredClone(value);
const KEYWORD_ID = {type: 'string', pattern: '^[a-z][a-z0-9_]*[.][a-z][a-z0-9_]*$', maxLength: 96};
const KEYWORD_PARAM = {type: 'object', additionalProperties: false, properties: {keyword_param: {type: 'object', additionalProperties: false, properties: {target: {enum: ['self', 'chosen', 'trigger_unit', 'creator', 'attack_target', 'effect_target']}, keyword_id: KEYWORD_ID, param: {type: 'string', pattern: '^[a-z][a-z0-9_]{0,23}$'}}, required: ['target', 'keyword_id', 'param']}}, required: ['keyword_param']};
const PER_STACK = {type: 'object', additionalProperties: false, properties: {target: {enum: ['self', 'chosen', 'trigger_unit', 'creator', 'attack_target']}, stack: {type: 'string', minLength: 1, maxLength: 32}}, required: ['target', 'stack']};
const FORBID = {type: 'object', additionalProperties: false, properties: {op: {const: 'forbid_deploy'}, player: {enum: ['opponent', 'owner']}}, required: ['op', 'player']};

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
const isKeywordParam = entry => entry?.required?.includes?.('keyword_param');

function migrate(schema) {
  const counts = {keyword_param: 0, remove_keyword: 0, forbid_deploy: 0, pin: 0, immediate: 0, per_stack: 0, hand_filter: 0, set_stacks: 0};
  eachArray(schema, list => {
    if (list.some(entry => entry?.required?.includes?.('unit_stat')) && !list.some(isKeywordParam)) { list.push(clone(KEYWORD_PARAM)); counts.keyword_param++; }
    const grant = list.find(entry => opOf(entry) === 'grant_keyword');
    if (grant && !hasOp(list, 'remove_keyword')) {
      const remove = clone(grant);
      remove.properties = {op: {const: 'remove_keyword'}, target: remove.properties.target, keyword_id: remove.properties.keyword_id, ...(remove.properties.unit_filter ? {unit_filter: remove.properties.unit_filter} : {})};
      remove.required = ['op', 'target', 'keyword_id'];
      list.push(remove);
      counts.remove_keyword++;
    }
    if (hasOp(list, 'gain_kredits') && !hasOp(list, 'forbid_deploy')) { list.push(clone(FORBID)); counts.forbid_deploy++; }
  });
  eachObject(schema, node => {
    const op = node?.properties?.op?.const;
    if (op === 'pin' && node.properties.turns?.maximum === 3) { node.properties.turns.maximum = 5; counts.pin++; }
    if (op === 'temporarily_remove' && Array.isArray(node.properties.return_when?.enum) && !node.properties.return_when.enum.includes('immediate')) { node.properties.return_when.enum.push('immediate'); counts.immediate++; }
    if (op === 'modify_operation_cost' && !node.properties.per_stack) { node.properties.per_stack = clone(PER_STACK); counts.per_stack++; }
    if (op === 'modify_hand_cost' && node.properties.filter?.properties && !node.properties.filter.properties.keyword_id) {
      node.properties.filter.properties.keyword_id = clone(KEYWORD_ID);
      node.properties.filter.properties.without_keyword = clone(KEYWORD_ID);
      counts.hand_filter++;
    }
    if (op === 'set_stacks' && node.properties.amount) {
      const amount = node.properties.amount;
      if (Array.isArray(amount.oneOf)) { if (!amount.oneOf.some(isKeywordParam)) { amount.oneOf.push(clone(KEYWORD_PARAM)); counts.set_stacks++; } }
      else { node.properties.amount = {oneOf: [amount, clone(KEYWORD_PARAM)]}; counts.set_stacks++; }
    }
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
