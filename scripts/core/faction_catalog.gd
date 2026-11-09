class_name FactionCatalog
extends RefCounted
## Cosmetic registry is separate from immutable card definitions and hashes.
static var entries: Dictionary = {}

static func parse(raw: Variant) -> Dictionary:
	var result := {}
	if not raw is Array: return result
	for entry in raw:
		if not entry is Dictionary or not entry.get("faction_id") is String or not entry.get("name") is String: continue
		if not entry.get("role") in ["major", "ally"] or not entry.get("color") is String or not Color.html_is_valid(entry.color): continue
		if entry.get("icon_id") != null and not CardArtCache.valid_id(str(entry.icon_id)): continue
		if entry.get("background_id") != null and not CardArtCache.valid_id(str(entry.background_id)): continue
		if not entry.get("category", "normal") in DeckRules.FACTION_CATEGORIES: continue
		result[entry.faction_id] = entry.duplicate(true)
		result[entry.faction_id]["category"] = entry.get("category", "normal")
	return result

static func info(spec: Dictionary) -> Dictionary:
	return entries.get(str(spec.get("faction_id", "")), {})

static func color_for(spec: Dictionary, fallback := Color("454d40")) -> Color:
	return Color.from_string(str(info(spec).get("color", "")), fallback)
