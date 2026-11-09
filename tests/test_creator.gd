extends SceneTree
## Exercises the real creator controls against in-memory transports only.
## No HTTP, DeepSeek, saved profiles, or confirmed card library are used.

class OfflineStore:
	extends AppStore
	var calls: Array = []
	var saves := 0
	func _ready() -> void:
		keyword_definitions = CardRuntime.builtin_keywords()
		keyword_definitions.append(JSON.parse_string(FileAccess.get_file_as_string("res://docs/cards/examples/keywords/example_supply.json")))
		online = false
		model_configured = false
	func refresh() -> void:
		pass
	func save_profile() -> bool:
		saves += 1
		return true
	func request(endpoint: String, method: int = HTTPClient.METHOD_GET, payload: Dictionary = {}) -> Dictionary:
		calls.append({"endpoint":endpoint,"method":method,"payload":payload.duplicate(true)})
		return {"ok":false,"error":"Unexpected network request in offline creator test"}

class DelayedStore:
	extends OfflineStore
	signal released
	var canceled: Array = []
	func _ready() -> void:
		super._ready()
		online = true
		model_configured = true
	func request(endpoint: String, method: int = HTTPClient.METHOD_GET, payload: Dictionary = {}) -> Dictionary:
		if method == HTTPClient.METHOD_DELETE:
			canceled.append(endpoint)
			return {"ok":true,"data":{"status":"canceled"}}
		var call := {"endpoint":endpoint,"method":method,"payload":payload.duplicate(true),"done":false,"result":{}}
		calls.append(call)
		while not call.done:
			await released
		return call.result
	func release(index: int, value: Dictionary) -> void:
		calls[index].result = value
		calls[index].done = true
		released.emit()

class CreatorHarness:
	extends "res://scripts/main.gd"
	func _ready() -> void:
		pass
	func _render() -> void:
		pass
	func _notify(text: String) -> void:
		info_text = text

var app: CreatorHarness
var offline: OfflineStore
var transport: DelayedStore
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("CREATOR_FAIL: " + description)

func _run() -> void:
	app = CreatorHarness.new()
	root.add_child(app)
	app.content = VBoxContainer.new()
	app.add_child(app.content)
	app.page = "workshop"
	offline = OfflineStore.new()
	app.add_child(offline)
	app.store = offline
	await _test_offline_plain_card()
	await _test_order_and_blank_name()
	await _test_keyword_compatibility_and_versions()
	transport = DelayedStore.new()
	app.add_child(transport)
	app.store = transport
	await _test_blueprint_and_numeric_edit()
	await _test_keyword_edits()
	await _test_clarification_chain()
	check(transport.calls.all(func(call): return call.done), "All delayed stub requests were completed")
	check(offline.saves == 0 and transport.saves == 0, "Creator previews never write player profiles")
	check(offline.cards.is_empty() and transport.cards.is_empty(), "Creator previews never publish a card")
	print("CREATOR_RESULT checks=%d failures=%d" % [checks, failures])
	app.queue_free()
	await process_frame
	quit(1 if failures else 0)

func _set_unit() -> void:
	app._invalidate_card_editor()
	app.manual.merge({"name":"  试验炮兵  ","kind":2,"cost":3,"operation_cost":0,"attack":2,"health":1}, true)
	app.creator_keywords = {
		"core.guard@1":{"id":"core.guard","version":1,"params":{}},
		"example.supply@1":{"id":"example.supply","version":1,"params":{"amount":2}}
	}
	app.source_text = ""

func _test_offline_plain_card() -> void:
	_set_unit()
	app.source_text = " \n "
	await app._generate_card()
	check(not app.busy and not app.draft.is_empty(), "Ordinary card previews offline with no configured model")
	check(offline.calls.is_empty(), "Empty optional effect never invokes HTTP or DeepSeek")
	if app.draft.is_empty(): return
	check(app.draft.get("local_only", false), "Ordinary card uses real local draft compiler")
	var definition: Dictionary = app.draft.definition
	check(definition.name == "试验炮兵" and definition.unit_class == "artillery", "Plain card keeps player name and artillery class")
	check(definition.cost == 3 and definition.operation_cost == 0 and definition.attack == 2 and definition.health == 1, "Plain card keeps exact 3 / 0 / 2 / 1 numeric values")
	check(definition.keywords.size() == 2 and definition.abilities.is_empty(), "Plain definition preserves selected builtin and parameterized keyword refs")
	var compiled := CardRuntime.compile_card(definition, app.draft.frozen_keywords)
	check(compiled.ok and compiled.definition.abilities[0].effects[0].amount == 2 and compiled.compiled_program_hash == app.draft.compiled_program_hash, "Registered keyword expands through actual compiler with selected amount")
	check(compiled.definition.keywords.any(func(ref): return ref.id == "core.guard"), "Guard survives compiled plain card preview")
	var frozen := app._card_blueprint()
	app.creator_keywords["example.supply@1"].params.amount = 3
	check(frozen.keywords[1].params.amount == 2, "Blueprint keyword params are copied independently of mutable editor state")

