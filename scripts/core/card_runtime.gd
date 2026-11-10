class_name CardRuntime
extends RefCounted
## Only declared JSON rules enter the interpreter; model text is never executable.
const Contracts = preload("res://scripts/core/contracts.gd")
const UnicodeData = preload("res://scripts/core/unicode_data.gd")
const StrictJson = preload("res://scripts/core/strict_json.gd")
static var _unicode: Dictionary = {}
static var _card_schema: Dictionary = {}
static var _keyword_schema: Dictionary = {}

static func parse_json(text: String, max_bytes: int = 32768) -> Dictionary:
	return StrictJson.new().parse(text, max_bytes)

static func builtin_keywords() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for item in JSON.parse_string(Contracts.BUILTINS_JSON):
		result.append(item)
	return result

static func keyword_name(id: String) -> String:
	var result := id
	for definition in builtin_keywords():
		if definition.id == id: result = definition.name
	return result

static func _integer(value: Variant) -> bool:
	return (typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT) and is_finite(float(value)) and abs(float(value)) <= 9007199254740991.0 and float(value) == floor(float(value))

static func _matches(value: Variant, schema: Dictionary, root: Dictionary, path: String = "") -> String:
	if schema.has("$ref"):
		return _matches(value, root.definitions[schema["$ref"].get_slice("/", 2)], root, path)
	if schema.has("const") and (typeof(value) == TYPE_BOOL) != (typeof(schema.const) == TYPE_BOOL):
		return path + ": 类型错误"
	if schema.has("const") and value != schema.const:
		return path + ": 必须为 " + str(schema.const)
	if schema.has("enum") and not value in schema.enum:
		return path + ": 未知枚举值"
	for key in ["oneOf", "anyOf"]:
		if schema.has(key):
			var successes := 0
			for choice in schema[key]:
				if _matches(value, choice, root, path).is_empty():
					successes += 1
			if successes == 0 or (key == "oneOf" and successes != 1):
				return path + ": 不符合允许的结构/操作"
	if schema.has("allOf"):
		for condition in schema.allOf:
			var error := _matches(value, condition, root, path)
			if not error.is_empty():
				return error
	if schema.has("if") and _matches(value, schema["if"], root, path).is_empty():
		var error := _matches(value, schema.get("then", {}), root, path)
		if not error.is_empty():
			return error
	var expected: String = schema.get("type", "")
	if (expected == "object" and not value is Dictionary) or (expected == "array" and not value is Array) or (expected == "string" and not value is String) or (expected == "null" and value != null) or (expected == "integer" and not _integer(value)):
		return path + ": 字段类型错误，需要 " + expected
	if _integer(value):
		if value < schema.get("minimum", -9007199254740991) or value > schema.get("maximum", 9007199254740991):
			return path + ": 数值超出范围"
	if value is String:
		if value.length() < schema.get("minLength", 0) or value.length() > schema.get("maxLength", 100000):
			return path + ": 文本长度超限"
		if schema.has("pattern"):
			var regex := RegEx.new()
			regex.compile(schema.pattern)
			if regex.search(value) == null:
				return path + ": 标识格式错误"
	if value is Array:
		if value.size() < schema.get("minItems", 0) or value.size() > schema.get("maxItems", 100000):
			return path + ": 数组长度超限"
		var seen := {}
		for i in value.size():
			if schema.get("uniqueItems", false):
				var encoded := canonical(value[i])
				if seen.has(encoded):
					return path + ": 重复项"
				seen[encoded] = true
			var error := _matches(value[i], schema.get("items", {}), root, path + "/" + str(i))
			if not error.is_empty():
				return error
	if value is Dictionary:
		if value.size() < schema.get("minProperties", 0) or value.size() > schema.get("maxProperties", 100000):
			return path + ": 字段数量超限"
		for key in schema.get("required", []):
			if not value.has(key):
				return path + "/" + key + ": 缺失字段"
		for key in value:
			if not key is String:
				return path + ": 键必须为字符串"
			var properties: Dictionary = schema.get("properties", {})
			var extra: Variant = schema.get("additionalProperties", true)
			if not properties.has(key) and extra is bool and not extra:
				return path + "/" + key + ": 未知字段"
			var child: Dictionary = properties.get(key, extra if extra is Dictionary else {})
			var error := _matches(value[key], child, root, path + "/" + key)
			if error.is_empty() and schema.has("propertyNames"):
				error = _matches(key, schema.propertyNames, root, path + "/" + key)
			if not error.is_empty():
				return error
	return ""

static func _plain(value: String, multiline: bool = false) -> bool:
	for i in value.length():
		var code := value.unicode_at(i)
		if (code < 32 and not (multiline and code == 10)) or (code >= 127 and code <= 159) or (code >= 0xd800 and code <= 0xdfff):
			return false
	return true

static func _safe_json(value: Variant, depth: int = 0) -> bool:
	if depth > 16:
		return false
	if value == null or value is bool:
		return true
	if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT:
		return _integer(value)
	if value is String:
		for i in value.length():
			if value.unicode_at(i) >= 0xd800 and value.unicode_at(i) <= 0xdfff:
				return false
		return true
	if value is Array:
		for item in value:
			if not _safe_json(item, depth + 1):
				return false
		return true
	if value is Dictionary:
		for key in value:
			if not key is String or not _safe_json(value[key], depth + 1):
				return false
		return true
	return false

static func _normalized(value: Variant) -> Variant:
	if value is String:
		return normalize_text(value)
	if value is Array:
		var result := []
		for child in value:
			result.append(_normalized(child))
		return result
	if value is Dictionary:
		var result := {}
		for key in value:
			result[key] = _normalized(value[key])
		return result
	if typeof(value) == TYPE_FLOAT and _integer(value):
		return int(value)
	return value

static func _failure(message: String) -> Dictionary:
	return {"ok": false, "error": message}

static func validate_keyword(value: Dictionary) -> String:
	if not _safe_json(value) or canonical(value).to_utf8_buffer().size() > 16384:
		return "词条不是安全且有界的 JSON"
	if _keyword_schema.is_empty():
		_keyword_schema = JSON.parse_string(Contracts.KEYWORD_JSON)
	var error := _matches(value, _keyword_schema, _keyword_schema)
	if not error.is_empty():
		return error
	if not _plain(value.name) or not _plain(value.description, true):
		return "词条包含控制字符"
	for alias in value.aliases:
		if not _plain(alias):
			return "词条别名包含控制字符"
	if value.implementation.kind == "builtin":
		# Catalog JSON is parsed strictly (integers) and the builtin table loosely (floats), so compare canonical text.
		for expected in builtin_keywords():
			if expected.implementation.kind == "builtin" and value.id == expected.id and value.version == expected.version and value.implementation == expected.implementation and canonical(value.parameters) == canonical(expected.parameters):
				return ""
		return "内置词条实现必须与已实现的 ID、版本和参数固定对应"
	if value.id.begins_with("core."):
		return "模板不能占用 core 命名空间"
	if value.implementation.kind == "configurable":
		return "" if value.parameters.is_empty() else "逐卡配置词条不使用模板参数"
	var used := {}
	var total := 0
	for parameter in value.parameters.values():
		if parameter.type!="token" and parameter.minimum > parameter.maximum:
			return "词条参数范围倒置"
	var combinations := 1
	for parameter in value.parameters.values():
		if parameter.type!="token": combinations *= int(parameter.maximum)-int(parameter.minimum)+1
		if combinations>65536: return "词条参数组合最多 65536 种，请缩小范围"
	for ability in value.implementation.abilities:
		var target_error := _ability_target_error(ability)
		if not target_error.is_empty(): return target_error
		var premise_error := _premise_params(ability.get("premise",{}), value.parameters, used)
		if not premise_error.is_empty(): return premise_error
		for scoped in _scoped_effects(ability.effects,ability.trigger):
			var effect: Dictionary = scoped.effect
			var effect_trigger: String = scoped.trigger
			total += 2 if effect.has("on_kill_summon") else 1
			for key in effect:
				if effect[key] is Dictionary and effect[key].has("param"):
					var name: String = effect[key].param
					if not value.parameters.has(name):
						return "模板引用了未声明参数 " + name
					used[name] = true
					var range_spec: Dictionary = value.parameters[name]
					if key=="token_id":
						if range_spec.type!="token": return "衍生引用需要token类型参数"
						continue
					if range_spec.type=="token": return "衍生参数仅能用于token_id"
					var low := (-100 if effect.get("stack")=="heavy_armor" else -99) if effect.op == "modify_stacks" else (0 if effect.op == "set_stacks" else (-4 if key == "cost_delta" else (-5 if key in ["attack_delta", "health_delta"] else 1)))
					var high := (100 if effect.get("stack")=="heavy_armor" else 99) if effect.op in ["modify_stacks", "set_stacks"] else (4 if key == "cost_delta" else (5 if low == -5 else (10 if effect.op in ["damage", "heal"] else (4 if effect.op in ["set_attack_limit", "set_combat_damage_multiplier"] else 3))))
					if effect.op == "summon": high = 2
					if effect.op == "intel": high = 9
					if effect.op == "gain_hq_defense": high = 10
					if effect.op == "modify_kredit_slots": low = -3; high = 3
					if range_spec.minimum < low or range_spec.maximum > high:
						return "参数全集超出操作范围 " + name
			if effect.op in ["search_deck", "summon_from_deck"] and (not _plain(effect.card_name) or effect.card_name.is_empty() or effect.card_name != effect.card_name.strip_edges()):
				return "检索卡牌名称不能为空、带首尾空格或控制字符"
			if effect.op == "modify_stats":
				var attack_zero := _can_be_zero(effect.attack_delta, value.parameters)
				var health_zero := _can_be_zero(effect.health_delta, value.parameters)
				if attack_zero and health_zero:
					return "模板允许同时为零的属性修改"
			if effect.op == "modify_stacks" and _can_be_zero(effect.amount, value.parameters):
				return "层数变化不能为零"
			if effect.op == "modify_operation_cost" and effect.has("cost_delta") and _can_be_zero(effect.cost_delta, value.parameters):
				return "行动费用修改不能为零"
			if effect.op == "modify_kredit_slots" and _can_be_zero(effect.amount,value.parameters): return "资源槽变化不能为零"
			if effect.op == "fight" and ability.trigger in ["on_death","on_reveal"]: return "战斗效果需要仍在场的来源单位"
			if effect.op == "fight" and effect.target == "chosen" and ability.has("target") and ability.target.side != "enemy": return "战斗目标必须是敌方单位"
			if effect.get("target", "") == "self" and ability.trigger in ["on_death", "on_reveal"]:
				return "死亡能力不能指向 self"
			if (effect.get("target", "") == "trigger_unit" and not effect_trigger in ["on_reveal","own_unit_deployed","next_own_unit_deployed","enemy_unit_deployed","after_attacked","own_unit_moved","enemy_unit_moved","on_kill","on_attacked","on_damaged","on_stack_gained","after_attack","after_move","after_action","on_attack","own_unit_entered","enemy_unit_entered","own_unit_attacked_hq","enemy_unit_attacked_hq","own_unit_became_veteran","enemy_unit_became_veteran","on_veteran","own_unit_attacked","enemy_unit_attacked","own_unit_retreated","enemy_unit_retreated","own_unit_returned","enemy_unit_returned","on_leave"]) or (effect.op == "cancel_action" and effect_trigger != "on_reveal"):
				return "反制操作只能在 on_reveal 使用"
			if effect.get("target", "") in ["chosen","adjacent_to_chosen","chosen_and_adjacent"] and not ability.trigger in ["on_play", "on_reveal", "on_death", "on_summon", "own_turn_start", "own_turn_end", "opponent_turn_start", "opponent_turn_end", "next_own_turn_start", "next_opponent_turn_start", "next_own_order_played","next_own_unit_deployed", "own_unit_deployed", "enemy_unit_deployed", "own_order_played", "enemy_order_played", "own_card_played", "enemy_card_played", "after_attacked","own_unit_moved","enemy_unit_moved","on_kill","on_attacked", "on_damaged", "on_stack_gained","after_attack","after_move","after_action","own_unit_died","enemy_unit_died","on_attack","own_unit_entered","enemy_unit_entered","own_unit_attacked_hq","enemy_unit_attacked_hq","own_unit_became_veteran","enemy_unit_became_veteran","on_veteran","own_unit_attacked","enemy_unit_attacked","own_unit_retreated","enemy_unit_retreated","own_unit_returned","enemy_unit_returned","on_leave","when_condition","on_activate"]:
				return "chosen 只能用于部署、被召唤、阵亡或己方回合效果"
	if total > 24 or used.size() != value.parameters.size():
		return "模板操作超限或声明参数未使用"
	return ""

static func walk_effects(effects: Array) -> Array:
	var result: Array = []
	for e in effects:
		result.append(e)
		if e.op in ["if_drawn","if_killed","schedule"]: result.append_array(walk_effects(e.effects))
		if e.op == "choose_effect":
			for option in e.options: result.append_array(walk_effects(option.effects))
	return result

# Scheduled children run in the future event context, not the parent on_play.
static func _scoped_effects(effects: Array, trigger: String) -> Array:
	var result: Array = []
	for effect in effects:
		result.append({"effect":effect,"trigger":trigger})
		if effect.op in ["if_drawn","if_killed","schedule"]:
			result.append_array(_scoped_effects(effect.effects,effect.trigger if effect.op=="schedule" else trigger))
		elif effect.op == "choose_effect":
			for option in effect.options: result.append_array(_scoped_effects(option.effects,trigger))
	return result

static func effect_leaves(effects: Array) -> Array:
	return walk_effects(effects).filter(func(e): return not e.op in ["choose_effect","if_drawn","if_killed","schedule"])

static func _effect_paths(effects: Array) -> Array:
	var paths: Array = [[]]
	for e in effects:
		var next: Array = []
		for path in paths:
			if e.op == "choose_effect":
				for option in e.options: next.append(path + ([] if option.has("target") else option.effects))
			else: next.append(path + [e])
		paths = next
	return paths

static func choice_text(option: Dictionary, definition: Dictionary, ability: Dictionary = {}) -> String:
	var shell: Dictionary = definition.duplicate(true)
	shell.keywords = []
	var a: Dictionary = ability.duplicate(true) if not ability.is_empty() else {"trigger":"on_play"}
	a.effects = option.effects
	if option.has("target"): a.target=option.target
	a.erase("premise")
	shell.abilities = [a]
	var text := rules_text(shell)
	return text.substr(text.find("：")+1)

