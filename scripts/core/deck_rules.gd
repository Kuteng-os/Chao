class_name DeckRules
extends RefCounted
const DECK_SIZE := 40
const FACTION_CATEGORIES := ["large", "normal", "small"]
const FACTION_CATEGORY_NAMES := {"large":"大阵营", "normal":"普通阵营", "small":"小阵营"}
static func composition(cards: Array, registry: Dictionary, primary: String, secondary: String, complete := true) -> Dictionary:
	var result := {"error":"", "main_count":0, "ally_count":0, "neutral_count":0}
	if primary.is_empty() or secondary.is_empty() or not SinCatalog.valid(primary) or not SinCatalog.valid(secondary) or primary==secondary:
		result.error="请选择两种不同的主罪孽与副罪孽。"
		return result
	for card in cards:
		if not card is Dictionary: result.error="牌组包含无效卡牌。"; return result
		var d: Dictionary = card.get("source", card.get("definition", card))
		var title: String = str(d.get("name", "卡牌"))
		if d.get("kind")=="hq": result.error="总部应单独选择，不计入40张牌组。"; return result
		if d.get("sin")==null or d.get("sin")=="": result.neutral_count+=1; continue
		var slot := "main" if d.get("sin")==primary else "ally" if d.get("sin")==secondary else ""
		if slot.is_empty(): result.error="“%s”的罪孽不属于所选主、副罪孽。" % title; return result
		var id: String = str(d.get("faction_id", ""))
		if not id.is_empty() and not registry.has(id): result.error="“%s”的阵营不存在，请刷新卡库。" % title; return result
		var category: String = str(registry.get(id, {}).get("category", "normal"))
		if not category in FACTION_CATEGORIES: result.error="阵营类别无效，请刷新卡库。"; return result
		if category=="large" and slot=="ally": result.error="“%s”属于大阵营，不能计入副罪孽。" % title; return result
		if category=="small" and slot=="main": result.error="“%s”属于小阵营，不能计入主罪孽。" % title; return result
		result[slot+"_count"] += 1
	if cards.size()>40 or result.main_count>30 or result.ally_count>10 or (complete and cards.size()!=40):
		result.error="牌组需要30张主罪孽、10张副罪孽（无罪孽牌可补足）；当前主%d张、副%d张、通用%d张。" % [result.main_count,result.ally_count,result.neutral_count]
	return result
const RARITIES := ["standard", "limited", "special", "elite"]
const NAMES := {"standard":"普通", "limited":"限定", "special":"特殊", "elite":"精英"}
const LIMITS := {"standard":4, "limited":3, "special":2, "elite":1}
const COLORS := {"standard":Color("aeb7ad"), "limited":Color("ae9770"), "special":Color("9bb4c4"), "elite":Color("d0a45d")}
static func rarity(definition: Dictionary) -> String:
	return str(definition.get("rarity", "standard"))
static func limit(definition: Dictionary) -> int:
	return int(LIMITS.get(rarity(definition), 0))
static func name_key(definition: Dictionary) -> String:
	return CardRuntime.normalize_text(str(definition.get("name", ""))).strip_edges().to_lower()
static func check_copies(cards: Array) -> String:
	var groups := {}
	for card in cards:
		if not card is Dictionary: return "牌组包含无效卡牌。"
		var raw: Variant = card.get("source", card.get("definition", card))
		if not raw is Dictionary or not raw.get("name") is String: return "卡牌缺少名称。"
		var definition: Dictionary = card.get("source", card.get("definition", card))
		if definition.get("kind")=="hq": return "总部应单独选择，不计入40张牌组。"
		if not can_include(definition): return "“%s”是衍生卡，尚未获准加入牌组。" % definition.name
		var maximum := limit(definition)
		if maximum == 0: return "卡牌稀有度无效。"
		var keys: Array = ["name:" + name_key(definition)]
		if card.has("card_id"):
			var origin: String = str(card.get("server_origin", ""))
			var reference: Dictionary = card.get("cloud_refs", {}).get(origin, {})
			keys.append("id:" + origin + ":" + str(reference.get("card_id", card.card_id)))
		for key in keys:
			var group: Dictionary = groups.get(key, {"count":0, "limit":4})
			group.count += 1
			group.limit = mini(group.limit, maximum)
			groups[key] = group
			if group.count > group.limit: return "“%s”最多携带 %d 张。" % [definition.name, group.limit]
	return ""

static func factions(cards: Array, registry: Dictionary, main_id: String = "", _ally_id: String = "", infer := false) -> Dictionary:
	var counts := {}
	for card in cards:
		if not card is Dictionary: return {"error":"牌组包含无效卡牌。"}
		var d: Dictionary = card.get("source", card.get("definition", card))
		var id: String = str(d.get("faction_id", ""))
		if id.is_empty(): continue
		if not registry.has(id): return {"error":"“%s”尚未指定已登记阵营。" % str(d.get("name", "卡牌"))}
		counts[id] = int(counts.get(id, 0)) + 1
	if infer and main_id.is_empty() and not counts.is_empty():
		var ids: Array = counts.keys()
		ids.sort_custom(func(a, b): return str(a) < str(b) if counts[a] == counts[b] else counts[a] > counts[b])
		main_id = ids[0]
	if not main_id.is_empty() and not registry.has(main_id): return {"error":"请选择已登记的主国。"}
	return {"error":"", "main_faction_id":main_id, "ally_faction_id":"", "ally_count":cards.size()-int(counts.get(main_id,0))}

static func can_include(definition: Dictionary) -> bool:
	return definition.get("deck_building", "allowed") != "generated_only"