func _test_order_and_blank_name() -> void:
	_set_unit()
	app._edit_manual("kind", 5)
	app.creator_keywords.clear()
	var blueprint := app._card_blueprint()
	check(blueprint.kind == "order" and blueprint.unit_class == null, "Order selection removes unit class from blueprint")
	check(blueprint.operation_cost == 0 and blueprint.attack == 0 and blueprint.health == 0, "Order selection zeroes unit statistics despite retained unit form values")
	await app._generate_card()
	check(app.draft.is_empty() and not app.info_text.is_empty(), "Empty order is rejected locally because it has no effect")
	app.creator_keywords["example.supply@1"] = {"id":"example.supply","version":1,"params":{"amount":1}}
	await app._generate_card()
	check(not app.draft.is_empty() and app.draft.definition.appearance.emblem == "order", "Plain order compiles with order appearance")
	_clear_form()
	app._text_workshop(app.content)
	check(app.content.find_children("*", "SpinBox", true, false).size() == 1, "Order form shows only deployment cost")
	var type_control = app.content.find_children("*", "OptionButton", true, false)[0]
	var revision := app.editor_revision
	type_control.item_selected.emit(2)
	check(app.manual.kind == 2 and app.editor_revision == revision + 1, "Real type selector invalidates old order preview")
	check(app._card_blueprint().attack == 2 and app._card_blueprint().health == 1, "Switching back to unit preserves prior player numbers")
	app._edit_manual("name", "  ")
	await app._generate_card()
	check(app.draft.is_empty() and app.info_text == "请填写卡牌名称。" and offline.calls.is_empty(), "Unnamed plain card asks for name without invoking model")

func _test_blueprint_and_numeric_edit() -> void:
	_set_unit()
	_clear_form()
	app._text_workshop(app.content)
	var revision := app.editor_revision
	var effect_editor = app.content.find_children("*", "TextEdit", true, false)[0]
	effect_editor.text = "部署时抽一张牌"
	effect_editor.text_changed.emit()
	check(app.source_text == "部署时抽一张牌" and app.editor_revision == revision + 1, "Optional effect text control updates source and invalidates preview")
	var index := transport.calls.size()
	app._generate_card()
	check(app.busy and transport.calls.size() == index + 1, "Additional effect starts one generation request")
	var request: Dictionary = transport.calls[index]
	var payload: Dictionary = request.payload
	check(request.endpoint == "/v1/card-generations" and request.method == HTTPClient.METHOD_POST, "Additional effect POST uses generation endpoint")
	check(payload.card_blueprint == app._card_blueprint(), "Generation sends complete frozen player blueprint")
	check(payload.source_text == "部署时抽一张牌" and payload.clarification_answers.is_empty(), "Mechanism text stays separate from structured base values")
	check(payload.card_blueprint.keywords.size() == 2 and payload.card_blueprint.operation_cost == 0, "Selected keywords and zero action cost are present in AI request")
	revision = app.editor_revision
	var cost_spin = app.content.find_children("*", "SpinBox", true, false)[0]
	cost_spin.value_changed.emit(4)
	check(app.manual.cost == 4 and app.editor_revision == revision + 1 and not app.busy, "Actual numeric field releases and invalidates pending generation")
	check(payload.card_blueprint.cost == 3, "Sent blueprint remains frozen after numeric editing")
	transport.release(index, {"ok":true,"data":{"generation_id":"stale-numbers"}})
	await process_frame
	check(app.generation_id.is_empty() and app.draft.is_empty(), "Late generation creation cannot publish stale numeric input")
	check(transport.canceled.has("/v1/card-generations/stale-numbers"), "Late-created generation is canceled after numeric edit")

