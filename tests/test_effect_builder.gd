extends SceneTree
## Real effect-builder controls and compiler; transport and persistence stay in memory.
## No network service, player profile, confirmed library or model quota is used.

class MemoryStore:
	extends AppStore
	signal released
	var calls: Array = []
	var previews: Array = []
	var saves := 0
	var hold_generation := false
	var pending: Dictionary = {}
	func _ready() -> void:
		keyword_definitions = CardRuntime.builtin_keywords()
		online = false
		model_configured = false
	func refresh() -> void:
		pass
	func save_profile() -> bool:
		saves += 1
		return true
	func create_draft(definition: Dictionary) -> Dictionary:
		previews.append(definition.duplicate(true))
		var compiled := CardRuntime.compile_card(definition, keyword_definitions)
		if not compiled.ok: return {"ok":false,"error":compiled.error}
		return {"ok":true,"draft":{"draft_id":"local-effects-test","draft_hash":compiled.definition_hash,"definition":compiled.source,"compiled":compiled}}
	func request(endpoint: String, method: int = HTTPClient.METHOD_GET, payload: Dictionary = {}) -> Dictionary:
		calls.append({"endpoint":endpoint,"method":method,"payload":payload.duplicate(true)})
		if method == HTTPClient.METHOD_DELETE: return {"ok":true,"data":{"status":"canceled"}}
		if hold_generation and endpoint == "/v1/card-generations":
			while pending.is_empty(): await released
			return pending
		return {"ok":false,"error":"Test transport does not invoke a provider"}

var app: Control
var memory: MemoryStore
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("EFFECT_BUILDER_FAIL: " + description)

func _run() -> void:
	app = load("res://tests/creator_harness.gd").new()
	root.add_child(app)
	app.content = VBoxContainer.new()
	app.add_child(app.content)
	app.page = "workshop"
	memory = MemoryStore.new()
	app.add_child(memory)
	app.store = memory
	_test_add_and_limit()
	_test_parameter_controls()
	_test_trigger_controls()
	_test_grouping_and_order()
	await _test_direct_preview()
	await _test_edit_and_delete()
	await _test_order_conversion()
	await _test_invalid_effect_budget()
	await _test_frozen_generation_and_late_response()
	_check(memory.saves == 0 and memory.cards.is_empty(), "Previews and canceled generation never persist or publish")
	print("EFFECT_BUILDER_RESULT checks=%d failures=%d" % [checks, failures])
	app.queue_free()
	await process_frame
	quit(1 if failures else 0)

func _reset() -> void:
	app._invalidate_card_editor()
	app.manual.merge({"name":"效果测试单位","kind":0,"cost":3,"operation_cost":1,"attack":2,"health":3}, true)
	app.creator_keywords.clear()
	app.creator_effects.clear()
	app.source_text = ""
	memory.calls.clear()
	memory.previews.clear()
	memory.hold_generation = false
	memory.pending.clear()
	_clear_form()

func _clear_form() -> void:
	for child in app.content.get_children():
		app.content.remove_child(child)
		child.queue_free()

func _row(index: int = 0) -> Array:
	_clear_form()
	app._creator_effect_row(app.content, index)
	var choices: Array = app.content.find_children("*", "OptionButton", true, false)
	var amounts: Array = app.content.find_children("*", "SpinBox", true, false)
	var deletes: Array = app.content.find_children("*", "Button", true, false).filter(func(button): return button.text == "×")
	return [choices[0], choices[1], amounts[0], deletes[0]]

func _test_add_and_limit() -> void:
	_reset()
	app.draft = {"draft_id":"old"}
	var revision: int = app.editor_revision
	app._add_creator_effect()
	_check(app.creator_effects == [{"trigger":"on_play","op":"draw","amount":1}], "Add creates a concrete draw-one effect")
	_check(app.draft.is_empty() and app.editor_revision == revision + 1, "Add invalidates the previous draft")
	for index in 11: app._add_creator_effect()
	revision = app.editor_revision
	app._add_creator_effect()
	_check(app.creator_effects.size() == 12 and app.editor_revision == revision, "Add stops at twelve effects without changing the draft revision")
	app._text_workshop(app.content)
	var add_buttons: Array = app.content.find_children("*", "Button", true, false).filter(func(button): return button.text == "＋ 添加效果")
	_check(add_buttons.size() == 1 and add_buttons[0].disabled, "Actual add control is disabled at twelve effects")
	_check(app._creator_abilities().size() == 3, "Twelve same-trigger effects fit three bounded abilities")

