class_name SinCatalog
extends RefCounted
const IDS := ["wrath","lust","sloth","gluttony","gloom","pride","envy"]
const ENTRIES = [{"id":"wrath","name":"暴怒","color":"#421812"},{"id":"lust","name":"色欲","color":"#573018"},{"id":"sloth","name":"怠惰","color":"#6b4206"},{"id":"gluttony","name":"暴食","color":"#2d3f15"},{"id":"gloom","name":"忧郁","color":"#172f36"},{"id":"pride","name":"傲慢","color":"#0e263f"},{"id":"envy","name":"嫉妒","color":"#321d3f"}]
static var icons: Dictionary = {}
static func valid(value: Variant) -> bool:
	return value == null or value is String and (value.is_empty() or value in IDS)
static func id_of(spec: Dictionary) -> String:
	var value: Variant = spec.get("sin")
	return value if value is String and value in IDS else ""
static func label(id: String) -> String:
	for entry in ENTRIES:
		if entry.id == id: return entry.name
	return "未选择罪孽"
static func color_for(spec: Dictionary) -> Color:
	for entry in ENTRIES:
		if entry.id == id_of(spec): return Color(entry.color)
	return Color("303538")
static func icon(id: String) -> Texture2D:
	if not id in IDS: return null
	if not icons.has(id): icons[id] = load("res://assets/sins/"+id+".png")
	return icons[id]