static func _effect_chooses(e: Dictionary) -> bool:
	if e.get("target") in ["chosen","adjacent_to_chosen","chosen_and_adjacent"]:return true
	for v in [e.get("amount"),e.get("attack_delta"),e.get("health_delta"),e.get("value")]:
		if v is Dictionary and (v.has("stack_count") or v.has("unit_stat")) and v.get("stack_count",v.get("unit_stat",{})).target=="chosen":return true
	return false

static func _ability_target_error(ability: Dictionary) -> String:
	if ability.trigger == "when_condition":
		if not ability.has("premise"): return "满足条件时需要明确前提"
		if ability.has("limit") or ability.has("limit_scope") or ability.has("occurrence"): return "满足条件时每次在场只触发一次"
		if ability.has("target") and ability.target.get("timing","") != "trigger": return "满足条件时需要触发时选择目标"
		var text := JSON.stringify(ability.premise)
		for marker in ['"chosen"','"trigger_unit"','"attack_target"','"event_damage"','"source_destroyed_count"','"destroyed_by"']:
			if marker in text: return "满足条件时不读取事件或所选目标"

	var extended := _extended_error(ability)
	if not extended.is_empty(): return extended
	if ability.has("premise"):
		if _premise_nodes(ability.premise) > 24: return "条件过于复杂：最多4层、24个节点"

	for effect in walk_effects(ability.effects):
		if effect.op == "set_combat_damage_multiplier" and int(effect.get("divisor",1)) > 1 and not effect.has("rounding"): return "分数伤害需要指定向上或向下取整"

	var chosen: bool = _unbound_effects(ability.effects).any(func(e: Dictionary) -> bool: return _effect_chooses(e))
	if ability.trigger == "while_active":
		for scoped in _scoped_effects(ability.effects,ability.trigger):
			var effect: Dictionary = scoped.effect
			var effect_trigger: String = scoped.trigger
			if effect.op!="unit_limit" and (not effect.op in ["modify_stats","modify_operation_cost","modify_stacks","grant_keyword","modify_incoming_damage"] or not effect.get("target","") in ["self","all_units","all_friendly_units","all_other_friendly_units","all_enemy_units","adjacent_to_self","own_hq","enemy_hq"] or effect.get("duration","") != "battle" or effect.op=="grant_keyword" and not effect.keyword_id in ["core.guard","core.blitz","core.fury","core.immune"]): return "场地持续效果仅支持群体固定攻防、行动费和重甲变化"

	if ability.has("target") and (not ability.trigger in ["on_play","on_reveal","on_death","on_summon","own_turn_start","own_turn_end","opponent_turn_start","opponent_turn_end","next_own_turn_start","next_opponent_turn_start","next_own_order_played","next_own_unit_deployed","own_unit_deployed","enemy_unit_deployed","own_order_played","enemy_order_played","own_card_played","enemy_card_played","after_attacked","own_unit_moved","enemy_unit_moved","on_kill","on_attacked","on_damaged","on_stack_gained","after_attack","after_move","after_action","own_unit_died","enemy_unit_died","on_attack","own_unit_entered","enemy_unit_entered","own_unit_attacked_hq","enemy_unit_attacked_hq","own_unit_became_veteran","enemy_unit_became_veteran","on_veteran","own_unit_attacked","enemy_unit_attacked","own_unit_retreated","enemy_unit_retreated","own_unit_returned","enemy_unit_returned","on_leave","when_condition","on_activate"] or not chosen): return "效果组 target 须与可选择时机的 chosen 配对"
	if ability.trigger in ["on_reveal","on_death","on_summon","own_turn_start","own_turn_end","opponent_turn_start","opponent_turn_end","next_own_turn_start","next_opponent_turn_start","next_own_order_played","next_own_unit_deployed","own_unit_deployed","enemy_unit_deployed","own_order_played","enemy_order_played","own_card_played","enemy_card_played","after_attacked","own_unit_moved","enemy_unit_moved","on_kill","on_attacked","on_damaged","on_stack_gained","after_attack","after_move","after_action","own_unit_died","enemy_unit_died","on_attack","own_unit_entered","enemy_unit_entered","own_unit_attacked_hq","enemy_unit_attacked_hq","own_unit_became_veteran","enemy_unit_became_veteran","on_veteran","own_unit_attacked","enemy_unit_attacked","own_unit_retreated","enemy_unit_retreated","own_unit_returned","enemy_unit_returned","on_leave","when_condition","on_activate"] and chosen and not ability.has("target"): return "延后触发的 chosen 需要效果组 target"
	return ""

static func _can_be_zero(value: Variant, params: Dictionary) -> bool:
	if value is Dictionary:
		# Runtime counts may evaluate to zero; they are not an always-zero definition.
		if not value.has("param"): return false
		return params[value.param].minimum <= 0 and params[value.param].maximum >= 0
	return value == 0

static func _substitute(value: Variant, params: Dictionary) -> Variant:
	if value is Dictionary:
		if value.has("param"):
			return params[value.param]
		var result := {}
		for key in value:
			result[key] = _substitute(value[key], params)
		return result
	if value is Array:
		var result := []
		for child in value:
			result.append(_substitute(child, params))
		return result
	return value

static func compile_card(definition: Dictionary, keyword_definitions: Array) -> Dictionary:
	if not _safe_json(definition):
		return _failure("卡牌包含非 JSON 类型、非整数或嵌套过深")
	var source: Dictionary = _normalized(definition)
	if canonical(source).to_utf8_buffer().size() > 16384:
		return _failure("卡牌定义超过 16 KiB")
	if _card_schema.is_empty():
		_card_schema = JSON.parse_string(Contracts.CARD_JSON)
	var error := _matches(source, _card_schema, _card_schema)
	if not error.is_empty():
		return _failure(error)
	if not _plain(source.name) or not _plain(source.flavor_text, true) or not _plain(source.get("display_text",""),true):
		return _failure("名称或风味文本包含禁止的控制字符")
	if source.appearance.has("name_break"):
		var split := int(source.appearance.name_break)
		if split >= str(source.name).length() or str(source.name).left(split).strip_edges().is_empty() or str(source.name).substr(split).strip_edges().is_empty():
			return _failure("名称换行必须位于文字之间，两行均不能为空")
	var registry := {}
	for candidate in keyword_definitions:
		if not candidate is Dictionary:
			return _failure("词条目录项必须为定义对象")
		# An optional registry record is accepted only when explicitly approved.
		var item: Dictionary = candidate
		if candidate.has("definition"):
			if candidate.get("registry_status", candidate.get("status", "")) != "approved":
				continue
			item = candidate.definition
			if candidate.has("definition_hash") and candidate.definition_hash != sha(item):
				return _failure("词条登记哈希不匹配")
		error = validate_keyword(item)
		if not error.is_empty():
			return _failure("词条校验失败：" + error)
		var identity: String = item.id + "@" + str(int(item.version))
		if registry.has(identity) and canonical(registry[identity]) != canonical(item):
			return _failure("词条同版本内容冲突")
		registry[identity] = _normalized(item)
	var expanded := source.duplicate(true)
	expanded.keywords = []
	var bindings := {}
	var groups: Array = [source.keywords]
	for token in source.tokens:
		if not _plain(token.name):
			return _failure("衍生单位名称包含控制字符")
		groups.append(token.keywords)
	for token in expanded.tokens:
		token.keywords = []
	for group_index in groups.size():
		var seen_ids := {}
		for reference in groups[group_index]:
			if seen_ids.has(reference.id):
				return _failure("关键词 ID 重复：" + reference.id)
			seen_ids[reference.id] = true
			var identity: String = reference.id + "@" + str(int(reference.version))
			if not registry.has(identity):
				return _failure("词条未登记或精确版本不存在：" + identity)
			var keyword: Dictionary = registry[identity]
			if reference.params.size() != keyword.parameters.size():
				return _failure("词条参数数量不匹配：" + identity)
			for param in keyword.parameters:
				if not reference.params.has(param) or not _valid_parameter(reference.params[param],keyword.parameters[param]):
					return _failure("词条参数范围错误：" + param)
			if keyword.implementation.kind == "configurable":
				if not reference.has("abilities") or reference.abilities.is_empty(): return _failure("请为本卡填写「"+keyword.name+"」的触发、前提与效果")
			elif reference.has("abilities"): return _failure("仅逐卡配置词条可填写独立效果")
			bindings[identity] = {"id": keyword.id, "version": keyword.version, "definition_hash": sha(keyword)}
			var body: Dictionary = expanded if group_index == 0 else expanded.tokens[group_index - 1]
			if keyword.implementation.kind == "configurable":
				if not body.has("abilities"): body["abilities"] = []
				body.abilities.append_array(reference.abilities.duplicate(true))
			elif keyword.implementation.kind == "template":
				if not body.has("abilities"): body["abilities"] = []
				body.abilities.append_array(_substitute(keyword.implementation.abilities, reference.params))
			else:
				if body.get("kind", "unit") != "unit":
					return _failure("指令与反制不能持有单位 builtin 词条")
				body.keywords.append(reference)
	if expanded.has("veteran"):
		if expanded.kind!="unit": return _failure("只有单位可以设置老兵形态")
		var form: Array=expanded.tokens.filter(func(t):return t.token_id==expanded.veteran.token_id)
		if form.is_empty() or form[0].get("kind","unit")!="unit": return _failure("老兵形态须引用已定义的衍生单位")
	var token_ids := {}
	for token in expanded.tokens:
		if token_ids.has(token.token_id): return _failure("token_id 重复")
		if not _plain(token.get("flavor_text", ""), true) or not _plain(token.get("display_text",""),true): return _failure("衍生卡说明包含控制字符")
		token_ids[token.token_id] = token
	var bodies: Array = [expanded]
	bodies.append_array(expanded.tokens)
	var edges := {}
	var total := 0
	for body in bodies:
		if body.get("kind") == "hq":
			for adjustment in body.draw_rule.get("adjustments",[]):
				if not _premise_names_valid(adjustment.premise) or _premise_nodes(adjustment.premise)>24 or not _premise_unit_queries(adjustment.premise).is_empty(): return _failure("总部抽牌条件无效或引用了单位目标")
		for tier in body.get("cost_surcharge",[])+([body.cost_override] if body.has("cost_override") else []):
			if not _premise_names_valid(tier.premise) or _premise_nodes(tier.premise)>24: return _failure("加费条件无效")
			for marker in ['"unit_stat"','"stack_count"','"unit_state"','"unit_keyword"','"unit_matches"','"unit_side"','"source_','"event_','"previous_card"','"destroyed_by"']:
				if JSON.stringify(tier.premise).contains(marker): return _failure("加费条件仅查询出牌前公开场面或回合状态")
		if body.has("cost_reduction") and not _count_names_valid(body.cost_reduction.per_unit): return _failure("减费规则的单位名称筛选无效")
		var uses_chosen := false
		var used_tokens := {}
		if body.has("veteran"): used_tokens[body.veteran.token_id]=true
		var count := 0
		for ability in body.get("abilities", []):
			if _premise_unit_queries(ability.get("premise",{})).any(func(q): return q.target == "chosen"): uses_chosen = true
			var target_error := _ability_target_error(ability)
			if target_error.is_empty(): target_error = _extended_error(ability,body)
			if not target_error.is_empty(): return _failure(target_error)
			if not body.get("kind","unit") in ["unit","field","hq"] and ability.trigger == "while_active": return _failure("此时机仅用于场地卡")
			if body.get("kind","unit") == "field":
				if not ability.trigger in ["on_play","while_active","own_turn_start","own_turn_end","opponent_turn_start","opponent_turn_end","own_unit_died","enemy_unit_died"]: return _failure("场地支持登场、回合时机和持续效果")
				if ability.has("target") and ability.target.get("timing","deploy") != "trigger": return _failure("场地请使用触发时选择目标")
			if body.get("kind", "unit") == "counter" and ability.trigger != "on_reveal":
				return _failure("反制只能使用 on_reveal")
			if body.get("kind", "unit") != "counter" and ability.trigger == "on_reveal":
				return _failure("on_reveal 只能用于反制")
			if body.get("kind", "unit") == "order" and not ability.trigger in ["on_play","next_own_turn_start","next_opponent_turn_start","next_own_order_played","next_own_unit_deployed"]:
				return _failure("指令只能使用 on_play")
			for scoped in _scoped_effects(ability.effects,ability.trigger):
				var effect: Dictionary = scoped.effect
				var effect_trigger: String = scoped.trigger
				count += 2 if effect.has("on_kill_summon") else 1
				for granted in effect.get("grant_abilities",[]): count += granted.effects.size()
				if effect.op=="grant_ability": count += effect.ability.effects.size()
				var target: String = effect.get("target", "")
				if target == "self" and (body.get("kind", "unit") != "unit" or ability.trigger in ["on_death", "on_reveal"]):
					return _failure("指令或死亡触发不能使用 self")
				if target == "trigger_unit" and (not effect_trigger in ["on_reveal","own_unit_deployed","next_own_unit_deployed","enemy_unit_deployed","after_attacked","own_unit_moved","enemy_unit_moved","on_kill","on_attacked","on_damaged","on_stack_gained","after_attack","after_move","after_action","on_attack","own_unit_entered","enemy_unit_entered","own_unit_attacked_hq","enemy_unit_attacked_hq","own_unit_became_veteran","enemy_unit_became_veteran","on_veteran","own_unit_attacked","enemy_unit_attacked","own_unit_retreated","enemy_unit_retreated","own_unit_returned","enemy_unit_returned","on_leave"] or (effect_trigger == "on_reveal" and body.get("counter_trigger") == "enemy_order_played")):
					return _failure("触发单位仅用于部署或总部攻击反制")
				if effect.op == "cancel_action" and (effect_trigger != "on_reveal" or body.get("counter_trigger") == "enemy_unit_deployed"):
					return _failure("取消行动仅用于指令或总部攻击反制")
				if effect in _unbound_effects(ability.effects) and _effect_chooses(effect):
					if not ability.trigger in ["on_play", "on_reveal", "on_death", "on_summon", "own_turn_start", "own_turn_end", "opponent_turn_start", "opponent_turn_end", "next_own_turn_start", "next_opponent_turn_start", "next_own_order_played","next_own_unit_deployed", "own_unit_deployed", "enemy_unit_deployed", "own_order_played", "enemy_order_played", "own_card_played", "enemy_card_played", "after_attacked","own_unit_moved","enemy_unit_moved","on_kill","on_attacked", "on_damaged", "on_stack_gained","after_attack","after_move","after_action","own_unit_died","enemy_unit_died","on_attack","own_unit_entered","enemy_unit_entered","own_unit_attacked_hq","enemy_unit_attacked_hq","own_unit_became_veteran","enemy_unit_became_veteran","on_veteran","own_unit_attacked","enemy_unit_attacked","own_unit_retreated","enemy_unit_retreated","own_unit_returned","enemy_unit_returned","on_leave","when_condition","on_activate"]:
						return _failure("chosen 只能用于部署、被召唤、阵亡或己方回合效果")
					if ability.trigger == "on_play" and not ability.has("target"): uses_chosen = true
				if effect.get("amount") is Dictionary and effect.amount.get("stat") == "source_base_health" and body.get("kind", "unit") != "unit":
					return _failure("初始防御力只能读取来源单位卡牌")
				if effect.op == "modify_stats" and not effect.attack_delta is Dictionary and not effect.health_delta is Dictionary and effect.attack_delta == 0 and effect.health_delta == 0:
					return _failure("属性修改不能全部为零")
				if effect.op == "modify_stacks" and effect.amount == 0:
					return _failure("层数变化不能为零")
				if effect.op == "modify_operation_cost" and effect.get("cost_delta",1) == 0:
					return _failure("行动费用修改不能为零")
				if effect.op == "modify_kredit_slots" and effect.amount == 0: return _failure("资源槽变化不能为零")
				if effect.op == "fight" and (body.get("kind","unit") != "unit" or ability.trigger in ["on_death","on_reveal"]): return _failure("战斗效果需要仍在场的来源单位")
				if effect.op == "fight" and effect.target == "chosen":
					var selector: Dictionary = ability.get("target",body.get("play_target",{}) if body.get("play_target") != null else {})
					if selector.get("side") != "enemy": return _failure("战斗目标必须是敌方单位")
				if effect.op in ["search_deck", "summon_from_deck"] and (not _plain(effect.card_name) or effect.card_name.is_empty() or effect.card_name != effect.card_name.strip_edges()):
					return _failure("检索卡牌名称不能为空、带首尾空格或控制字符")
				for id in effect.get("token_ids",[]):
					if not token_ids.has(id): return _failure("选牌引用了不存在的衍生模板")
					used_tokens[id] = true
				if effect.has("on_kill_summon"):
					var id: String = effect.on_kill_summon
					if not token_ids.has(id) or token_ids[id].get("kind","unit") != "unit": return _failure("击杀后召唤须引用已定义的衍生单位")
					used_tokens[id]=true
				if effect.op in ["summon", "create_card", "transform", "liberate"]:
					if not token_ids.has(effect.token_id):
						return _failure("召唤引用了不存在的 token_id")
					used_tokens[effect.token_id] = true
					if effect.op in ["summon", "transform", "liberate"] and token_ids[effect.token_id].get("kind", "unit") != "unit":
						return _failure("只能直接召唤单位；指令和反制请生成到手牌")
				if effect.op == "grant_keyword":
					var identity: String = effect.keyword_id + "@" + str(int(effect.keyword_version))
					if not registry.has(identity):
						return _failure("动态授予词条未登记")
					bindings[identity] = {"id": effect.keyword_id, "version": effect.keyword_version, "definition_hash": sha(registry[identity])}
		if uses_chosen != (body.get("play_target") != null): return _failure("chosen 与 play_target 必须成对出现")
		if count > 24 or (not body.get("kind", "unit") in ["unit","field","hq"] and body.get("abilities", []).is_empty()): return _failure("能力数量超限或指令没有效果")
		edges[body.get("token_id", "")] = used_tokens.keys()
		total += count
	var reachable := {}
	var pending: Array = edges[""].duplicate()
	while not pending.is_empty():
		var id: String = pending.pop_back()
		if reachable.has(id): continue
		reachable[id] = true
		pending.append_array(edges[id])
	# Unused templates remain available as derived library entries.
	if total > 96: return _failure("卡牌与衍生卡合计最多96条操作")
	error = _matches(expanded, _card_schema, _card_schema)
	if not error.is_empty():
		return _failure("展开程序无效：" + error)
	if canonical(expanded).to_utf8_buffer().size() > 32768:
		return _failure("展开程序超过 32 KiB")
	var ordered: Array = bindings.values()
	ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.id < b.id if a.id != b.id else a.version < b.version)
	var definition_hash := sha(source)
	var program := {"compiler_version": "card-compiler-1", "definition_hash": definition_hash, "keyword_bindings": ordered, "expanded_definition": expanded}
	if canonical(program).to_utf8_buffer().size() > 32768:
		return _failure("展开程序超过 32 KiB")
	return {"ok": true, "error": "", "definition": expanded, "source": source, "display_keywords": registry.keys().filter(func(key):return bindings.has(key)).map(func(key):return {"id":registry[key].id,"version":registry[key].version,"name":registry[key].name,"description":registry[key].description}), "definition_hash": definition_hash, "compiled_program_hash": sha(program), "keyword_bindings": ordered, "compiler_version": "card-compiler-1"}