func _test_keyword_compatibility_and_versions() -> void:
	_set_unit()
	var original_definitions: Array = offline.keyword_definitions.duplicate(true)
	var supply: Dictionary = original_definitions[2]
	var turn_only: Dictionary = supply.duplicate(true)
	turn_only.merge({"id":"example.turn_supply","name":"回合补给"}, true)
	turn_only.implementation.abilities[0].trigger = "own_turn_start"
	var self_only: Dictionary = supply.duplicate(true)
	self_only.merge({"id":"example.self_heal","name":"自身修复","parameters":{}}, true)
	self_only.implementation.abilities[0].effects = [{"op":"heal","target":"self","amount":1}]
	check(CardRuntime.validate_keyword(turn_only).is_empty() and CardRuntime.validate_keyword(self_only).is_empty(), "Incompatible-order fixtures are genuine valid unit keywords")
	offline.keyword_definitions.append_array([turn_only, self_only])
	app.creator_keywords["example.turn_supply@1"] = {"id":"example.turn_supply","version":1,"params":{"amount":1}}
	app.creator_keywords["example.self_heal@1"] = {"id":"example.self_heal","version":1,"params":{}}
	app._edit_manual("kind", 5)
	check(app.creator_keywords.size() == 1 and app.creator_keywords.has("example.supply@1"), "Switch to order removes builtins, non-on-play and self-targeting selections while retaining compatible template")
	app._choose_card_keywords()
	for keyword_name in ["守护", "突击", "回合补给", "自身修复"]:
		var toggle := _keyword_toggle(keyword_name)
		check(toggle != null and toggle.disabled, "Order picker disables incompatible keyword: " + keyword_name)
	var supply_toggle := _keyword_toggle("补给")
	check(supply_toggle != null and not supply_toggle.disabled and supply_toggle.button_pressed, "Order picker keeps compatible selected on-play template enabled")
	await app._generate_card()
	check(not app.draft.is_empty() and app.draft.definition.kind == "order", "Type change leaves directly previewable compatible order keywords")
	app._close_modal()
	_set_unit()
	var new_version: Dictionary = supply.duplicate(true)
	new_version.version = 2
	offline.keyword_definitions.append(new_version)
	app._choose_card_keywords()
	var old_toggle := _keyword_toggle("补给 · v1")
	var latest_toggle := _keyword_toggle("补给")
	check(old_toggle != null and old_toggle.button_pressed and not old_toggle.disabled, "Selected old keyword version remains visible and removable after new version is registered")
	check(latest_toggle != null and not latest_toggle.button_pressed, "New latest keyword version appears separately from selected old version")
	var revision := app.editor_revision
	if old_toggle != null: old_toggle.toggled.emit(false)
	check(not app.creator_keywords.has("example.supply@1") and app.editor_revision == revision + 1, "Old-version checkbox can actually remove hidden-before-fix selection")
	# Re-select v1 before choosing v2 to exercise replacement rather than just addition.
	app.creator_keywords["example.supply@1"] = {"id":"example.supply","version":1,"params":{"amount":2}}
	app._choose_card_keywords()
	latest_toggle = _keyword_toggle("补给")
	revision = app.editor_revision
	if latest_toggle != null: latest_toggle.toggled.emit(true)
	await process_frame
	check(app.creator_keywords.has("example.supply@2") and not app.creator_keywords.has("example.supply@1") and app.editor_revision == revision + 1, "Choosing new version atomically replaces same-ID old reference and invalidates preview")
	check(app._card_blueprint().keywords.filter(func(ref): return ref.id == "example.supply").size() == 1, "Blueprint contains only one version for a selected keyword ID")
	check(_keyword_toggle("补给 · v1") == null and _keyword_toggle("补给").button_pressed, "Deferred picker rebuild reflects latest-only selection without stale checked old version")
	app._close_modal()
	offline.keyword_definitions = original_definitions
	await process_frame

func _test_keyword_edits() -> void:
	_set_unit()
	app.source_text = "部署时额外抽一张牌"
	var index := transport.calls.size()
	app._generate_card()
	transport.release(index, {"ok":true,"data":{"generation_id":"stale-keywords"}})
	await _wait_for_calls(index + 2)
	app._choose_card_keywords()
	var revision := app.editor_revision
	var guard = _keyword_toggle("守护")
	check(guard != null, "Registered guard appears in actual keyword picker")
	if guard != null: guard.toggled.emit(false)
	check(not app.creator_keywords.has("core.guard@1") and app.editor_revision == revision + 1 and not app.busy, "Keyword toggle invalidates in-flight generation")
	check(transport.canceled.has("/v1/card-generations/stale-keywords"), "Keyword change cancels known server generation")
	transport.release(index + 1, {"ok":true,"data":{"status":"ready","result":{"draft_id":"old-keywords"}}})
	await process_frame
	check(app.draft.is_empty() and app.generation_id.is_empty(), "Old ready result cannot restore removed keyword selection")
	index = transport.calls.size()
	app._generate_card()
	revision = app.editor_revision
	var amount_spin = app.overlay.find_children("*", "SpinBox", true, false)[0]
	amount_spin.value_changed.emit(3)
	check(app.creator_keywords["example.supply@1"].params.amount == 3 and app.editor_revision == revision + 1, "Actual keyword parameter control invalidates generation and updates chosen params")
	check(transport.calls[index].payload.card_blueprint.keywords[0].params.amount == 2, "In-flight request keeps old selected parameter frozen")
	transport.release(index, {"ok":true,"data":{"generation_id":"stale-parameter"}})
	await process_frame
	check(transport.canceled.has("/v1/card-generations/stale-parameter") and app.draft.is_empty(), "Keyword parameter edit cancels late-created task without stale preview")
	app._close_modal()

