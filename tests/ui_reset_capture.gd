extends "res://scripts/main.gd"
func _startup_begin()->void:_boot_loading=false
func _ready()->void:
	super._ready()
	get_viewport().warp_mouse(Vector2(3,3))
	_capture.call_deferred()
func shot(id:String)->void:
	await get_tree().create_timer(0.45).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://../../ui-reset-"+id+".png")
func _capture()->void:
	store.settings.backend_url="http://127.0.0.1:1";store._ensure_context()
	var records:Array=JSON.parse_string(FileAccess.get_file_as_string("res://tests/visual090_assets/records.json"))
	FactionCatalog.entries=FactionCatalog.parse(JSON.parse_string(FileAccess.get_file_as_string("res://tests/visual090_assets/factions.json")))
	store.factions=FactionCatalog.entries
	for entry in FactionCatalog.entries.values():
		if entry.get("icon_id") is String:CardArtCache.textures[entry.icon_id]=load("res://tests/visual090_assets/"+entry.icon_id+".png")
	for record in records:
		CardArtCache.textures[record.art.id]=load("res://tests/visual090_assets/"+record.art.id+".png")
		store._ingest_remote(record,store._bound_server,[])
	store.deck_name="R 公司 · 城区行动";store.main_sin="wrath";store.ally_sin="gloom"
	store.deck_ids=[]
	for card in store.latest_cards():
		for i in mini(DeckRules.limit(card.definition),3):store.deck_ids.append(card.card_id)
	store.authenticated=false;store.online=false
	page="home";_render();await shot("home")
	for next in ["library","network","workshop","keywords","profile"]:
		page=next;_render();await shot(next)
	page="settings"
	for category in ["display","audio","account","connection","about"]:
		settings_tab=category;_render();await shot("settings-"+category)
	_new_deck_dialog();await shot("new-deck");_close_modal()
	store.save_local_deck(store.deck_name)
	store.main_sin="gloom";store.ally_sin="pride";store.save_local_deck("忧郁 · 城市守卫",true)
	_saved_decks_dialog();await shot("saved-decks");_close_modal()
	_card_details(store.latest_cards()[0]);await shot("card-details");_close_modal()
	_emote_dialog();await shot("emotes");_close_modal()
	var mock:=preload("res://tests/ui090_mock_store.gd").new();add_child(mock)
	mock.authenticated=true;mock.account_identity={"display_name":"预览指挥官","username":"preview","bio":"统计页面示例数据","avatar":"wings","avatar_color":"#91dcd3"}
	for kind in ["profile","statistics"]:
		page=kind;_render()
		for child in content.get_children():content.remove_child(child);child.queue_free()
		var hub:=HubScript.new();content.add_child(hub);hub.setup(self,mock,kind=="statistics");await shot(kind+"-filled")
	store.authenticated=true;store.central_mode=true;store.account_identity=mock.account_identity
	cloud_rooms=[{"room_id":"ROOM-ABC","status":"waiting","commanders":["测试指挥官 A"]},{"room_id":"ROOM-XYZ","status":"active","commanders":["测试指挥官 B","测试指挥官 C"]}]
	page="network";_render();await shot("network-filled")
	var loading:=preload("res://scripts/ui/startup_loading.gd").new();add_child(loading);loading.stage("cards","卡库已更新",true);await shot("loading");remove_child(loading);loading.queue_free()
	page="library";_render();get_window().size=Vector2i(1280,720);await shot("library-1280")
	mobile=true;ScreenLayout.configure(get_window(),true);_build_theme();get_window().size=Vector2i(1560,720);page="settings";settings_tab="audio";_render();await shot("mobile-settings")
	page="library";_render();await shot("mobile-library")
	get_window().size=Vector2i(1200,900);page="network";_render();await shot("tablet-lobby")
	print("UI_RESET_PAGES_CAPTURED cards=",store.latest_cards().size())
	get_tree().quit()