static func canonical(value: Variant) -> String:
	if value == null:
		return "null"
	if value is bool:
		return "true" if value else "false"
	if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT:
		return str(int(value))
	if value is String or value is StringName:
		var encoded := '"'
		var normalized := normalize_text(str(value))
		for i in normalized.length():
			var code := normalized.unicode_at(i)
			match code:
				34: encoded += '\\"'
				92: encoded += '\\\\'
				10: encoded += '\\n'
				9: encoded += '\\t'
				_: encoded += ("\\u%04x" % code) if code < 32 else String.chr(code)
		return encoded + '"'
	if value is Array:
		var parts := PackedStringArray()
		for item in value:
			parts.append(canonical(item))
		return "[" + ",".join(parts) + "]"
	if value is Dictionary:
		var parts := PackedStringArray()
		var keys: Array = value.keys()
		keys.sort()
		for key in keys:
			parts.append(canonical(key) + ":" + canonical(value[key]))
		return "{" + ",".join(parts) + "}"
	return "null"

static func sha(value: Variant) -> String:
	return canonical(value).sha256_text()

static func normalize_text(value: String) -> String:
	if _unicode.is_empty():
		_unicode = JSON.parse_string(UnicodeData.DATA_JSON)
	value = value.replace("\r\n", "\n").replace("\r", "\n")
	var points: Array[int] = []
	for i in value.length():
		_decompose(value.unicode_at(i), points)
	# Stable canonical combining-class ordering within each starter segment.
	for i in range(1, points.size()):
		var j := i
		while j > 0 and _ccc(points[j]) != 0 and _ccc(points[j - 1]) > _ccc(points[j]):
			var temporary := points[j]
			points[j] = points[j - 1]
			points[j - 1] = temporary
			j -= 1
	if points.is_empty():
		return ""
	var result: Array[int] = [points[0]]
	var starter := 0
	var last_class := 0
	for i in range(1, points.size()):
		var current := points[i]
		var current_class := _ccc(current)
		var composite := _compose(result[starter], current)
		if composite >= 0 and (last_class == 0 or last_class < current_class):
			result[starter] = composite
		else:
			if current_class == 0:
				starter = result.size()
			result.append(current)
			last_class = current_class
	var text := ""
	for code in result:
		text += String.chr(code)
	return text

static func _ccc(code: int) -> int:
	return int(_unicode.classes.get(str(code), 0))

static func _decompose(code: int, output: Array[int]) -> void:
	if code >= 0xac00 and code <= 0xd7a3:
		var offset := code - 0xac00
		output.append(0x1100 + int(offset / 588))
		output.append(0x1161 + int((offset % 588) / 28))
		if offset % 28 > 0:
			output.append(0x11a7 + offset % 28)
	elif _unicode.decomposition.has(str(code)):
		for child in _unicode.decomposition[str(code)]:
			_decompose(int(child), output)
	else:
		output.append(code)

static func _compose(first: int, second: int) -> int:
	if first >= 0x1100 and first <= 0x1112 and second >= 0x1161 and second <= 0x1175:
		return 0xac00 + ((first - 0x1100) * 21 + second - 0x1161) * 28
	if first >= 0xac00 and first <= 0xd7a3 and (first - 0xac00) % 28 == 0 and second >= 0x11a8 and second <= 0x11c2:
		return first + second - 0x11a7
	return int(_unicode.composition.get(str(first) + "," + str(second), -1))

static func max_unit_stat_text(v: Dictionary) -> String:
	return ("友方" if v.max_unit_stat.side == "ally" else "敌方") + "单位中最高的" + ("攻击力" if v.max_unit_stat.stat == "attack" else "防御力")

## Template parameters may stand for either side of a compare premise, within the integer range compare accepts.
static func _premise_params(p: Variant, parameters: Dictionary, used: Dictionary) -> String:
	if not p is Dictionary: return ""
	if p.get("test") == "compare":
		for side in ["left","right"]:
			var v: Variant = p.get(side)
			if not v is Dictionary or not v.has("param"): continue
			if not parameters.has(v.param): return "模板引用了未声明参数 " + str(v.param)
			var spec: Dictionary = parameters[v.param]
			if spec.type == "token" or int(spec.minimum) < -100 or int(spec.maximum) > 100: return "前提比较参数需为-100至100的整数"
			used[v.param] = true
	for item in p.get("items",[]):
		var error := _premise_params(item, parameters, used)
		if not error.is_empty(): return error
	return _premise_params(p.get("item"), parameters, used)

static func _numeric_text(value: Variant, signed_value := false) -> String:
	if value is Dictionary:
		if value.has("max_unit_stat"): return ("+" if signed_value else "等同于") + max_unit_stat_text(value) + ("" if signed_value else "的")
		if value.has("count_units"): return ("+" if signed_value else "等同于") + count_text(value.count_units) + ("（结算时计数）" if signed_value else "的")
		if value.has("stack_count") or value.has("unit_stat"): return ("+" if signed_value else "等同于") + _unit_value_text(value) + ("" if signed_value else "的")
		if value.has("equipment_faction"): return "每件指定阵营装备×%d" % value.scale
		if value.has("equipment"): return "每件【%s】装备×%d" % [value.equipment,value.scale]
		var names := {"enemy_deaths_this_turn":"本回合敌方单位阵亡数","friendly_deaths_this_turn":"本回合友方单位阵亡数","event_damage":"本次受到的伤害","friendly_turn_number":"己方回合序号","enemy_turn_number":"敌方回合序号","source_base_health":"本卡初始防御力", "enemy_unit_count":"敌方在场单位数", "friendly_unit_count":"己方在场单位数", "other_friendly_unit_count":"其他友方在场单位数"}
		var text: String = names.get(value.get("stat", ""), "未知数值")
		return "+" + text + "（结算时计数）" if signed_value else "等同于" + text + "的"
	return "%+d" % int(value) if signed_value else str(value)

static func _selector_text(selector: Dictionary) -> String:
	var side: String="任意一方" if selector.side=="any" else "友方" if selector.side=="ally" else "敌方"
	return _filter_detail(selector) + side+{"any":"","front":"前线","support":"后援线"}[selector.row]+("指定阵营的" if selector.has("faction_id") else "")+unit_class_text(selector.get("unit_classes",[]))+("或总部" if selector.get("include_hq",false) else "")

static func _count_names_valid(selector: Dictionary) -> bool:
	for key in ["card_name","name_contains"]:
		if selector.has(key) and (selector[key].strip_edges().is_empty() or selector[key] != selector[key].strip_edges() or not _plain(selector[key])): return false
	return true

