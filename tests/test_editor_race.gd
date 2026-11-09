extends SceneTree
## Delayed in-memory AppStore transport: no HTTP or model requests are sent.

class DelayedStore:
	extends AppStore
	signal released
	var calls: Array = []
	var canceled: Array = []
	func _ready() -> void:
		keyword_definitions = CardRuntime.builtin_keywords()
		online = true
		model_configured = true
	func refresh() -> void:
		pass
	func create_draft(definition: Dictionary) -> Dictionary:
		return await _pending("draft", definition)
	func confirm_draft(value: Dictionary) -> Dictionary:
		return await _pending("confirm", value)
	func request(endpoint: String, method: int = HTTPClient.METHOD_GET, payload: Dictionary = {}) -> Dictionary:
		if method == HTTPClient.METHOD_DELETE:
			canceled.append(endpoint)
			return {"ok":true,"data":{"status":"canceled"}}
		return await _pending("http", {"endpoint":endpoint,"method":method,"payload":payload})
	func _pending(kind: String, payload: Dictionary) -> Dictionary:
		var call := {"kind":kind,"payload":payload.duplicate(true),"done":false,"result":{}}
		calls.append(call)
		while not call.done:
			await released
		return call.result
	func release(index: int, value: Dictionary) -> void:
		calls[index].result = value
		calls[index].done = true
		released.emit()

class EditorHarness:
	extends "res://scripts/main.gd"
	func _ready() -> void:
		pass
	func _render() -> void:
		pass
	func _navigate(destination: String) -> void:
		page = destination

var app: EditorHarness
var transport: DelayedStore
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("EDITOR_RACE_FAIL: " + description)

func _run() -> void:
	app = EditorHarness.new()
	root.add_child(app)
	transport = DelayedStore.new()
	app.add_child(transport)
	app.store = transport
	app.content = VBoxContainer.new()
	app.add_child(app.content)
	app.page = "workshop"
	_test_control_bindings()
	await _test_preview_races()
	await _test_generation_races()
	await _test_confirmation_race()
	check(transport.calls.all(func(call): return call.done), "Every delayed stub operation was released")
	print("EDITOR_RACE_RESULT checks=%d failures=%d" % [checks, failures])
	app.queue_free()
	await process_frame
	quit(1 if failures else 0)

func _test_control_bindings() -> void:
	app._manual_workshop(app.content)
	var revision := app.editor_revision
	for line in app.content.find_children("*", "LineEdit", true, false):
		if line.placeholder_text == "卡牌名称（必填）":
			line.text_changed.emit("控制测试")
			check(app.manual.name == "控制测试" and app.editor_revision == revision + 1, "Name control invalidates editor revision")
			revision = app.editor_revision
	for spin in app.content.find_children("*", "SpinBox", true, false):
		spin.value_changed.emit(spin.value + 1)
		check(app.editor_revision == revision + 1, "Numeric control invalidates editor revision")
		revision = app.editor_revision
	for option in app.content.find_children("*", "OptionButton", true, false):
		option.item_selected.emit(1)
		check(app.editor_revision == revision + 1, "Kind / trigger / effect control invalidates revision")
		revision = app.editor_revision
	for toggle in app.content.find_children("*", "CheckButton", true, false):
		toggle.toggled.emit(true)
		check(app.editor_revision == revision + 1, "Builtin keyword control invalidates revision")
		revision = app.editor_revision
	for editor in app.content.find_children("*", "TextEdit", true, false):
		editor.text = "[ ]"
		editor.text_changed.emit()
		check(app.editor_revision == revision + 1, "Keyword JSON editor invalidates revision")
		revision = app.editor_revision
	app._edit_json("{\"new\":true}")
	check(app.editor_revision == revision + 1, "JSON import replacement invalidates revision")
	app.pending_editor_revision = app.editor_revision
	app.pending_source = "preserved"
	app._edit_manual("cost", 9)
	check(app.pending_editor_revision != app.editor_revision and app.pending_source == "preserved", "Card edit preserves old keyword dependency revision for stale detection")
	app._set_work_mode(2)
	check(app.draft.is_empty() and not app.busy, "Switching editor mode invalidates old operation")