func _test_parameter_controls() -> void:
	_reset()
	var examples := [
		{"op":"draw","max":3,"expected":{"op":"draw","amount":3,"player":"owner"}},
		{"op":"heal","max":10,"expected":{"op":"heal","amount":10,"target":"own_hq"}},
		{"op":"damage","max":10,"expected":{"op":"damage","amount":10,"target":"enemy_hq"}},
		{"op":"gain_kredits","max":3,"expected":{"op":"gain_kredits","amount":3}}
	]
	for example in examples:
		app.creator_effects = [{"trigger":"on_play","op":example.op,"amount":1}]
		var controls := _row()
		var spin: SpinBox = controls[2]
		_check(spin.min_value == 1 and spin.max_value == example.max and spin.step == 1, "Integer UI bounds for " + example.op)
		spin.value = example.max + 5
		_check(app.creator_effects[0].amount == example.max, "Real spin control caps " + example.op)
		_check(app._creator_abilities()[0].effects[0] == example.expected, "Effect has correct owner or HQ target for " + example.op)
		spin.value = 0
		_check(app.creator_effects[0].amount == 1, "Real spin control requires a positive amount for " + example.op)
	app.creator_effects = [{"trigger":"on_play","op":"heal","amount":10}]
	var controls := _row()
	app.draft = {"draft_id":"before-operation-change"}
	controls[1].item_selected.emit(0)
	_check(app.creator_effects[0].op == "draw" and app.creator_effects[0].amount == 3, "Changing heal-ten to draw clamps the retained amount")
	_check(app.draft.is_empty(), "Operation selector invalidates the old preview")
	var revision: int = app.editor_revision
	app._edit_creator_effect(-1, "amount", 2)
	app._edit_creator_effect(99, "amount", 2)
	app._edit_creator_effect(0, "amount", 3)
	_check(app.editor_revision == revision, "Invalid indices and unchanged values do not invalidate the editor")

func _test_trigger_controls() -> void:
	_reset()
	app._add_creator_effect()
	var controls := _row()
	var trigger: OptionButton = controls[0]
	_check(not trigger.disabled and trigger.item_count == 4, "Units expose all four supported triggers")
	var names := ["on_play","own_turn_start","own_turn_end","on_death"]
	for index in names.size():
		trigger.item_selected.emit(index)
		_check(app._creator_abilities()[0].trigger == names[index], "Actual trigger selector maps " + names[index])
	var compiled := CardRuntime.compile_card(app._basic_card_definition(), memory.keyword_definitions)
	_check(compiled.ok, "On-death draw effect compiles through the real runtime")

func _test_grouping_and_order() -> void:
	_reset()
	app.creator_effects = [
		{"trigger":"on_play","op":"draw","amount":1},
		{"trigger":"on_death","op":"heal","amount":2},
		{"trigger":"on_play","op":"damage","amount":3},
		{"trigger":"own_turn_start","op":"gain_kredits","amount":2},
		{"trigger":"on_play","op":"heal","amount":4},
		{"trigger":"on_death","op":"damage","amount":5}
	]
	var abilities: Array = app._creator_abilities()
	_check(abilities.map(func(ability): return ability.trigger) == ["on_play","on_death","own_turn_start"], "Trigger groups keep first appearance order")
	_check(abilities[0].effects.map(func(effect): return effect.op) == ["draw","damage","heal"], "Interleaved trigger groups preserve same-trigger effect order")
	_check(abilities[1].effects[0].amount == 2 and abilities[1].effects[1].amount == 5, "Interleaved effects retain their independent parameters")
	var definition: Dictionary = app._basic_card_definition()
	var compiled := CardRuntime.compile_card(definition, memory.keyword_definitions)
	_check(compiled.ok and compiled.source.abilities == abilities, "Mixed triggers compile without reordering the source")
	app.creator_effects.clear()
	for index in 5: app.creator_effects.append({"trigger":"on_play","op":"heal","amount":index + 1})
	abilities = app._creator_abilities()
	_check(abilities.size() == 2 and abilities[0].effects.size() == 4 and abilities[1].effects.size() == 1, "Fifth effect starts a second ability instead of violating four-effect schema")
	var flattened: Array = abilities[0].effects + abilities[1].effects
	_check(flattened.map(func(effect): return effect.amount) == [1,2,3,4,5], "Chunking preserves exact effect sequence across the boundary")
	compiled = CardRuntime.compile_card(app._basic_card_definition(), memory.keyword_definitions)
	_check(compiled.ok, "Five-effect composition passes the actual compiler")
	var frozen: Dictionary = app._card_blueprint()
	app.creator_effects[0].amount = 9
	_check(frozen.abilities[0].effects[0].amount == 1, "Blueprint abilities do not alias editable effect rows")
	frozen.abilities[0].effects[1].amount = 8
	_check(app.creator_effects[1].amount == 2, "Mutating a blueprint does not change editable effect rows")

func _test_direct_preview() -> void:
	_reset()
	app.creator_effects = [{"trigger":"on_play","op":"draw","amount":2},{"trigger":"on_play","op":"damage","amount":3}]
	app.creator_keywords["core.guard@1"] = {"id":"core.guard","version":1,"params":{}}
	app.source_text = " \n "
	for connected in [false, true]:
		memory.online = connected
		memory.model_configured = connected
		await app._generate_card()
		_check(not app.draft.is_empty() and not app.busy, "Configured effects preview with connection=" + str(connected))
		_check(memory.calls.is_empty(), "Whitespace-only optional text never calls a model endpoint")
		if not app.draft.is_empty():
			_check(app.draft.definition.abilities[0].effects == [{"op":"draw","amount":2,"player":"owner"},{"op":"damage","amount":3,"target":"enemy_hq"}], "Direct preview preserves configured effects")
			_check(app.draft.definition.keywords.size() == 1 and app.draft.compiled.ok, "Standard effects and registered keyword coexist")
	_check(memory.previews.size() == 2, "Both paths use manual preview transport, never generation")