static func rules_text(card: Dictionary) -> String:
	var definition: Dictionary = card.get("definition", card)
	var lines := PackedStringArray()
	if definition.get("kind") == "hq":
		lines.append("总部初始防御%d；每回合抽%d张牌" % [definition.health,definition.draw_rule.base])
		for adjustment in definition.draw_rule.get("adjustments",[]): lines.append("若%s，抽牌数%+d" % [premise_text(adjustment.premise),adjustment.delta])
	if definition.has("cost_override"): lines.append("若%s，本卡费用为%d" % [premise_text(definition.cost_override.premise),definition.cost_override.value])
	for tier in definition.get("cost_surcharge",[]):
		lines.append("若%s，本卡费用+%d（多档只取最高档）" % [premise_text(tier.premise),tier.amount])
	if definition.has("cost_reduction"):
		lines.append("本卡费用减少%s×%d（最低0，出牌前计算）" % [count_text(definition.cost_reduction.per_unit),int(definition.cost_reduction.amount)])
	var triggers := {"on_activate":"主动","own_card_played":"己方打出卡牌后","enemy_card_played":"敌方打出卡牌后","on_keyword_lost":"失去词条时","on_kill":"消灭敌方单位后","after_attacked":"受到攻击后","own_unit_moved":"友方单位移动到前线后","enemy_unit_moved":"敌方单位移动到前线后","when_condition":"满足条件时","own_unit_attacked":"友方单位攻击后","enemy_unit_attacked":"敌方单位攻击后","own_unit_retreated":"友方单位撤退后","enemy_unit_retreated":"敌方单位撤退后","own_unit_returned":"友方单位回手后","enemy_unit_returned":"敌方单位回手后","on_leave":"离场时","on_veteran":"升为老兵时","own_unit_became_veteran":"友方单位升为老兵时","enemy_unit_became_veteran":"敌方单位升为老兵时","on_attack":"主动攻击时","own_unit_entered":"友方单位入场时","enemy_unit_entered":"敌方单位入场时","own_unit_attacked_hq":"友方单位攻击敌方总部后","enemy_unit_attacked_hq":"敌方单位攻击己方总部后","next_own_unit_deployed":"下一次己方部署单位后","after_attack":"主动攻击完成后","after_move":"移动完成后","after_action":"主动行动完成后","own_unit_died":"友方单位阵亡时","enemy_unit_died":"敌方单位阵亡时","on_stack_gained":"获得层数后","own_unit_deployed":"己方部署其他单位后","enemy_unit_deployed":"敌方部署单位后","own_order_played":"己方指令结算后","enemy_order_played":"敌方指令结算后","on_attacked":"受到主动攻击时","on_damaged":"受到伤害后","next_own_turn_start":"己方下回合开始","next_opponent_turn_start":"敌方下回合开始","next_own_order_played":"下一张己方指令结算后","while_active":"在场期间","opponent_turn_start":"对方回合开始","opponent_turn_end":"对方回合结束","on_summon":"被召唤时", "on_reveal": "触发时", "on_play": "部署时" if definition.get("kind","unit") == "unit" else "生效时" if definition.get("kind") == "field" else "使用时", "own_turn_start": "己方回合开始", "own_turn_end": "己方回合结束", "on_death": "阵亡"}
	if definition.has("damage_bonuses"): lines.append("效果伤害："+_bonus_text(definition.damage_bonuses)+"。")
	var targets := {"all_other_friendly_units":"其他友方单位","self_and_trigger":"自身与触发单位","trigger_and_adjacent":"触发单位及其相邻单位","adjacent_to_trigger":"触发单位相邻单位","random_enemy_target":"随机敌方目标","random_friendly_target":"随机友方目标","all_units":"双方所有单位","creator":"生成本卡的单位","attack_target":"攻击目标","effect_target":"受影响单位","chosen_and_adjacent":"所选单位及其左右相邻单位","adjacent_to_self":"自身左右相邻单位","adjacent_to_chosen":"所选单位左右相邻单位","trigger_unit": "触发单位", "self": "自身", "chosen": "所选单位", "own_hq": "己方总部", "enemy_hq": "敌方总部", "all_friendly_units": "所有友方单位", "all_enemy_units": "所有敌方单位", "random_friendly_unit": "随机友方单位", "random_enemy_unit": "随机敌方单位"}
	if definition.get("play_target") is Dictionary:
		var selector: Dictionary = definition.play_target
		targets["chosen"] = "所选"+_selector_text(selector)
	if definition.get("kind") == "counter":
		var counter_names := {"enemy_unit_deployed":"对方部署单位后", "enemy_order_played":"对方打出指令时", "enemy_unit_attacked":"对方攻击友方单位时", "enemy_hq_attacked":"对方攻击己方总部时"}
		lines.append("伏置：%s触发一次，触发时扣费；下次己方回合开始未触发则返回手牌。" % counter_names.get(definition.get("counter_trigger"), ""))
	for keyword in definition.get("keywords", []):
		lines.append(keyword_name(keyword.id))
	for ability in definition.get("abilities", []):
		var effects := PackedStringArray()
		for effect in ability.effects:
			var target: String = "所选单位" if effect.get("target")=="selected_units" else targets.get(effect.get("target", ""), "")
			if effect.get("target") == "chosen" and ability.has("target"):
				target = "所选"+_selector_text(ability.target)
				if ability.trigger in ["on_death","own_turn_start","own_turn_end"] and ability.target.get("timing","deploy")=="deploy": target=target.replace("所选","部署时选定的")
			if effect.get("target") in ["adjacent_to_chosen","chosen_and_adjacent"]:
				var selector: Dictionary = ability.get("target",definition.get("play_target") if definition.get("play_target") is Dictionary else {})
				if not selector.is_empty(): target="所选"+_selector_text(selector)+("及其" if effect.target=="chosen_and_adjacent" else "的")+"左右相邻单位"
			if effect.has("unit_filter"):
				var f: Dictionary = effect.unit_filter
				target += "中"+("名为【%s】的" % f.card_name if f.has("card_name") else "")+("名称含【%s】的" % f.name_contains if f.has("name_contains") else "")+unit_class_text(f.get("unit_classes",[]))
				target += _filter_detail(f)
			var amount_text := _numeric_text(effect.get("amount", 0))
			var duration := "" if ability.trigger == "while_active" else "本回合" if effect.get("duration", "battle") == "end_of_turn" else "永久" if effect.get("duration") == "match" else "直到下个己方回合开始" if effect.get("duration")=="next_own_turn_start" else "直到下个敌方回合结束" if effect.get("duration")=="next_opponent_turn_end" else "在场期间"
			match effect.op:
				"select_units": effects.append("选择%d～%d个%s%s单位" % [effect.min,effect.max,"友方" if effect.side=="ally" else "敌方" if effect.side=="enemy" else "","【%s】"%effect.unit_filter.name_contains if effect.get("unit_filter",{}).has("name_contains") else ""])
				"if_killed": effects.append(("本次伤害每消灭一个单位，" if effect.get("per_unit",false) else "若刚才的伤害消灭单位，")+choice_text({"effects":effect.effects},definition,ability))
				"schedule":
					var when: String = ""
					if effect.trigger in ["next_own_turn_start","next_opponent_turn_start"]:
						when=("每个%s回合开始" % ("己方" if effect.trigger=="next_own_turn_start" else "敌方") if effect.get("repeat")=="each_turn" else "%s后续第%d回合开始" % ["己方" if effect.trigger=="next_own_turn_start" else "敌方",effect.get("after_turns",1)])
					else:
						when=("每次" if effect.get("repeat")=="each_event" else "下一次")+{"next_own_unit_deployed":"己方部署单位后","next_own_unit_entered":"友方单位入场时","next_own_unit_attacked_hq":"友方单位攻击敌方总部后","next_own_order_played":"己方指令结算后"}[effect.trigger]
					effects.append(("本回合，" if effect.get("lifetime")=="turn" else "")+when+"："+choice_text({"effects":effect.effects},definition,ability)+("（共%d次）"%effect.times if effect.has("times") else ""))
				"become_trigger_unit": effects.append("变为被消灭单位的复制"+("（保留自身永久强化）" if effect.inherit=="permanent" else ""))
				"transform":
					var token_name: String=effect.token_id
					for token in definition.tokens:
						if token.token_id==effect.token_id: token_name=token.name
					effects.append("将%s进化为【%s】%s"%[target,token_name,"（继承永久强化）" if effect.inherit=="permanent" else ""])
				"prepare_counter": effects.append("使敌方下一张指令无效"+("（自身在场期间）" if effect.duration=="battle" else "（本回合）" if effect.duration=="end_of_turn" else ""))
				"if_drawn": effects.append("若本组抽到的牌%s为%s数费用，%s" % ["全部" if effect.match=="all" else "至少一张","偶" if effect.parity=="even" else "奇",choice_text({"effects":effect.effects},definition,ability)])
				"choose_effect":
					var choices := PackedStringArray()
					for option in effect.options: choices.append(option.label+("（需"+premise_text(option.premise)+"）" if option.has("premise") else "")+"〔"+choice_text(option,definition,ability)+"〕")
					effects.append("抉择（仅选一项）："+" / ".join(choices))
				"remove_hand": effects.append("移除%s手牌中的所有【%s】" % ["己方" if effect.player=="owner" else "敌方",effect.card_name])
				"cancel_action": effects.append("取消本次指令或总部攻击，费用不返还")
				"damage":
					var text := "对%s造成%s点伤害" % [target, amount_text]
					if effect.has("max_amount"): text += "，最多%d点" % effect.max_amount
					for cap in effect.get("caps",[]): text += "（%s最多%d点）" % [_filter_detail(cap.filter)+unit_class_text(cap.filter.get("unit_classes",[])),cap.amount]
					if effect.has("bonuses"): text += "（"+_bonus_text(effect.bonuses)+"，合并结算）"
					if effect.has("on_kill_summon"):
						var token_name: String = effect.on_kill_summon
						for token in definition.get("tokens",[]):
							if token.token_id == effect.on_kill_summon: token_name=token.name
						text += "；若本次击杀，在其原位置为其控制者召唤【%s】" % token_name
					effects.append(text)
				"heal": effects.append("为%s恢复%s点生命" % [target, amount_text])
				"draw": effects.append("%s抽%d张%s牌" % ["" if effect.player == "owner" else "敌方", effect.amount,{"unit":"单位","order":"指令","counter":"反制","field":"场地"}.get(effect.get("filter",{}).get("kind",""),"")])
				"modify_stats":
					if effect.get("health_mode")=="max_only":
						effects.append("%s防御上限%+d%s（%s）" % [target,effect.health_delta,"，攻击"+_numeric_text(effect.attack_delta,true) if effect.attack_delta!=0 else "",duration])
						continue
					effects.append("%s%s/%s%s" % [target, _numeric_text(effect.attack_delta, true), _numeric_text(effect.health_delta, true), "（%s）" % duration if not duration.is_empty() else ""])
				"swap_stats": effects.append("交换%s的攻击力与剩余防御力（本次在场期间）" % target)
				"set_attack": effects.append("%s攻击力设为%s（%s）" % [target,_unit_value_text(effect.value) if effect.value is Dictionary else str(effect.value),duration])
				"lose_kredits": effects.append(("己方" if effect.player=="owner" else "敌方")+"失去%d指挥点" % effect.amount)
				"trigger_death": effects.append("触发%s的阵亡效果" % target)
				"trigger_evolution": effects.append("使%s立即进化" % target)
				"summon_origin": effects.append("召唤%d张原型" % effect.amount)
				"temporarily_remove": effects.append("暂时移除%s，%s%s" % [target,"回合结束" if effect.return_when=="end_of_turn" else "本单位离场后" if effect.return_when=="source_leaves" else "%s第%d个后续回合%s" % ["敌方" if "opponent" in effect.return_when else "己方",int(effect.get("after_turns",1)),"结束" if effect.return_when.ends_with("end") else "开始"],"返回手牌" if effect.destination=="hand" else "回到原位"])
				"become_veteran": effects.append("使%s升为老兵" % target)
				"take_control": effects.append("控制%s（%s）" % [target,{"end_of_turn":"本回合","next_own_turn_start":"直到己方下回合开始","battle":"直到离场"}[effect.duration]])
				"grant_ability":
					var shell: Dictionary=definition.duplicate(true)
					shell.kind="unit";shell.keywords=[];shell.play_target=null;shell.abilities=[effect.ability]
					effects.append("%s获得“%s”（%s）" % [target,rules_text(shell),duration])
				"grant_keyword": effects.append("%s获得%s%s" % [target, keyword_name(effect.keyword_id), "（%s）" % duration if not duration.is_empty() else ""])
				"set_attack_limit": effects.append("%s使%s每回合最多攻击%d次" % [duration, target, effect.attacks])
				"modify_stacks": effects.append("%s%s%+d%s" % [target, "重甲" if effect.stack=="heavy_armor" else effect.stack+"层数", effect.amount, "（%s）" % duration if not duration.is_empty() else ""])
				"set_stacks": effects.append("%s使%s%s设为%d" % [duration, target, "重甲" if effect.stack=="heavy_armor" else effect.stack+"层数", effect.amount])
				"modify_operation_cost": effects.append("%s行动费%s%s" % [target, "为%d"%effect.cost_set if effect.has("cost_set") else "%+d"%effect.cost_delta, "（%s）" % duration if not duration.is_empty() else ""])
				"destroy": effects.append("消灭%s" % target)
				"pin": effects.append("压制%s（各自后续%d回合结束时解除）" % [target,effect.turns])
				"suppress": effects.append("抑制%s" % target)
				"repair": effects.append("完全修复%s" % target)
				"reset_operations": effects.append("重置%s本回合已用行动次数" % target)
				"retreat": effects.append("使%s撤退" % target)
				"return_to_hand": effects.append("将%s返回其控制者手牌" % target + (("，本回合内" if effect.duration=="end_of_turn" else "，")+"该牌下次打出费用%+d" % effect.cost_delta if effect.has("cost_delta") else ""))
				"remove": effects.append("移除%s，不触发阵亡" % target)
				"shuffle_into_deck": effects.append("将%s%s%s牌库%s，不触发阵亡" % [target, "洗入" if effect.get("position","random")=="random" else "放到", "其拥有者的" if effect.get("deck","caster")=="owner" else "己方", {"top":"顶","bottom":"底"}.get(effect.get("position","random"),"")])
				"tax_opponent_plays": effects.append("下个敌方回合，敌方打出%s的费用+%d" % [{"unit":"单位牌","order":"指令牌","any":"卡牌"}[effect.card_kind], effect.amount] + ("；己方下个回合开始时，敌方每因此多支付%d点，获得1点指挥点（可超过资源槽）" % effect.refund_per if effect.has("refund_per") else ""))
				"fight": effects.append("自身与%s交战" % target)
				"intel": effects.append("选择并查看敌方%d张手牌" % effect.amount if effect.get("selection","random")=="chosen" else "情报%d" % effect.amount)
				"discard": effects.append("%s%s弃置%d张%s手牌" % ["己方" if effect.player == "owner" else "敌方","选择" if effect.get("selection","random") == "chosen" else "随机",effect.amount,_card_filter_text(effect.get("filter",{}))])
				"research":
					var names := PackedStringArray()
					for id in effect.token_ids:
						for token in definition.get("tokens",[]):
							if token.token_id == id: names.append("【%s】" % token.name)
					effects.append("研发：选择%s加入手牌" % "或".join(names))
				"develop": effects.append("开发：从%s随机展示最多3种卡牌，选择一张加入手牌" % ("指定衍生卡池" if effect.source == "tokens" else "当前己方牌库（选中的原牌移出牌库）" if effect.source=="deck" else "己方起始牌组卡池"))
				"modify_hand_cost": effects.append("%s，%s己方手牌%s费用%s%d（最低0）" % [{"hand":"留在手牌期间","end_of_turn":"本回合","match":"永久"}[effect.duration],{"chosen":"选择一张","random":"随机一张","all":"所有","self":"本卡这张","drawn":"本组刚抽到的"}[effect.selection],"（指定阵营）" if effect.get("filter",{}).has("faction_id") else "","+" if effect.cost_delta>0 else "",effect.cost_delta])
				"modify_cards": effects.append(_modify_cards_text(effect,definition))
				"gain_hq_defense": effects.append("%s总部增加%d点防御" % ["己方" if effect.player == "owner" else "敌方",effect.amount])
				"modify_kredit_slots": effects.append("%s资源槽%+d" % ["己方" if effect.player == "owner" else "敌方",effect.amount])
				"set_combat_priority": effects.append("%s%s交战先手（%s）" % [duration,target,{"attack":"主动攻击","retaliation":"反击","both":"攻击及反击"}[effect.applies_to]])
				"grant_unit_class": effects.append("%s%s也视为%s（不改变行动规则）" % [duration,target,unit_class_text([effect.unit_class])])
				"noop": effects.append("无额外效果")
				"modify_incoming_damage": effects.append(_incoming_rule_text(effect,target,duration))
				"grant_order_target_reward": effects.append("%s己方指令选中%s时获得%d指挥点（不含本指令）" % [duration,target,effect.amount])
				"set_combat_damage_multiplier":
					if effect.get("attack_base")=="opponent":
						effects.append("%s交战时以对方攻击力为基数（对总部仍用自身攻击力，倍率%d/%d）" % [target,effect.multiplier,int(effect.get("divisor",1))]);continue
					var against: String = {"any":"任意目标","infantry":"步兵","tank":"坦克","artillery":"炮兵","fighter":"战斗机","bomber":"轰炸机","hq":"总部"}.get(effect.against, "目标")
					if effect.has("target_filter"): against=_filter_detail(effect.target_filter)+unit_class_text(effect.target_filter.get("unit_classes",[]))
					if effect.has("target_attack_compare"): against="攻击力"+{"gt":"高于","gte":"不低于","eq":"等于","ne":"不等于","lt":"低于","lte":"不高于"}[effect.target_attack_compare]+"自身的"+against
					var phase: String = {"attack":"主动攻击","retaliation":"反击","both":"主动攻击或反击"}.get(effect.applies_to, "攻击")
					if effect.multiplier == 0:
						effects.append("%s%s对%s%s时不造成战斗伤害" % [duration,target,against,phase])
						continue
					var ratio := str(effect.multiplier) + ("/" + str(effect.divisor) if effect.has("divisor") else "")
					var extra := ("，向上取整" if effect.get("rounding") == "ceil" else "，向下取整") if int(effect.get("divisor",1)) > 1 else ""
					if effect.get("attack_delta",0)!=0: extra += "（交战攻击%+d）" % effect.attack_delta
					if effect.get("ignore_armor",false): extra += "，无视重甲"
					effects.append("%s使%s对%s%s时造成%s倍战斗伤害%s" % [duration,target,against,phase,ratio,extra])
				"gain_kredits": effects.append(("获得%d点本回合资源，可超过资源槽" if effect.get("allow_overflow",false) else "恢复%d点资源，不超过现有资源槽") % effect.amount)
				"search_deck": effects.append("从己方牌组将%d张【%s】加入手牌" % [effect.amount, effect.card_name])
				"summon_from_deck": effects.append("从己方牌组召唤%d张【%s】单位到后援线" % [effect.amount, effect.card_name])
				"unit_limit": effects.append("%s在场单位最多%d个" % ["双方" if effect.player=="both" else "己方" if effect.player=="owner" else "敌方",effect.amount])
				"reshuffle_zones": effects.append("%s将%s洗回各自牌库" % ["双方" if effect.player=="both" else "己方" if effect.player=="owner" else "敌方","、".join(effect.zones.map(func(z):return {"hand":"手牌","discard":"弃牌堆","battlefield":"在场单位"}[z]))])
				"liberate": effects.append("解放为"+str(effect.token_id))
				"transfer_card": effects.append(_transfer_text(effect))
				"equip", "unequip": effects.append("%s%s%d件【%s】装备" % [targets.get(effect.target,effect.target),"装备" if effect.op=="equip" else "移除",effect.amount,effect.tag])
				"create_card":
					var name: String = effect.token_id
					for token in definition.get("tokens", []):
						if token.token_id == effect.token_id: name = token.name
					effects.append("将%d张【%s】加入%s手牌" % [effect.amount, name, "己方" if effect.player == "owner" else "敌方"])
				"summon":
					var name: String = effect.token_id
					for token in definition.tokens:
						if token.token_id == effect.token_id:
							var flags := PackedStringArray()
							for keyword in token.keywords:
								flags.append(keyword_name(keyword.id))
							name = "%s（%d/%d，行动费%d%s）" % [token.name, token.attack, token.health, int(token.get("operation_cost",1)), "，" + "、".join(flags) if not flags.is_empty() else ""]
					effects.append("在己方后援线召唤%d个%s" % [effect.amount, name])
		lines.append(("手牌中，" if ability.get("zone")=="hand" else "")+("场地生效期间" if ability.trigger=="while_active" and definition.get("kind")=="field" else ("%s第%d个后续回合开始" % ["己方" if ability.trigger=="next_own_turn_start" else "敌方",ability.after_turns]) if int(ability.get("after_turns",1))>1 else ("失去"+keyword_name(ability.keyword_id)+"时" if ability.trigger=="on_keyword_lost" else str(triggers[ability.trigger])).replace("友方单位","自身" if ability.get("event_scope")=="self" else "其他友方单位" if ability.get("event_scope")=="other" else "友方单位")) + ("（%s）" % ability.stack if ability.trigger=="on_stack_gained" else "") + ("（第%d次）" % ability.occurrence if ability.has("occurrence") else "") + ("（每累计损失%d防御）" % int(ability.damage_step) if ability.has("damage_step") else "") + ("（%s最多%d次）" % ["每回合" if ability.get("limit_scope")=="turn" else "",int(ability.limit)] if ability.has("limit") else "") + "：" + ("若" + premise_text(ability.premise) + "，则" if ability.has("premise") else "") + ("重复%s次（次数先锁定）：" % (count_text(ability.repeat.count_units) if ability.repeat is Dictionary else str(ability.repeat)) if ability.has("repeat") else "") + "；".join(effects))
	return _compact_rules("\n".join(lines)) if not lines.is_empty() else "无额外能力"