func _test_clarification_chain() -> void:
	_set_unit()
	app.source_text = "部署时抽牌，条件请继续询问"
	var revision := app.editor_revision
	var index := transport.calls.size()
	app._generate_card()
	var original_blueprint: Dictionary = transport.calls[index].payload.card_blueprint.duplicate(true)
	transport.release(index, {"ok":true,"data":{"generation_id":"round-one"}})
	await _wait_for_calls(index + 2)
	transport.release(index + 1, _clarification("draw_amount", "抽几张？"))
	await process_frame
	check(not app.busy and app.questions.size() == 1 and app.generation_id == "round-one", "First clarification keeps active parent generation")
	app.answers = {"draw_amount":"1 张"}
	index = transport.calls.size()
	app._answer_card()
	var payload: Dictionary = transport.calls[index].payload
	check(payload.parent_generation_id == "round-one" and not payload.has("card_blueprint"), "First continuation inherits frozen blueprint via parent without replacing it")
	check(payload.source_text == app.source_text and payload.editor_revision == revision, "First continuation keeps original effect source and revision")
	check(payload.clarification_answers == [{"question_id":"draw_amount","answer":"1 张"}], "First continuation submits answer linked to exact question")
	transport.release(index, {"ok":true,"data":{"generation_id":"round-two"}})
	await _wait_for_calls(index + 2)
	transport.release(index + 1, _clarification("condition", "什么条件？"))
	await process_frame
	check(app.questions.size() == 1 and app.questions[0].id == "condition" and app.answers.is_empty(), "Second clarification displays new question and resets old response fields")
	app.answers = {"condition":"无额外条件"}
	index = transport.calls.size()
	app._answer_card()
	payload = transport.calls[index].payload
	check(payload.parent_generation_id == "round-two" and not payload.has("card_blueprint"), "Second continuation links latest parent to preserve complete server ancestry")
	check(payload.clarification_answers == [{"question_id":"condition","answer":"无额外条件"}] and payload.source_text == app.source_text, "Second continuation carries current answer with original mechanism request")
	check(app._card_blueprint() == original_blueprint and app.editor_revision == revision, "Multiple clarification rounds do not mutate player numbers, name, or keyword selection")
	transport.release(index, {"ok":true,"data":{"generation_id":"round-three"}})
	await _wait_for_calls(index + 2)
	var definition := app._basic_card_definition()
	definition.abilities = [{"trigger":"on_play","effects":[{"op":"draw","player":"owner","amount":1}]}]
	var compiled := CardRuntime.compile_card(definition, transport.keyword_definitions)
	check(compiled.ok, "Mock ready response uses a genuinely compilable selected-keyword plus extra-effect card")
	transport.release(index + 1, {"ok":true,"data":{"status":"ready","result":{"draft_id":"completed-clarifications","draft_hash":compiled.definition_hash,"definition":compiled.source,"compiled":compiled}}})
	await process_frame
	check(not app.busy and app.draft.get("draft_id") == "completed-clarifications" and app.questions.is_empty(), "Final clarification response reaches preview without publishing")
	check(app.draft.definition.attack == 2 and app.draft.definition.keywords.size() == 2, "Completed preview retains player stats and selected keywords alongside extra effect")

func _clear_form() -> void:
	for child in app.content.get_children():
		app.content.remove_child(child)
		child.queue_free()

func _keyword_toggle(label: String) -> CheckButton:
	for toggle in app.overlay.find_children("*", "CheckButton", true, false):
		if toggle.text == label: return toggle
	return null

func _wait_for_calls(count: int) -> void:
	for attempt in range(100):
		if transport.calls.size() >= count: return
		await create_timer(0.03).timeout
	check(false, "Generation polling issued expected request within three seconds")

func _clarification(id: String, prompt: String) -> Dictionary:
	return {"ok":true,"data":{"status":"needs_clarification","result":{"questions":[{"id":id,"prompt":prompt,"options":[]}]}}}
