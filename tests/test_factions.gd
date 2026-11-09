extends SceneTree
var failures := 0
var checks := 0
const MAIN := "11111111-1111-4111-8111-111111111111"
const ALLY := "22222222-2222-4222-8222-222222222222"
const THIRD := "33333333-3333-4333-8333-333333333333"
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var registry := {MAIN:{"role":"major"},ALLY:{"role":"major"},THIRD:{"role":"ally"}}
	var deck: Array = []
	for i in 40: deck.append({"name":"测试 %d" % i,"faction_id":ALLY if i < 12 else MAIN,"rarity":"standard"})
	check(DeckRules.factions(deck,registry,MAIN,ALLY).error.is_empty(),"28 main + 12 allied accepted")
	check(DeckRules.factions(deck,registry,"","",true).main_faction_id==MAIN,"40 card composition infers correct main")
	deck[12].faction_id = ALLY
	check(DeckRules.factions(deck,registry,MAIN,ALLY).error.is_empty(),"13 non-main cards accepted")
	deck[12].faction_id = MAIN
	deck[0].rarity = "elite"
	check(DeckRules.factions(deck,registry,MAIN,ALLY).error.is_empty(),"Non-main elite accepted")
	deck[0].rarity = "standard"
	deck[12].rarity = "elite"
	check(DeckRules.factions(deck,registry,MAIN,ALLY).error.is_empty(),"Main elite allowed")
	deck[39].faction_id = THIRD
	check(DeckRules.factions(deck,registry,MAIN,ALLY).error.is_empty(),"Third faction accepted")
	check(not DeckRules.factions([{"name":"旧卡"}],registry,MAIN,ALLY).error.is_empty(),"Unassigned old versions cannot battle")
	check(DeckRules.factions([{"name":"援军","faction_id":THIRD}],registry,"","",true).main_faction_id==THIRD,"Legacy ally role may be nominal main")
	check(DeckRules.factions([{"name":"援军","faction_id":THIRD}],registry,MAIN).main_faction_id==MAIN,"Explicit main retained even with no matching cards")
	check(DeckRules.factions(deck,registry,THIRD,ALLY).ally_faction_id.is_empty(),"Legacy ally selection cleared")
	check(not DeckRules.factions(deck,registry,"unknown").error.is_empty(),"Nominal main must be registered")
	var definition: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://docs/cards/examples/valid_unit.json"))
	definition.keywords = []
	var original := CardRuntime.compile_card(definition,CardRuntime.builtin_keywords())
	definition["faction_id"] = MAIN
	var compiled := CardRuntime.compile_card(definition,CardRuntime.builtin_keywords())
	check(compiled.ok and compiled.source.faction_id==MAIN,"Faction id survives compilation")
	definition.erase("faction_id")
	check(CardRuntime.compile_card(definition,CardRuntime.builtin_keywords()).definition_hash==original.definition_hash,"Old source hash unchanged")
	print("FACTION_TEST_RESULT checks=%d failures=%d" % [checks,failures])
	quit(1 if failures else 0)