static func _premise_nodes(p: Dictionary, depth: int = 1) -> int:
	if depth > 4: return 1000
	var nodes := 1
	for child in p.get("items", []): nodes += _premise_nodes(child, depth + 1)
	if p.has("item"): nodes += _premise_nodes(p.item, depth + 1)
	return nodes

static func _premise_names_valid(p: Dictionary) -> bool:
	if p.has("filter") and not _count_names_valid(p.filter): return false
	if p.has("card_name") and not _count_names_valid({"card_name":p.card_name}): return false
	if p.get("test")=="compare":
		for v in [p.left,p.right]:
			if v is Dictionary and v.has("stack_count") and not _stack_name(v.stack_count.stack):return false
	for child in p.get("items",[]):
		if not _premise_names_valid(child):return false
	return _premise_names_valid(p.item) if p.has("item") else true

static func _premise_unit_queries(p: Dictionary) -> Array:
	if p.get("test","") in ["unit_keyword","unit_state","unit_matches","unit_side"]: return [p]
	var queries := []
	if p.get("test")=="compare":
		for v in [p.left,p.right]:
			if v is Dictionary and (v.has("stack_count") or v.has("unit_stat")): queries.append({"target":v.get("stack_count",v.get("unit_stat",{})).target})
	for item in p.get("items",[]): queries.append_array(_premise_unit_queries(item))
	if p.has("item"): queries.append_array(_premise_unit_queries(p.item))
	return queries

static func premise_text(p: Dictionary) -> String:
	if p.test=="deployed_last_turn": return ("己方" if p.player=="owner" else "敌方")+"上个回合部署过"+("【"+p.filter.card_name+"】" if p.filter.has("card_name") else "名称含【"+p.filter.name_contains+"】的" if p.filter.has("name_contains") else "")+("指定阵营的" if p.filter.has("faction_id") else "")+_filter_detail(p.filter)+unit_class_text(p.filter.get("unit_classes",[]))
	if p.test=="destroyed_by": return "被"+unit_class_text(p.unit_classes)+"消灭"
	if p.test == "previous_card": return ("己方" if p.player=="owner" else "敌方")+("本回合" if p.get("this_turn",false) else "")+"上一张打出的牌是"+("【"+p.card_name+"】" if p.has("card_name") else _played_card_filter_text(p.get("filter",{"kind":p.kind})))
	if p.test=="event_card": return "打出的牌为"+_played_card_filter_text(p.filter)
	if p.test in ["hand_contains","played_this_turn"]: return ("己方" if p.player=="owner" else "敌方")+("手牌中有" if p.test=="hand_contains" else "本回合使用过")+str(p.get("min",1))+"张"+_played_card_filter_text(p.filter)
	if p.test == "turn_owner": return "己方回合" if p.side == "owner" else "对方回合"
	if p.test=="unit_matches": return "指定单位符合"+_filter_detail(p.filter)+unit_class_text(p.filter.get("unit_classes",[]))
	if p.test=="unit_side": return "指定单位属于"+("己方" if p.side=="ally" else "敌方")
	if p.test=="deck_top": return ("己方" if p.player=="owner" else "敌方")+"牌库顶费用为"+("偶数" if p.parity=="even" else "奇数")
	if p.test in ["unit_keyword","unit_state"]:
		var who: String = {"self":"自身","chosen":"所选单位","trigger_unit":"触发单位","attack_target":"攻击目标"}[p.target]
		if p.test == "unit_state": return who + {"is_liberated":"已解放","is_veteran":"是老兵","in_front":"位于前线","in_support":"位于支援阵线","has_attacked":"本次在场期间已主动攻击"}[p.state]
		return who + {"printed":"卡面原生具有","current":"当前具有","consumed":"本次在场期间已消耗过"}[p.state] + keyword_name(p.keyword_id)
	if p.test == "not": return "不满足（" + premise_text(p.item) + "）"
	if p.test in ["all", "any"]:
		var pieces := PackedStringArray()
		for item in p.items: pieces.append("（" + premise_text(item) + "）")
		return ("且" if p.test == "all" else "或").join(pieces)
	var names := {"enemy_deaths_this_turn":"本回合敌方单位阵亡数","friendly_deaths_this_turn":"本回合友方单位阵亡数","event_damage":"本次受到的伤害","friendly_turn_number":"己方回合序号","enemy_turn_number":"敌方回合序号","source_destroyed_count":"本卡本次消灭的单位数","enemy_unit_count":"敌方在场单位数","friendly_unit_count":"己方在场单位数","other_friendly_unit_count":"其他友方在场单位数","enemy_front_count":"敌方前线单位数","friendly_front_count":"己方前线单位数","enemy_support_count":"敌方后援线单位数","friendly_support_count":"己方后援线单位数","enemy_hand_count":"敌方手牌数","friendly_hand_count":"己方手牌数","enemy_deck_count":"敌方牌组张数","friendly_deck_count":"己方牌组张数","enemy_hq_health":"敌方总部防御力","friendly_hq_health":"己方总部防御力","enemy_kredits":"敌方剩余资源","friendly_kredits":"己方剩余资源","source_attack":"自身当前攻击力","source_health":"自身当前防御力","source_base_health":"本卡初始防御力"}
	var left: String = max_unit_stat_text(p.left) if p.left is Dictionary and p.left.has("max_unit_stat") else _unit_value_text(p.left) if p.left is Dictionary and (p.left.has("stack_count") or p.left.has("unit_stat")) else count_text(p.left.count_units) if p.left is Dictionary and p.left.has("count_units") else names.get(p.left.stat, p.left.stat) if p.left is Dictionary else str(p.left)
	var right: String = max_unit_stat_text(p.right) if p.right is Dictionary and p.right.has("max_unit_stat") else _unit_value_text(p.right) if p.right is Dictionary and (p.right.has("stack_count") or p.right.has("unit_stat")) else count_text(p.right.count_units) if p.right is Dictionary and p.right.has("count_units") else names.get(p.right.stat, p.right.stat) if p.right is Dictionary else str(p.right)
	return left + {"gt":"大于","gte":"不少于","eq":"等于","ne":"不等于","lte":"不多于","lt":"小于"}[p.cmp] + right + ("%+d" % int(p.right_offset) if p.has("right_offset") and p.right_offset!=0 else "")

static func _unit_value_text(v: Dictionary) -> String:
	var q: Dictionary = v.get("stack_count",v.get("unit_stat",{}))
	var who: String = {"self":"自身","chosen":"所选单位","trigger_unit":"触发单位","creator":"生成本卡的单位","attack_target":"攻击目标","effect_target":"受影响单位"}[q.target]
	return who+(("的重甲层数" if q.stack=="heavy_armor" else "的"+q.stack+"层数") if v.has("stack_count") else {"attack":"当前攻击力","health":"当前防御力","base_attack":"初始攻击力","base_health":"初始防御力","operation_cost":"行动费用","cost":"打出费用","max_health":"防御上限"}[q.stat])

static func _bonus_text(bonuses: Array) -> String:
	var parts:=PackedStringArray()
	for b in bonuses:
		var f:Dictionary=b.filter
		parts.append("对"+("有"+keyword_name(f.keyword_id)+"的" if f.has("keyword_id") else "")+("【%s】" % f.card_name if f.has("card_name") else "名称含【%s】的" % f.name_contains if f.has("name_contains") else "")+("指定阵营" if f.has("faction_id") else "")+unit_class_text(f.get("unit_classes",[]))+"伤害+%d" % b.amount)
	return "，".join(parts)

static func _stack_name(s: String) -> bool:
	return s.length()>=1 and s.length()<=32 and s==s.strip_edges() and _plain(s)

static func _keyword_aura(a: Dictionary) -> bool:
	var p: Dictionary=a.get("premise",{})
	return p.get("test")=="unit_keyword" and p.get("target")=="self" and a.effects.all(func(e):return e.op=="modify_stats" and e.target=="self" and e.health_delta==0 and _integer(e.attack_delta))

