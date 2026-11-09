extends "res://tests/test_generated_cards.gd"

const MatchController = preload("res://scripts/network/match_controller.gd")
const StoreClass = preload("res://scripts/app_store.gd")

func _initialize() -> void:
	for kind in ["unit", "order", "counter", "field"]:
		_hand_art(kind)
	_chain_and_summon()
	_metadata_paths()
	_ui.call_deferred()

func _ui() -> void:
	var image := Image.create(20,20,false,Image.FORMAT_RGBA8);image.fill(Color.CORAL)
	CardArtCache.textures["2".repeat(64)] = ImageTexture.create_from_image(image)
	var g:=_game();var owner:=_rich(g);var c:=_with_art(_maker(_token(),true));g._receive_card(owner,c,"test")
	_check(g.apply_action(owner,{"type":"play","hand_id":g.state.players[owner].hand.back().instance_id}).is_empty(),"UI summon fixture")
	var view:Control=load("res://scripts/ui/battle_view.gd").new()
	view.me=owner;view.state=g.view_for(owner);view.connected=true;root.add_child(view)
	await process_frame
	var found:=false
	for face in view.find_children("*","Control",true,false):
		if face.has_meta("unit") and face.get_meta("unit").uid==g.state.units.back().uid:
			found=true;_check(face.art_id=="2".repeat(64),"battle unit face uses generated image")
	_check(found,"generated unit face exists")
	view.queue_free();await process_frame
	print("DERIVED_ART839: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func _with_art(d: Dictionary) -> Dictionary:
	var c := _compile(d)
	c["art_id"] = "1".repeat(64)
	c["token_art_ids"] = {"child":"2".repeat(64)}
	return c

func _hand_art(kind: String) -> void:
	var token := _token(kind)
	if kind == "order": token.abilities = [{"trigger":"on_play","effects":[{"op":"draw","player":"owner","amount":1}]}]
	if kind == "counter": token["counter_trigger"] = "enemy_order_played"; token.abilities = [{"trigger":"on_reveal","effects":[{"op":"cancel_action"}]}]
	var c := _with_art(_maker(token))
	var g := _game(); var owner := _rich(g)
	g._receive_card(owner,c,"test")
	_check(g.apply_action(owner,{"type":"play","hand_id":g.state.players[owner].hand.back().instance_id}).is_empty(),"create "+kind)
	var child: Dictionary = g.state.players[owner].hand.back().card
	_check(child.art_id == "2".repeat(64),"own image in hand: "+kind)
	_check(g.view_for(owner).players[owner].hand.back().card.art_id == child.art_id,"image sent to owner")
	_check(g.view_for(1-owner).players[owner].hand.is_empty(),"hidden generated hand stays secret")
	_play_child(g)
	if kind == "unit":
		_check(g.state.units.back().card.art_id == child.art_id,"unit keeps image in battle")
		g._leave_battlefield(g.state.units.back(),true)
		_check(g.state.players[owner].hand.back().card.art_id == child.art_id,"returned card keeps image")
	elif kind == "field": _check(g.state.field.card.art_id == child.art_id,"field keeps image")
	elif kind == "counter": _check(g.state.players[owner].counters.back().card.art_id == child.art_id,"counter keeps private image")

func _chain_and_summon() -> void:
	var t := _token("order")
	t.abilities = [{"trigger":"on_play","effects":[{"op":"create_card","token_id":"second","player":"owner","amount":1}]}]
	var d := _maker(t); var second := _token(); second.token_id="second"; d.tokens.append(second)
	var c := _with_art(d); c.token_art_ids.second="3".repeat(64)
	var g := _game(); var first: Dictionary=g._generated_card(c,"child");var next: Dictionary=g._generated_card(first,"second")
	_check(first.art_id == "2".repeat(64) and next.art_id == "3".repeat(64),"two generation library preserves individual art")
	c.token_art_ids.second="4".repeat(64)
	_check(first.token_art_ids.second == "3".repeat(64),"frozen cards do not share mutable art map")
	var plain: Dictionary=g._generated_card(_compile(d),"child")
	_check(plain.art_id.is_empty(),"unset image falls back to faction, never parent image")
	var s := _with_art(_maker(_token(),true));var owner:=_rich(g);g._receive_card(owner,s,"test")
	_check(g.apply_action(owner,{"type":"play","hand_id":g.state.players[owner].hand.back().instance_id}).is_empty(),"summon resolves")
	_check(g.state.units.back().card.art_id == "2".repeat(64),"summoned unit owns art")
	_check(g.view_for(1-owner).units.back().card.art_id == "2".repeat(64),"opponent sees summoned art")

func _metadata_paths() -> void:
	var d := _maker(_token());var c := _with_art(d)
	_check(CardArtCache.valid_token_art_ids(c.token_art_ids,d),"accept valid template art")
	for bad in [[],null,{"unknown":"2".repeat(64)},{"child":"bad"}]: _check(not CardArtCache.valid_token_art_ids(bad,d),"reject invalid token art")
	var store := StoreClass.new();var record := {"definition":d,"token_art":{"child":{"id":"2".repeat(64)}}}
	var compiled: Dictionary=store.compile_record(record)
	_check(compiled.ok and compiled.token_art_ids == c.token_art_ids,"catalog to local match compilation")
	store.free()
	var controller := MatchController.new()
	var faction_id:="11111111-1111-4111-8111-111111111111"
	controller.faction_catalog={faction_id:{"faction_id":faction_id,"name":"测试","role":"major","color":"#456247"}}
	controller.main_faction_id=faction_id
	var deck:=[]
	for i in 10:
		var source:=d.duplicate(true);source.name="携带衍生牌"+str(i);source["faction_id"]=faction_id
		var entry:=_with_art(source)
		for j in 4: deck.append(entry)
	var ready:Dictionary=controller._prepare_deck(deck,Runtime.builtin_keywords())
	_check(ready.ok and ready.cards[0].token_art_ids==c.token_art_ids,"local deck keeps generated art")
	var remote:Dictionary=controller._prepare_deck(ready.sources,Runtime.builtin_keywords())
	_check(remote.ok and remote.cards[0].token_art_ids==c.token_art_ids,"LAN peer recompilation keeps generated art")
	var hq:=_base("有衍生卡的总部","hq");hq.health=20;hq.cost=0;hq["draw_rule"]={"base":1};hq.tokens=d.tokens
	var h := _with_art(hq);var prepared:Dictionary=controller._prepare_headquarters(h,Runtime.builtin_keywords())
	_check(prepared.ok and prepared.card.token_art_ids==h.token_art_ids and prepared.source.token_art_ids==h.token_art_ids,"HQ LAN envelope keeps art")
	controller.free()
