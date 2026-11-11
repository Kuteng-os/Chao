extends "res://tests/test_engine.gd"
## Run: godot --headless --path . --script tests/test_inspector010.gd
## Stat and cost sources for the long-hover inspector, and the keyword glossary shared by inspectors and tooltips.

func _initialize() -> void:
	_stat_sources()
	_cost_sources()
	_glossary()
	print("INSPECTOR 010: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _named(name: String, kind := "unit") -> Dictionary:
	return _compile(_base(name, kind))

func _parts(data: Dictionary) -> Array:
	return data.parts.map(func(part): return "%s|%s|%s" % [part.get("amount", part.get("set")), part.source, part.note])

func _stat_sources() -> void:
	var g := _game()
	var seat := _rich(g)
	var unit: Dictionary = g._new_unit(seat, _named("受益单位"))
	var banner: Dictionary = g._new_unit(seat, _named("战旗"))
	g._reset_budget()
	g._effect({"op":"modify_stats","target":"chosen","attack_delta":2,"health_delta":0,"duration":"end_of_turn"}, g._context(seat, banner.uid, banner.card, unit.uid))
	g._effect({"op":"modify_stats","target":"chosen","attack_delta":0,"health_delta":3,"duration":"battle"}, g._context(seat, -1, _named("补给"), unit.uid))
	g._effect({"op":"modify_operation_cost","target":"chosen","cost_delta":-1,"duration":"battle"}, g._context(seat, -1, _named("急行军"), unit.uid))
	var aura_spec := _base("指挥所")
	aura_spec.abilities = [{"trigger":"while_active","effects":[{"op":"modify_stats","target":"all_friendly_units","attack_delta":1,"health_delta":0,"duration":"battle"}]}]
	g._new_unit(seat, _compile(aura_spec))
	g._recompute(g._unit(unit.uid))
	var data: Dictionary = g.stat_breakdown(g._unit(unit.uid))
	_check(data.attack.base == 3 and data.attack.total == 6, "attack 3 + 2 + aura 1: " + str(data.attack))
	_check(_parts(data.attack).has("2|战旗|本回合"), "a temporary buff names its card and duration: " + str(_parts(data.attack)))
	_check(_parts(data.attack).has("1|指挥所|持续"), "an aura names its source unit")
	_check(_parts(data.health).has("3|补给|"), "a lasting buff names its card")
	_check(data.operation_cost.total == 0 and _parts(data.operation_cost).has("-1|急行军|"), "operation cost changes are explained")
	g._reset_budget()
	g._effect({"op":"damage","target":"chosen","amount":2}, g._context(1-seat, -1, _named("炮击"), unit.uid))
	data = g.stat_breakdown(g._unit(unit.uid))
	_check(data.health.damage == 2 and data.health.current == data.health.total - 2, "damage taken is reported separately from the health cap")
	var plain: Dictionary = g._new_unit(seat, _named("未改变"))
	var untouched: Dictionary = g.stat_breakdown(plain)
	_check(untouched.health.parts.is_empty() and untouched.operation_cost.parts.is_empty(), "an unchanged unit has nothing to explain apart from shared auras")

func _cost_sources() -> void:
	var g := _game()
	var seat := _rich(g)
	var spec := _base("贵重单位")
	spec.cost = 5
	var card := _compile(spec)
	g.state.players[seat].hand.append({"instance_id":"hand-card","card":card})
	g._reset_budget()
	g._effect({"op":"modify_hand_cost","selection":"all","cost_delta":-2,"duration":"hand"}, g._context(seat, -1, _named("后勤")))
	var held: Dictionary = g._hand(seat, "hand-card").card
	var data: Dictionary = g.cost_breakdown(seat, held)
	_check(data.base == 5 and data.total == 3, "printed 5, now 3: " + str(data))
	_check(_parts(data).has("-2|后勤|"), "the cost change names its card: " + str(_parts(data)))

func _glossary() -> void:
	var spec := _base("词条单位")
	spec.keywords = [{"id":"core.guard","version":2,"params":{}}]
	var compiled := _compile(spec)
	var display: Dictionary = Runtime.display_definition(compiled)
	var glossary: Array = Runtime.keyword_glossary(display, ["core.blitz"])
	_check(glossary.size() == 2, "printed and granted keywords are both listed: " + str(glossary.map(func(e): return e.name)))
	_check(glossary[0].name == "守护" and not glossary[0].granted and not str(glossary[0].description).is_empty(), "printed keyword with its description")
	_check(glossary[1].granted, "granted keyword is marked")
	var text := Runtime.inspector_text(display, ["core.blitz"], [{"title":"数值变化","body":"攻击 5"}])
	_check(text.contains("词条") and text.contains("（获得）") and text.contains("数值变化"), "inspector text has the glossary and the extra section")
	_check(not Runtime.inspector_text(display, [], [{"title":"数值变化","body":""}]).contains("数值变化"), "empty sections are left out")