static func _extended_error(a: Dictionary, body: Dictionary = {}) -> String:
	if a.trigger=="on_activate":
		if (not body.is_empty() and body.get("kind")!="unit") or a.get("zone")=="hand" or a.get("limit")!=1 or a.get("limit_scope")!="turn": return "主动能力仅供场上单位使用，须设置每回合一次"
		if a.has("target") and a.target.get("timing")!="trigger": return "主动能力发动时选择目标"
		if _premise_unit_queries(a.get("premise",{})).any(func(q):return q.target!="self"): return "主动能力发动前的前提不能读取未选择的目标或事件单位"
	if a.trigger=="on_keyword_lost":
		if not builtin_keywords().any(func(k):return k.id==a.get("keyword_id")) or not body.is_empty() and body.get("kind")!="unit": return "失去词条事件需要单位及基础词条"
	elif a.has("keyword_id"): return "事件词条仅用于失去词条时"
	for i in a.effects.size():
		var e: Dictionary=a.effects[i]
		var prior: Array=a.effects.slice(0,i)
		if e.op=="select_units" and (e.min>e.max or prior.any(func(x):return x.op=="select_units") or a.trigger=="while_active"): return "每组最多一次多选，数量范围须有效"
		if e.get("target")=="selected_units" and not prior.any(func(x):return x.op=="select_units"): return "本组须先选择多个单位"
		if e.get("amount") is Dictionary and e.amount.get("stat")=="selected_destroyed_count" and not prior.any(func(x):return x.op=="destroy" and x.target=="selected_units"): return "本组须先消灭所选单位"
		if e.get("source")=="attack_target" and (e.mode!="copy" or not a.trigger in ["after_attack","on_attack"]): return "被攻击单位仅能在攻击时或之后复制"
		if e.has("copy_state") and (e.source!="attack_target" or e.mode!="copy" or e.has("inherit_from")): return "当前攻防复制仅用于被攻击单位"

	if a.get("zone")=="hand" and (not a.trigger in ["enemy_unit_died","own_unit_died"] or not body.is_empty() and body.get("kind")!="unit" or a.has("target") or a.effects.any(func(e):return e.op!="modify_hand_cost" or e.selection!="self")): return "手牌监听仅支持阵亡时修改本卡费用"
	if a.get("zone")!="hand" and a.effects.any(func(e):return e.op=="modify_hand_cost" and e.selection=="self"): return "本卡手牌费用需使用手牌区域监听"
	for e in a.effects:
		if e.op=="become_trigger_unit" and a.trigger!="on_kill": return "复制被消灭单位形态仅用于本单位击杀时"
		if e.op=="transfer_card" and e.source=="event_card" and (e.mode!="copy" or not a.trigger in ["on_kill","own_unit_died","enemy_unit_died"]): return "事件卡仅能在击杀或阵亡事件中复制"

	if a.trigger == "when_condition" and not body.is_empty() and body.get("kind","unit") != "unit": return "满足条件时仅用于在场单位"
	if a.trigger=="on_leave" and (a.has("occurrence") or a.has("limit") or a.has("limit_scope")): return "离场时仅触发一次，不设置次数限制"
	if a.has("occurrence") and not a.trigger in ["own_unit_attacked", "enemy_unit_attacked", "own_unit_retreated", "enemy_unit_retreated", "own_unit_returned", "enemy_unit_returned", "own_unit_deployed", "enemy_unit_deployed", "own_order_played", "enemy_order_played", "own_card_played", "enemy_card_played", "after_attacked","own_unit_moved","enemy_unit_moved","on_kill","on_attacked", "on_damaged", "on_stack_gained", "after_attack", "after_move", "after_action", "own_unit_died", "enemy_unit_died", "on_attack", "own_unit_entered", "enemy_unit_entered", "own_unit_attacked_hq", "enemy_unit_attacked_hq", "own_unit_became_veteran", "enemy_unit_became_veteran", "on_veteran", "on_leave"]: return "第几次仅用于事件监听"
	if a.has("limit_scope") and not a.has("limit"): return "每回合次数限制须填写次数"
	if str(a.get("premise",{})).contains("destroyed_by") and a.trigger!="on_death": return "击杀者兵种前提只能用于阵亡"
	if str(a.get("premise",{})).contains("source_destroyed_count") and not a.trigger in ["on_play","after_attack","after_action"]: return "该时机没有本次消灭数"
	for e in a.effects:
		if e.op=="temporarily_remove" and e.return_when=="source_leaves" and not body.is_empty() and body.get("kind")!="unit": return "来源离场归还需要单位来源"
		if e.op=="temporarily_remove" and e.has("return_cost") and e.destination!="hand": return "归还费用仅用于返回手牌"
		if e.op=="summon_origin" and not body.is_empty() and body.get("kind")!="unit": return "召唤原型仅用于单位"
		if e.get("target")=="attack_target" and not (a.trigger in ["on_attack","after_attack","after_action"] or a.trigger=="on_reveal" and (body.is_empty() or body.get("counter_trigger")=="enemy_unit_attacked")): return "该时机没有攻击目标"
		for v in [e.get("amount"),e.get("attack_delta"),e.get("health_delta"),e.get("value")]:
			if v is Dictionary and v.has("unit_stat"):
				if v.unit_stat.target=="attack_target" and not (a.trigger in ["on_attack","after_attack","after_action"] or a.trigger=="on_reveal" and (body.is_empty() or body.get("counter_trigger")=="enemy_unit_attacked")): return "该时机没有攻击目标"
				if v.unit_stat.target=="effect_target" and not e.op in ["set_attack","damage","heal","modify_stats","modify_stacks","set_stacks"]: return "结算目标属性仅用于设置攻击力"
		if e.op=="schedule":
			if e.get("repeat")=="each_event" and not e.trigger in ["next_own_unit_deployed","next_own_order_played","next_own_unit_entered","next_own_unit_attacked_hq"]: return "每次事件监听需要事件时机"
			if e.get("repeat")=="each_turn" and not e.trigger in ["next_own_turn_start","next_opponent_turn_start"]: return "每回合监听需要回合时机"
			if e.has("after_turns") and not e.trigger in ["next_own_turn_start","next_opponent_turn_start"]: return "事件监听不设置回合延迟"
		if e.op=="grant_ability":
			var child_body := {"kind":"unit","play_target":null}
			var error := _extended_error(e.ability,child_body)
			if not error.is_empty(): return error
			for rule in e.ability.effects:
				if rule.get("target")=="self" and e.ability.trigger=="on_death": return "阵亡附加效果没有自身目标"
				if rule.op=="modify_stats" and rule.attack_delta==0 and rule.health_delta==0: return "属性修改不能全为零"
				if rule.has("on_kill_summon"): return "附加能力不使用来源卡衍生模板"
	if a.has("after_turns") and not a.trigger in ["next_own_turn_start","next_opponent_turn_start"]: return "延迟回合数仅用于后续回合开始"
	for e in a.effects:
		if e.op in ["if_drawn","if_killed","schedule"]:
			if e.op=="schedule":
				if a.trigger=="while_active": return "延迟效果不能放入持续光环"
				if e.get("lifetime")=="source" and not body.is_empty() and body.get("kind")!="unit": return "来源在场期限需要单位"
				if e.get("lifetime")=="target" and not effect_leaves(e.effects).any(_effect_chooses): return "目标在场期限需要绑定 chosen"
				if e.has("times") and not e.get("repeat") in ["each_turn","each_event"]: return "重复次数仅用于每回合延迟效果"
			var child: Dictionary=a.duplicate(true);child.effects=e.effects
			if e.op=="schedule": child={"trigger":e.trigger,"effects":e.effects,"_scheduled":true}
			var error:=_extended_error(child,body)
			if not error.is_empty():return error
	for path in _effect_paths(a.effects):
		var damage_seen:=false
		for e in path:
			if e.op=="if_killed" and not damage_seen: return "击杀结果须跟在同组伤害之后"
			if e.op=="damage": damage_seen=true
	if a.has("event_scope") and not a.trigger in ["own_unit_moved","own_unit_retreated","own_unit_returned","own_unit_attacked","own_unit_entered","own_unit_deployed","own_unit_died"]: return "事件筛选需要友方单位事件"
	for e in a.effects:
		if e.op=="unit_limit" and (a.trigger!="while_active" or not body.is_empty() and body.get("kind")!="field"): return "单位上限仅用于场地持续效果"
		if e.op=="liberate" and (not body.is_empty() and body.get("kind")!="unit" or a.trigger in ["on_death","on_leave","on_reveal","while_active"]): return "解放需要仍在场的单位"
		if e.op=="transfer_card" and e.has("entry") and not (e.source=="deck" and e.mode=="move" and e.destination=="support"): return "部署方式仅用于从牌库进入后援线"
	if a.has("repeat"):
		if a.trigger == "while_active": return "持续光环不能重复结算"
		if a.repeat is Dictionary and not _count_names_valid(a.repeat.count_units): return "单位名称筛选不能含首尾空格或控制字符"
	if body.get("kind") == "hq":
		if not a.trigger in ["while_active","own_turn_start","own_turn_end","opponent_turn_start","opponent_turn_end","own_unit_deployed","enemy_unit_deployed","own_order_played","enemy_order_played","own_card_played","enemy_card_played","own_unit_died","enemy_unit_died","on_attack","own_unit_entered","enemy_unit_entered","own_unit_attacked_hq","enemy_unit_attacked_hq","own_unit_became_veteran","enemy_unit_became_veteran","on_veteran","own_unit_attacked","enemy_unit_attacked","own_unit_retreated","enemy_unit_retreated","own_unit_returned","enemy_unit_returned","on_leave"]: return "总部时机无效"
		if a.has("target") and a.target.get("timing","deploy") != "trigger": return "总部在触发时选择目标"
	var choices: Array = a.effects.filter(func(e): return e.op == "choose_effect")
	if not choices.is_empty():
		if choices.size()>1 or a.trigger=="while_active": return "每个非持续效果组最多一次抉择"
		for e in choices:
			for option in e.options:
				if option.has("premise") and (_premise_nodes(option.premise)>24 or not _premise_names_valid(option.premise)): return "抉择条件无效或过于复杂"
				if not _plain(option.label): return "抉择标题含控制字符"
				if option.effects.any(func(x): return x.op=="choose_effect"): return "抉择不能嵌套"
				if option.has("target"):
					var branch := {"trigger":"on_play","target":option.target,"effects":option.effects}
					var failure := _extended_error(branch,body)
					if not failure.is_empty(): return failure
					if not option.effects.any(_effect_chooses): return "分支选择需要选定目标效果"
		for path in _effect_paths(a.effects):
			var branch: Dictionary = a.duplicate(true)
			branch.effects = path
			var error := _extended_error(branch,body)
			if not error.is_empty(): return error
		return ""
	for e in a.effects:
		if e.has("unit_filter"):
			if e.get("target") in ["own_hq","enemy_hq"]: return "单位筛选仅用于触发效果的单位目标"
			for k in ["card_name","name_contains"]:
				if e.unit_filter.has(k) and (not _plain(e.unit_filter[k]) or e.unit_filter[k]!=e.unit_filter[k].strip_edges() or e.unit_filter[k].strip_edges().is_empty()): return "单位名称筛选不能含首尾空格"
	if a.has("premise") and not _premise_names_valid(a.premise):return "层数名称无效"
	if a.trigger in ["after_attack","after_move","after_action","on_attack","on_veteran","on_leave"] and not body.is_empty() and body.get("kind")!="unit":return "行动后时机只能用于单位"
	if a.trigger=="on_stack_gained":
		if not _stack_name(a.get("stack","")) or not body.is_empty() and body.get("kind")!="unit":return "获得层数事件需要单位与明确层数名称"
	elif a.has("stack"):return "层数名称只用于获得层数事件"
	for e in a.effects:
		if e.op=="prepare_counter" and e.duration=="battle" and not body.is_empty() and body.get("kind")!="unit": return "在场期间的反制预备需要单位"
		if e.op == "modify_incoming_damage" and not e.amount is Dictionary and e.amount == 0 and not e.has("multiplier") and not e.get("immune",false): return "受到伤害的变化不能为零"
		if e.op in ["modify_stacks","set_stacks"]:
			if not _stack_name(e.stack):return "层数名称需为1—32字，无首尾空格及控制字符"
			if not e.amount is Dictionary and abs(int(e.amount))>(100 if e.stack=="heavy_armor" else 99):return "层数操作超出范围（重甲100，自定义99）"
			if a.trigger=="while_active" and e.stack!="heavy_armor":return "自定义层数不支持持续光环"
		if e.op=="remove_hand" and (e.card_name!=e.card_name.strip_edges() or not _plain(e.card_name)):return "移除手牌需准确卡名"
		if e.op in ["shuffle_into_deck","tax_opponent_plays"] and a.trigger=="while_active":return "洗入牌库和征收费用是一次性效果，不能作为持续光环"
		for v in [e.get("amount"),e.get("attack_delta"),e.get("health_delta"),e.get("value")]:
			if not v is Dictionary or not (v.has("stack_count") or v.has("unit_stat")):continue
			var q:Dictionary=v.get("stack_count",v.get("unit_stat",{}))
			if v.has("stack_count") and not _stack_name(q.stack):return "层数名称无效"
			if a.trigger=="while_active":return "光环不能读取单位属性或层数"
			if q.target=="self" and not body.is_empty() and body.get("kind")!="unit":return "没有自身单位可读取"
			var selector:Variant=a.get("target",body.get("play_target"))
			if q.target=="chosen" and (selector==null and not body.is_empty() or selector is Dictionary and selector.get("include_hq",false)):return "读取所选单位需要不含总部的目标"
			if q.target=="trigger_unit" and not a.trigger in ["own_unit_deployed","next_own_unit_deployed","enemy_unit_deployed","after_attacked","own_unit_moved","enemy_unit_moved","on_kill","on_attacked","on_damaged","after_attack","after_move","after_action","on_attack","own_unit_entered","enemy_unit_entered","own_unit_attacked_hq","enemy_unit_attacked_hq","own_unit_became_veteran","enemy_unit_became_veteran","on_veteran","own_unit_attacked","enemy_unit_attacked","own_unit_retreated","enemy_unit_retreated","own_unit_returned","enemy_unit_returned","on_leave"]:return "此事件没有可读取的触发单位"

	for selector in [a.get("target"),body.get("play_target")]:
		if selector is Dictionary and (selector.has("unit_classes") or selector.has("faction_id")) and selector.get("include_hq",false): return "兵种目标不能同时选择总部"
	for e in a.effects:
		if e.get("target") == "adjacent_to_self" and not body.is_empty() and body.get("kind","unit") != "unit": return "自身相邻目标需要来源单位"
		if e.get("target") in ["adjacent_to_chosen","chosen_and_adjacent"] and a.get("target",body.get("play_target") if body.get("play_target") is Dictionary else {}).get("include_hq",false): return "相邻效果的中心目标必须是单位"
	for q in _premise_unit_queries(a.get("premise",{})):
		if a.trigger == "while_active" and not _keyword_aura(a) and not (q.test=="unit_state" and q.target=="self" and q.state in ["in_front","in_support"]): return "持续状态前提支持自身前线/后援线位置；自身词条条件仅用于固定攻击力光环"
		if q.target == "chosen" and (a.trigger != "on_play" or a.has("target") or (not body.is_empty() and (body.get("play_target") == null or body.play_target.get("include_hq",false)))): return "所选单位状态前提需要登场共用 play_target，且不包含总部"
		if q.target == "self" and (a.trigger in ["on_death","on_reveal"] or (not body.is_empty() and body.get("kind","unit") != "unit")): return "自身状态前提需要仍在场的来源单位"
		if q.target == "trigger_unit" and (not a.trigger in ["on_reveal","own_unit_deployed","next_own_unit_deployed","enemy_unit_deployed","after_attacked","own_unit_moved","enemy_unit_moved","on_kill","on_attacked","on_damaged","on_stack_gained","after_attack","after_move","after_action","on_attack","own_unit_entered","enemy_unit_entered","own_unit_attacked_hq","enemy_unit_attacked_hq","own_unit_became_veteran","enemy_unit_became_veteran","on_veteran","own_unit_attacked","enemy_unit_attacked","own_unit_retreated","enemy_unit_retreated","own_unit_returned","enemy_unit_returned","on_leave"] or (a.trigger == "on_reveal" and body.get("counter_trigger") == "enemy_order_played")): return "此事件没有可查询的触发单位"
	var events := ["on_keyword_lost","own_unit_deployed","enemy_unit_deployed","own_order_played","enemy_order_played","own_card_played","enemy_card_played","after_attacked","own_unit_moved","enemy_unit_moved","on_kill","on_attacked","on_damaged","on_stack_gained","after_attack","after_move","after_action","own_unit_died","enemy_unit_died","on_attack","own_unit_entered","enemy_unit_entered","own_unit_attacked_hq","enemy_unit_attacked_hq","own_unit_became_veteran","enemy_unit_became_veteran","on_veteran","own_unit_attacked","enemy_unit_attacked","own_unit_retreated","enemy_unit_retreated","own_unit_returned","enemy_unit_returned","on_leave"]
	if a.has("damage_step") and a.trigger != "on_damaged": return "累计损伤阈值仅用于受伤后"
	if a.has("limit") and a.trigger!="on_activate" and not a.trigger in events: return "次数限制仅用于事件监听"
	if not a.get("_scheduled",false) and a.trigger.begins_with("next_") and not body.is_empty() and body.get("kind","unit") != "order": return "延迟预留仅用于指令"
	if a.has("target") and (a.trigger.begins_with("next_") or a.trigger in events) and a.target.get("timing","deploy") != "trigger": return "事件目标须在触发时选择"
	if a.trigger == "while_active":
		if a.has("limit") or a.has("damage_step") or a.has("target"): return "持续效果不能包含次数或目标选择"
		if a.has("premise") and not _keyword_aura(a) and not _aura_premise(a.premise): return "持续前提仅允许战场和战线单位计数"
		for e in a.effects:
			if e.op=="unit_limit": continue
			if e.op=="modify_stats" and e.get("target")=="self" and e.health_delta!=0: return "自身持续攻防效果仅改变攻击力"
			for k in e.get("unit_filter",{}):
				if k in ["attack","health","keyword_id","without_keyword","attack_parity"]: return "光环筛选不能读取可被光环改变的属性或词条"
			for k in ["attack_delta","health_delta","amount"]:
				if e.get(k) is Dictionary and not ((body.is_empty() or body.get("kind")=="unit") and e.op=="modify_stats" and e.get("target")=="self" and e.health_delta==0): return "光环只支持固定数值"
			if e.get("target") in ["self","adjacent_to_self","all_other_friendly_units"] and not body.is_empty() and body.get("kind")!="unit": return "自身或相邻光环需要单位来源"
			if e.get("target") in ["own_hq","enemy_hq"] and e.op!="modify_incoming_damage": return "总部光环仅支持受伤修正"
			if a.has("premise") and e.op=="modify_stats" and e.health_delta!=0: return "条件光环不改变防御"
	for index in a.effects.size():
		var e: Dictionary = a.effects[index]
		if e.op in ["discard","modify_cards","develop"]:
			for key in ["card_name","name_contains"]:
				if e.get("filter",{}).has(key) and (not _plain(e.filter[key]) or e.filter[key] != e.filter[key].strip_edges()): return "卡名筛选不能含控制字符或首尾空格"
		if e.op == "develop" and ((e.source == "tokens") != e.has("token_ids") or e.source == "tokens" and e.has("filter")): return "衍生卡开发需 token_ids，起始牌组开发使用 filter"
		if e.op == "return_to_hand" and ((e.has("cost_delta") != e.has("duration")) or e.get("cost_delta",1)==0): return "回手费用变化需同时指定非零费用变化和持续时间"
		if e.op == "modify_hand_cost":
			if e.cost_delta==0: return "费用变化不能为零"
			for k in ["card_name","name_contains"]:
				if e.get("filter",{}).has(k) and (not _plain(e.filter[k]) or e.filter[k]!=e.filter[k].strip_edges()): return "卡名筛选不能带首尾空格"
		if e.op == "modify_cards":
			if e.filter.get("kind","unit") != "unit": return "跨区域强化仅用于单位卡"
			if e.filter.get("same_as_discarded",false) and not a.effects.slice(0,index).any(func(x):return x.op == "discard" and x.amount == 1): return "同名强化需在同一组先弃置一张牌"
			if e.get("attack_delta",0) == 0 and e.get("health_delta",0) == 0 and e.get("operation_cost_delta",0) == 0 and e.get("grant_abilities",[]).is_empty(): return "强化不能为空"
			for granted in e.get("grant_abilities",[]):
				for rule in granted.effects:
					if rule.get("target") == "self" and granted.trigger == "on_death": return "阵亡附加效果没有自身目标"
					if rule.op == "modify_stats" and rule.attack_delta == 0 and rule.health_delta == 0: return "属性修改不能全为零"
					if rule.op == "modify_operation_cost" and rule.get("cost_delta",1) == 0: return "行动费修改不能为零"
	for e in a.effects:
		if e.op=="modify_stats" and e.get("health_mode")=="max_only" and (not _integer(e.health_delta) or e.health_delta==0): return "防御上限变化需要非零整数"
		if e.has("on_kill_summon") and (e.target in ["own_hq","enemy_hq"] or e.target == "chosen" and a.get("target",body.get("play_target",{}) if body.get("play_target") is Dictionary else {}).get("include_hq",false)): return "击杀后召唤仅支持单位目标"
		if e.op == "transfer_card":
			if e.has("copy_buff"):
				if e.mode!="copy" or not e.destination in ["support","source_position"]: return "复制强化仅用于将复制单位召唤到场上"
				if e.copy_buff.attack_delta==0 and e.copy_buff.health_delta==0: return "复制强化不能同时为零"
			if e.has("fallback_sources") and (e.mode!="copy" or e.destination!="hand" or not e.source in ["deck","discard","hand"] or e.source in e.fallback_sources): return "后备来源仅用于牌库、弃牌区、手牌复制到手牌，来源不能重复"
			if e.get("player")=="opponent" and not e.source in ["deck","hand","discard","starting_deck"]: return "对方来源只允许明确卡池"
			if e.has("deck_position") and e.destination!="deck": return "牌库位置仅用于放入牌库"
			if e.has("overflow") and e.destination!="hand": return "满手牌改放牌库顶仅用于加入手牌"
			if e.selection=="chosen" and not e.source in ["deck","hand","discard","starting_deck"]: return "手选需要明确卡池"
			if e.has("inherit_from") and e.mode != "copy": return "强化继承筛选仅用于复制"
			var sources := {}
			for ref in e.get("inherit_from",[]):
				if sources.has(ref.card_id): return "强化来源不能重复"
				sources[ref.card_id]=true
			if e.source == "starting_deck" and e.mode != "copy": return "起始牌组池只允许复制"
			if e.source == "drawn" and e.mode != "move": return "本次抽牌只能移动"
			if e.source=="self" and e.mode=="move" and (a.trigger!="on_death" or not e.destination in ["hand","deck"] or e.amount!=1 or e.has("filter") or e.selection!="random" or not body.is_empty() and body.get("kind")!="unit"): return "原卡回手仅用于单位阵亡，移动自身一张到手牌"
			if e.destination == "source_position" and not body.is_empty() and body.get("kind","unit") != "unit": return "原位置召唤需要来源单位"
			var f: Dictionary=e.get("filter",{})
			if f.has("min_cost") and f.has("max_cost") and f.min_cost > f.max_cost: return "费用范围倒置"
			if (f.get("event_faction",false) or f.has("event_cost_distance")) and not a.trigger in ["own_order_played","enemy_order_played","own_card_played","enemy_card_played","next_own_order_played","next_own_unit_deployed","own_unit_deployed","enemy_unit_deployed","own_unit_died","enemy_unit_died","after_action","after_attack","after_move","on_attack","own_unit_entered","enemy_unit_entered","own_unit_attacked_hq","enemy_unit_attacked_hq","own_unit_became_veteran","enemy_unit_became_veteran","on_veteran","own_unit_attacked","enemy_unit_attacked","own_unit_retreated","enemy_unit_retreated","own_unit_returned","enemy_unit_returned","on_leave"]: return "事件卡筛选须在卡牌事件使用"
			if f.has("card_name") and not _plain(f.card_name): return "卡名含控制字符"
		if e.op in ["equip","unequip"] and not _plain(e.tag): return "装备名含控制字符"
	if a.get("target",{}).get("include_hq",false):
		if a.target.row != "any": return "总部目标战线须选任意"
		for e in a.effects:
			if e.get("target") == "chosen" and not e.op in ["damage","heal","modify_incoming_damage","grant_order_target_reward"]: return "总部目标仅允许伤害或治疗"
	if body.get("play_target") is Dictionary and body.play_target.get("include_hq",false) and a.trigger == "on_play" and not a.has("target"):
		if body.play_target.row != "any": return "总部目标战线须选任意"
		for e in a.effects:
			if e.get("target") == "chosen" and not e.op in ["damage","heal","modify_incoming_damage","grant_order_target_reward"]: return "总部目标仅允许伤害或治疗"
	return ""