func _test_preview_races() -> void:
	var old := transport.calls.size()
	app._preview_definition({"name":"old"})
	check(app.busy, "Preview enters busy before transport resolves")
	app._edit_manual("name", "new")
	check(not app.busy and app.draft.is_empty(), "Editing releases old request ownership and clears preview")
	var newer := transport.calls.size()
	app._preview_definition({"name":"new"})
	transport.release(old, preview("old"))
	await process_frame
	check(app.busy and app.draft.is_empty(), "Late old preview cannot clear newer busy or publish old draft")
	transport.release(newer, preview("new"))
	await process_frame
	check(not app.busy and app.draft.draft_id == "new", "Current preview completes normally")
	old = transport.calls.size()
	app._preview_definition({"name":"old failure"})
	app._edit_json("new JSON input")
	newer = transport.calls.size()
	app._preview_definition({"name":"latest"})
	transport.release(newer, preview("latest"))
	await process_frame
	transport.release(old, {"ok":false,"error":"late failure"})
	await process_frame
	check(app.draft.draft_id == "latest" and not app.busy and app.info_text != "late failure", "Late failed preview cannot erase newer completed draft")

func _test_generation_races() -> void:
	var old := transport.calls.size()
	app._start_generation({"source_text":"old description"})
	app._edit_manual("attack", 10)
	var newer := transport.calls.size()
	app._preview_definition({"name":"while creating"})
	transport.release(old, {"ok":true,"data":{"generation_id":"late-created-job"}})
	await process_frame
	check(app.busy and app.generation_id.is_empty(), "Late task creation cannot replace current editor request")
	check(transport.canceled.has("/v1/card-generations/late-created-job"), "Canceled editor also cancels a late-created backend job")
	transport.release(newer, preview("while creating"))
	await process_frame
	app.request_epoch += 1
	app.busy = true
	app._poll_card_job("old-before-timer", app.request_epoch, app.editor_revision)
	app._edit_manual("health", 11)
	newer = transport.calls.size()
	app._preview_definition({"name":"new busy"})
	await create_timer(1.15).timeout
	check(app.busy and transport.calls.size() == newer + 1, "Old polling timer does not clear new busy or send stale HTTP")
	transport.release(newer, preview("new busy"))
	await process_frame
	app.request_epoch += 1
	app.busy = true
	old = transport.calls.size()
	app._poll_card_job("old-http", app.request_epoch, app.editor_revision)
	await create_timer(1.15).timeout
	check(transport.calls.size() == old + 1 and transport.calls[old].payload.endpoint.ends_with("old-http"), "Polling uses its captured job ID")
	app._edit_manual("cost", 10)
	newer = transport.calls.size()
	app._preview_definition({"name":"after HTTP edit"})
	transport.release(old, {"ok":true,"data":{"status":"ready","result":{"draft_id":"stale-model"}}})
	await process_frame
	check(app.busy and app.draft.is_empty(), "Late HTTP result cannot release new busy or insert stale model draft")
	transport.release(newer, preview("after HTTP edit"))
	await process_frame
	# Defensive case: a revision changes without the normal invalidate helper.
	app.request_epoch += 1
	app.busy = true
	old = transport.calls.size()
	app._poll_card_job("revision-only", app.request_epoch, app.editor_revision)
	await create_timer(1.15).timeout
	app.editor_revision += 1
	transport.release(old, {"ok":true,"data":{"status":"ready","result":{"draft_id":"revision-stale"}}})
	await process_frame
	check(not app.busy and app.draft.draft_id == "after HTTP edit", "Revision-only stale result releases only its own busy and preserves existing newer draft")

func _test_confirmation_race() -> void:
	app.draft = {"draft_id":"approved-before-edit","draft_hash":"old"}
	var confirmation := transport.calls.size()
	app._confirm_card()
	app._edit_manual("name", "new after confirm")
	var newer := transport.calls.size()
	app._preview_definition({"name":"new after confirm"})
	transport.release(newer, preview("new after confirm"))
	await process_frame
	transport.release(confirmation, {"ok":true})
	await process_frame
	check(app.draft.draft_id == "new after confirm" and not app.busy, "Late confirmation receipt cannot clear newer preview")
	check(transport.calls[confirmation].payload.draft_id == "approved-before-edit", "Confirmation sends a frozen copy of the reviewed draft")

func preview(id: String) -> Dictionary:
	return {"ok":true,"draft":{"draft_id":id,"draft_hash":id,"definition":{"name":id}}}