func _test_edit_and_delete() -> void:
	_reset()
	app.creator_effects = [{"trigger":"on_play","op":"draw","amount":1},{"trigger":"on_play","op":"heal","amount":4}]
	await app._generate_card()
	var previous: Dictionary = app.draft.duplicate(true)
	var revision: int = app.editor_revision
	var controls := _row()
	controls[2].value_changed.emit(3)
	_check(app.draft.is_empty() and app.editor_revision == revision + 1, "Amount editing invalidates a previously compiled preview")
	_check(previous.definition.abilities[0].effects[0].amount == 1, "Compiled old preview remains an independent snapshot")
	await app._generate_card()
	_check(app.draft.definition.abilities[0].effects[0].amount == 3, "Re-preview compiles the updated parameter")
	revision = app.editor_revision
	controls = _row()
	controls[3].pressed.emit()
	_check(app.creator_effects == [{"trigger":"on_play","op":"heal","amount":4}] and app.draft.is_empty() and app.editor_revision == revision + 1, "Actual delete button removes only its row and invalidates preview")
	await app._generate_card()
	_check(app.draft.definition.abilities[0].effects.size() == 1 and app.draft.definition.abilities[0].effects[0].op == "heal", "Deleted effects cannot reappear in the next preview")

func _test_order_conversion() -> void:
	_reset()
	app.creator_effects = [{"trigger":"own_turn_start","op":"draw","amount":1},{"trigger":"on_death","op":"heal","amount":3}]
	app._edit_manual("kind", 5)
	_check(app.creator_effects.all(func(effect): return effect.trigger == "on_play"), "Changing to an order resets existing effect triggers")
	var controls := _row()
	_check(controls[0].disabled and controls[0].get_item_text(0) == "打出时", "Order effect UI locks the trigger to play")
	await app._generate_card()
	_check(not app.draft.is_empty() and app.draft.definition.kind == "order" and app.draft.definition.abilities[0].effects.size() == 2, "Configured order previews directly without AI")
	app.creator_effects[1].trigger = "on_death"
	_check(app._card_blueprint().abilities.size() == 1 and app._card_blueprint().abilities[0].trigger == "on_play", "Order blueprint normalizes stale row triggers as well")
	_check(memory.calls.is_empty(), "Order effects never invoke a model when optional text is empty")

func _test_invalid_effect_budget() -> void:
	_reset()
	app.creator_effects = [{"trigger":"on_play","op":"draw","amount":4}]
	await app._generate_card()
	_check(app.draft.is_empty() and not app.info_text.is_empty(), "Runtime rejects out-of-range effect data even if UI controls are bypassed")
	app.creator_effects.clear()
	for index in 13: app.creator_effects.append({"trigger":"on_play","op":"heal","amount":1})
	await app._generate_card()
	_check(app.draft.is_empty(), "Runtime total-effect budget remains authoritative after chunking")
	_check(memory.calls.is_empty(), "Invalid configurations fail locally without model fallback")

func _test_frozen_generation_and_late_response() -> void:
	_reset()
	app.creator_effects = [{"trigger":"on_play","op":"draw","amount":2},{"trigger":"own_turn_end","op":"gain_kredits","amount":1}]
	app.source_text = "另加一个需要模型理解的效果"
	memory.hold_generation = true
	app._generate_card()
	_check(app.busy and memory.calls.size() == 1, "Optional extra text starts one in-memory generation request")
	var sent: Dictionary = memory.calls[0].payload
	_check(memory.calls[0].endpoint == "/v1/card-generations" and sent.card_blueprint.abilities == app._creator_abilities(), "Generation freezes all configured abilities in the player blueprint")
	_check(sent.card_blueprint.attack == 2 and sent.source_text == app.source_text, "Fixed abilities accompany base stats and separate free text")
	var revision: int = app.editor_revision
	app._edit_creator_effect(0, "amount", 3)
	_check(not app.busy and app.draft.is_empty() and app.editor_revision == revision + 1, "Effect editing cancels the active editor context")
	_check(sent.card_blueprint.abilities[0].effects[0].amount == 2, "Sent generation blueprint is deeply frozen after effect edits")
	memory.pending = {"ok":true,"data":{"generation_id":"late-effects-generation"}}
	memory.released.emit()
	await process_frame
	_check(app.generation_id.is_empty() and app.draft.is_empty(), "Late model task cannot restore the obsolete effects")
	_check(memory.calls.any(func(call): return call.method == HTTPClient.METHOD_DELETE and call.endpoint == "/v1/card-generations/late-effects-generation"), "Late-created obsolete generation is canceled on the server")