static func _aura_premise(p: Dictionary) -> bool:
	if p.test=="unit_state": return p.target=="self" and p.state in ["in_front","in_support"]
	if p.test=="destroyed_by": return false
	if str(p).contains("keyword_id") or str(p).contains("attack") or str(p).contains("health"): return false
	if _premise_unit_queries(p).any(func(q):return not (q.test=="unit_state" and q.target=="self" and q.state in ["in_front","in_support"])):return false
	if p.test == "not": return _aura_premise(p.item)
	if p.test in ["all","any"]:
		for item in p.items:
			if not _aura_premise(item): return false
		return true
	for v in [p.left,p.right]:
		if v is Dictionary and not v.has("count_units") and not v.has("max_unit_stat") and not v.stat in ["enemy_unit_count","friendly_unit_count","other_friendly_unit_count","enemy_front_count","friendly_front_count","enemy_support_count","friendly_support_count"]: return false
	return true

static func _transfer_text(e: Dictionary) -> String:
	if e.has("copy_buff"):
		var base: Dictionary=e.duplicate(true);base.erase("copy_buff")
		return _transfer_text(base)+"，该复制%+d/%+d（%s）"%[e.copy_buff.attack_delta,e.copy_buff.health_delta,"永久" if e.copy_buff.duration=="match" else "在场期间"]
	if e.source=="attack_target": return "将被攻击单位的%d张复制%s%s" % [e.amount,{"hand":"加入手牌","deck":"洗入牌库","support":"召唤至后援线","source_position":"召唤至原位置"}[e.destination],"（保留当前攻击、防御上限与费用）" if e.get("copy_state")=="current_stats" else ""]
	if e.amount is Dictionary and e.amount.get("stat")=="selected_destroyed_count": return "从己方弃牌区随机召唤等量%s单位" % ("【%s】"%e.get("filter",{}).get("name_contains") if e.get("filter",{}).has("name_contains") else "")
	if e.get("player")=="opponent":
		var local: Dictionary=e.duplicate(true);local.erase("player")
		return _transfer_text(local).replace("己方","敌方").replace("手动选择","由敌方选择")
	if e.get("entry")=="deploy": return "从己方牌库%s%d张单位，免费部署" % ["选择" if e.selection=="chosen" else "随机选择",e.amount]
	if e.source=="self" and e.mode=="move": return ("将阵亡原卡返回己方手牌" if e.destination=="hand" else "将阵亡原卡放入牌库"+{"top":"顶","bottom":"底","random":"随机位置"}[e.get("deck_position","random")])+("；手牌满则改放牌库顶" if e.has("overflow") else "")
	if e.source == "self" and not e.has("filter"):
		var where: String = {"hand":"加入己方手牌","deck":"洗入己方牌库","support":"召唤至己方后援线","source_position":"召唤至原位置"}[e.destination]
		return "将自身的%d张复制%s%s" % [e.amount,where,_copy_inheritance_text(e)]
	var sources: Dictionary={"event_card":"触发事件的卡牌","deck":"己方牌组","discard":"己方弃牌区","hand":"当前手牌","self":"本卡","drawn":"本组刚抽到的手牌","starting_deck":"己方起始牌组卡池"}
	var dest: Dictionary={"deck":"己方牌组随机位置","hand":"己方手牌","support":"己方后援线","source_position":"来源单位原位置"}
	var f: Dictionary=e.get("filter",{})
	var filters:=PackedStringArray()
	if f.has("card_name"): filters.append("【%s】" % f.card_name)
	if f.has("faction_id"): filters.append("指定阵营")
	if f.has("sin") or f.has("sins") or f.has("exclude_sins"): filters.append(_sin_filter_text(f))
	if f.has("unit_class"): filters.append(unit_class_text([f.unit_class]))
	elif f.has("kind"): filters.append({"unit":"单位","order":"指令","counter":"反制","field":"场地"}.get(f.kind,f.kind))
	if f.get("event_faction",false): filters.append("与事件卡同阵营")
	if f.has("event_cost_distance"): filters.append("费用相差不超过%d" % int(f.event_cost_distance))
	var fallback := PackedStringArray()
	for source in e.get("fallback_sources",[]): fallback.append({"deck":"牌库","discard":"弃牌区","hand":"手牌"}[source])
	var method: String={"chosen":"选择","top":"按顺序","random":"随机","highest_cost":"随机选择费用最高的"}[e.selection]
	return "从%s%s%s%d张%s卡牌，放入%s" % [sources[e.source],method,"复制" if e.mode=="copy" else "取出",e.amount,"、".join(filters),dest[e.destination]] + (_copy_inheritance_text(e) if e.mode == "copy" else "") + ("；无符合牌则依次从%s寻找" % "、".join(fallback) if not fallback.is_empty() else "")


static func unit_class_text(classes: Array) -> String:
	if classes.is_empty() or classes.size() == 5: return "单位"
	if classes.size() == 2 and classes.has("fighter") and classes.has("bomber"): return "空军"
	if classes.size() == 3 and classes.has("infantry") and classes.has("tank") and classes.has("artillery"): return "陆军"
	var names := PackedStringArray()
	for c in classes: names.append({"infantry":"步兵","tank":"坦克","artillery":"炮兵","fighter":"战斗机","bomber":"轰炸机"}[c])
	return "、".join(names)

static func count_text(s: Dictionary) -> String:
	return _filter_detail(s) + {"ally":"己方","enemy":"敌方","any":"双方"}[s.side]+{"any":"在场","front":"前线","support":"后援线"}[s.get("row","any")]+("【%s】" % s.card_name if s.has("card_name") else "名称含【%s】的" % s.name_contains if s.has("name_contains") else "")+unit_class_text(s.get("unit_classes",[]))+("种数（同名只计一次）" if s.get("distinct_by")=="name" else "数")

static func _compact_rules(text: String) -> String:
	var literal_names := PackedStringArray()
	var name_pattern := RegEx.create_from_string("【[^】]*】")
	for item in name_pattern.search_all(text):
		var literal: String = item.get_string()
		if not literal in literal_names: literal_names.append(literal)
	for index in literal_names.size(): text=text.replace(literal_names[index],"\uE000%d\uE001" % index)
	text=text.replace("的点伤害","的伤害")
	text=text.replace("本次在场期间","在场期间")
	for side in ["己方","敌方"]:
		var other := "敌方" if side == "己方" else "己方"
		text=text.replace(side+"在场单位数大于"+other+"在场单位数",side+"在场单位更多").replace(side+"在场单位数小于"+other+"在场单位数",side+"在场单位更少").replace(side+"在场单位数等于"+other+"在场单位数","双方在场单位一样多")
	for turns in range(1,4):
		text=text.replace("压制所有友方单位（各自后续%d回合结束时解除）；压制所有敌方单位（各自后续%d回合结束时解除）" % [turns,turns],"压制所有单位（各自后续%d回合结束时解除）" % turns)
		text=text.replace("压制所有友方单位，直至其后续%d个回合结束；压制所有敌方单位，直至其后续%d个回合结束" % [turns,turns],"压制所有单位（各自后续%d回合）" % turns)
	text=text.replace("抑制所有友方单位；抑制所有敌方单位","抑制所有单位")
	var previous := ""
	var output := PackedStringArray()
	for line in text.split("\n"):
		var at := line.find("：")
		var head := line.left(at) if at >= 0 else ""
		if not head.is_empty() and head == previous: line="　"+line.substr(at+1)
		else: previous=head
		output.append(line)
	text="\n".join(output)
	for index in literal_names.size(): text=text.replace("\uE000%d\uE001" % index,literal_names[index])
	return text

static func display_definition(card: Dictionary) -> Dictionary:
	var d: Dictionary = card.definition.duplicate(true)
	d["_printed"] = card.get("source",card.definition).duplicate(true)
	d["_keyword_info"] = card.get("display_keywords",builtin_keywords()).duplicate(true)
	for ref in d._printed.keywords:
		d._printed.abilities.append_array(ref.get("abilities",[]).duplicate(true))
	d._printed.abilities.append_array(card.get("match_abilities",[]).duplicate(true))
	d._printed.abilities.append_array(card.get("pending_abilities",[]).duplicate(true))
	for saved in card.get("match_layers",[]) + card.get("pending_layers",[]):
		var layer: Dictionary = saved.layer
		match saved.bucket:
			"modifiers":
				d.attack += int(layer.attack_delta)
				d.health += int(layer.health_delta)
			"operation_costs": d.operation_cost = int(layer.cost_set) if layer.has("cost_set") else int(d.operation_cost)+int(layer.cost_delta)
	d.abilities.append_array(card.get("match_abilities",[]).duplicate(true))
	d.abilities.append_array(card.get("pending_abilities",[]).duplicate(true))
	d.attack=clampi(int(d.attack),0,30)
	d.health=clampi(int(d.health),0,30)
	d.operation_cost=clampi(int(d.operation_cost),0,12)
	return d

static func _card_filter_text(filter: Dictionary) -> String:
	return ("与所弃卡同名的" if filter.get("same_as_discarded",false) else "名称含【%s】的" % filter.name_contains if filter.has("name_contains") else "【%s】" % filter.card_name if filter.has("card_name") else "") + ("单位" if filter.get("kind") == "unit" else "")

static func _modify_cards_text(effect: Dictionary, definition: Dictionary) -> String:
	var zones := PackedStringArray()
	for zone in effect.zones: zones.append({"battlefield":"场上","hand":"手牌","deck":"牌组"}[zone])
	var changes := PackedStringArray()
	if effect.get("attack_delta",0) != 0 or effect.get("health_delta",0) != 0: changes.append("%+d/%+d" % [effect.get("attack_delta",0),effect.get("health_delta",0)])
	if effect.get("operation_cost_delta",0) != 0: changes.append("行动费%+d" % effect.operation_cost_delta)
	for ability in effect.get("grant_abilities",[]):
		var d := definition.duplicate(true)
		d.kind = "unit"
		d.keywords = []
		d.play_target = null
		d.abilities = [ability]
		changes.append("获得“%s”" % rules_text(d))
	return "%s强化%s%s中%s单位：%s" % ["永久" if effect.duration == "match" else "在场期间",{"owner":"己方","opponent":"敌方","both":"双方"}[effect.player],"、".join(zones),_card_filter_text(effect.filter).trim_suffix("单位"),"，".join(changes)]


static func definition_classes(d: Dictionary) -> Array:
	if d.get("kind","unit") != "unit": return []
	var result: Array = [d.unit_class]
	for a in d.get("abilities",[]):
		if a.trigger != "on_play" or a.has("premise"): continue
		for e in a.effects:
			if e.op == "grant_unit_class" and e.target == "self" and e.duration in ["battle","match"] and not e.unit_class in result: result.append(e.unit_class)
	return result

static func _copy_inheritance_text(e: Dictionary) -> String:
	if not e.has("inherit_from"): return "（保留永久强化）"
	if e.inherit_from.is_empty(): return "（不继承强化）"
	var names:=PackedStringArray()
	for ref in e.inherit_from: names.append("【%s】"%ref.name)
	return "（仅继承%s的永久强化）"%"、".join(names)

static func _incoming_rule_text(effect: Dictionary, target: String, duration: String) -> String:
	if effect.get("immune",false): return target+"免疫"+{"combat":"战斗","effect":"效果","both":""}[effect.damage_kind]+"伤害（"+duration+"）"
	var kind: String=("来自"+unit_class_text(effect.source_unit_classes)+"的" if effect.has("source_unit_classes") else "")+{"combat":"战斗","effect":"效果","both":""}[effect.damage_kind]
	var times: String="，伤害×%d" % effect.multiplier if effect.has("multiplier") else ""
	if effect.has("source_kind"): kind=("己方" if effect.get("source_side")=="ally" else "敌方" if effect.get("source_side")=="enemy" else "")+{"unit":"单位","order":"指令","counter":"反制","field":"场地","hq":"总部"}[effect.source_kind]+"造成的"+kind
	if effect.amount is Dictionary:
		var rule: Dictionary=effect.amount.attack_gap
		return "%s攻击力每高出伤害来源单位%d点，受到的%s伤害-%d%s（%s）"%[target,rule.step,kind,rule.reduction,times,duration]
	return "%s受到的%s伤害%s%s（%s）"%[target,kind,"%+d"%int(effect.amount) if effect.amount!=0 else "",times,duration]

static func short_text(text: String) -> String:
	var literals := PackedStringArray()
	for found in RegEx.create_from_string("【[^】]*】").search_all(text):
		if not found.get_string() in literals: literals.append(found.get_string())
	for i in literals.size(): text=text.replace(literals[i],"\uE000%d\uE001"%i)
	for pair in preload("res://scripts/core/card_text_rules.gd").RULES:
		text=RegEx.create_from_string(pair[0]).sub(text,pair[1],true)
	for i in literals.size(): text=text.replace("\uE000%d\uE001"%i,literals[i])
	return text.strip_edges()

static func print_definition(d: Dictionary) -> Dictionary:
	return d.get("_printed",d)

static func keyword_labels(d: Dictionary) -> Array:
	var labels: Array=[]
	for entry in builtin_keywords()+d.get("_keyword_info",[]):
		if not str(entry.name) in labels: labels.append(str(entry.name))
	return labels

static func custom_rules_text(d: Dictionary) -> String:
	return str(print_definition(d).get("display_text","")).strip_edges()

static func short_rules_text(d: Dictionary) -> String:
	var manual:=custom_rules_text(d)
	if not manual.is_empty(): return manual
	var printed: Dictionary=print_definition(d).duplicate(true)
	var refs: Array=printed.get("keywords",[])
	printed.keywords=[]
	var text:=short_text(rules_text(printed))
	if printed.get("kind") in ["order","field"]: text=text.trim_prefix("使用时：").trim_prefix("生效时：")
	if printed.get("kind")=="counter":
		text=RegEx.create_from_string("伏置：([^\n]+?)触发一次[^\n]*\n触发时：").sub(text,"$1：")
	var labels:=PackedStringArray()
	for ref in refs:
		var title:=keyword_name(ref.id)
		for entry in d.get("_keyword_info",[]):
			if entry.id==ref.id and int(entry.version)==int(ref.version): title=entry.name
		if not ref.params.is_empty():
			var values:=PackedStringArray()
			for value in ref.params.values(): values.append(str(int(value)))
			title += " "+"/".join(values)
		labels.append(title)
	if text in ["无额外能力","无额外能力。"]: text=""
	return "\n".join(labels)+( "\n" if not labels.is_empty() and not text.is_empty() else "")+text

static func detailed_rules_text(d: Dictionary) -> String:
	var manual:=custom_rules_text(d)
	var text:=(manual+"\n\n实际机制\n" if not manual.is_empty() else "")+rules_text(d)
	var descriptions:=PackedStringArray()
	for ref in print_definition(d).get("keywords",[]):
		for entry in d.get("_keyword_info",builtin_keywords()):
			if entry.id==ref.id and int(entry.version)==int(ref.version):
				descriptions.append(entry.name+"："+keyword_description(str(entry.id),str(entry.description)))
	return text+("\n\n词条说明\n"+"\n".join(descriptions) if not descriptions.is_empty() else "")

static func keyword_description(id: String, original: String) -> String:
	# Display current battle rules without rewriting frozen keyword definitions/hashes.
	if id=="core.smokescreen": return "不能被普通攻击选中；主动攻击或移动后失去。位于前线时不生效；烟幕生效期间，守护失效。指令和技能仍可影响。"
	if id=="core.guard": return "保护同阵线相邻单位或总部。炮兵、轰炸机无视守护；烟幕生效期间，守护失效。"
	return original

static func bold_rules_text(text: String, d: Dictionary) -> String:
	var labels:=keyword_labels(d)
	labels.sort_custom(func(a,b):return a.length()>b.length())
	var result:=""
	var at:=0
	while at<text.length():
		var found:=""
		for label in labels:
			if text.substr(at).begins_with(label): found=label;break
		if not found.is_empty(): result+="[b]"+found.replace("[","[lb]") +"[/b]";at+=found.length()
		else: result+=text[at].replace("[","[lb]");at+=1
	return result

static func _filter_detail(f: Dictionary) -> String:
	var text: String=("老兵" if f.is_veteran else "非老兵") if f.has("is_veteran") else ""
	text += {"front":"前线的","support":"后援线的"}.get(f.get("row"),"")
	if f.has("is_liberated"): text+=("已解放的" if f.is_liberated else "未解放的")
	if f.has("generated_by"): text+="缴获的"
	if f.has("without_keyword"): text+="不具有"+keyword_name(f.without_keyword)+"的"
	if f.has("keyword_id"): text+="具有"+keyword_name(f.keyword_id)+"的"
	for key in ["attack","health"]:
		if f.has(key): text+=("攻击力" if key=="attack" else "防御力")+{"gt":"大于","gte":"不少于","eq":"等于","ne":"不等于","lte":"不多于","lt":"小于"}[f[key].cmp]+str(f[key].value)+"的"
	if f.has("attack_parity"): text+="攻击力为"+("偶" if f.attack_parity=="even" else "奇")+"数的"
	if f.has("adjacent_to"): text+=("自身" if f.adjacent_to=="self" else "所选单位")+"左右相邻的"
	return _sin_filter_text(f)+("费用"+{"gt":"大于","gte":"不少于","eq":"等于","ne":"不等于","lte":"不多于","lt":"小于"}[f.cost.cmp]+str(f.cost.value)+"的" if f.has("cost") else "")+text

static func _valid_parameter(value: Variant, spec: Dictionary) -> bool:
	if spec.type=="token":
		var r := RegEx.new();r.compile("^[a-z][a-z0-9_]{0,31}$")
		return value is String and r.search(value)!=null
	return _integer(value) and value>=spec.minimum and value<=spec.maximum

static func _unbound_effects(effects: Array) -> Array:
	var result := []
	for e in effects:
		if e.op in ["if_drawn","if_killed","schedule"]:result.append_array(_unbound_effects(e.effects))
		elif e.op=="choose_effect":
			for option in e.options:
				if not option.has("target"):result.append_array(_unbound_effects(option.effects))
		else:result.append(e)
	return result

static func _sin_filter_text(f: Dictionary) -> String:
	var names: Dictionary={"wrath":"暴怒","lust":"色欲","sloth":"怠惰","gluttony":"暴食","gloom":"忧郁","pride":"傲慢","envy":"嫉妒"}
	var text: String=(str(names.get(f.sin,"无罪孽"))+"的") if f.has("sin") else ""
	for key in ["sins","exclude_sins"]:
		if f.has(key): text+=("非" if key=="exclude_sins" else "")+"、".join(f[key].map(func(x):return names.get(x,"无罪孽")))+"的"
	return text

static func _played_card_filter_text(f: Dictionary) -> String:
	return ("【"+f.card_name+"】" if f.has("card_name") else "名称含【"+f.name_contains+"】的" if f.has("name_contains") else "")+_sin_filter_text(f)+str({"unit":"单位","order":"指令","field":"场地","counter":"反制"}.get(f.get("kind"),"牌"))
