extends "res://tests/test_engine.gd"
const StoreClass=preload("res://scripts/app_store.gd")
const Controller=preload("res://scripts/network/match_controller.gd")
const Face=preload("res://scripts/ui/card_face.gd")

func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	var defs:=[];var cards:=[]
	for i in 10:
		var d:=_base("罪孽混组"+str(i));d["sin"]=SinCatalog.IDS[i%7]
		var c:=_compile(d);defs.append(d)
		_check(c.definition.sin==d.sin,"compiled sin survives")
		for j in 4: cards.append(c)
	for sin in SinCatalog.IDS:
		_check(SinCatalog.icon(sin)!=null,"bundled icon: "+sin)
		_check(SinCatalog.color_for({"sin":sin})!=Color("303538"),"own dark color")
	var old:=_compile(_base());_check(not old.definition.has("sin"),"old immutable definitions remain unchanged")
	_check(SinCatalog.id_of(old.definition)=="" and SinCatalog.color_for(old.definition)==Color("303538"),"legacy is neutral/unassigned")
	var malformed:=_base();malformed["sin"]="greed";_check(not Runtime.compile_card(malformed,[]).ok,"reject eighth sin")
	var game:=EngineClass.new();_check(game.setup(cards,cards,42).is_empty(),"all seven sins freely combine")
	var maker:Dictionary=defs[0].duplicate(true);maker.tokens=[{"token_id":"child","name":"独立忧郁衍生","sin":"gloom","unit_class":"infantry","attack":1,"health":2,"keywords":[]}]
	var child:Dictionary=game._generated_card(_compile(maker),"child");_check(child.definition.sin=="gloom","derived sin independent from parent")
	var ctl:=Controller.new();root.add_child(ctl);ctl.main_sin="envy"
	var ready:Dictionary=ctl._prepare_deck(cards,[]);_check(ready.ok,"deck requires no faction")
	var lan:Dictionary=ctl._prepare_deck(ready.sources,[]);_check(lan.ok and lan.cards[0].definition.sin=="wrath","LAN retains sins")
	_check(ctl.start_solo(cards,[]).is_empty(),"practice can start with nominal sin")
	_check(ctl.state.players[0].main_sin=="envy" and ctl.state.players[1].main_sin=="envy","public backs use nominal sin")
	ctl.leave_game();ctl.free()
	var store:=StoreClass.new();store.profile_path="user://sin840-test-"+str(Time.get_ticks_usec())+".json";store.keyword_definitions=Runtime.builtin_keywords()
	_check(store.new_local_deck("主国罪孽","","pride").ok,"new deck selects sin")
	_check(store.save_local_deck("主国罪孽").ok,"local save")
	var saved_id:=store.active_deck_id
	_check(store.new_local_deck("另一个","","wrath").ok,"switch to other sin")
	_check(store.load_local_deck(saved_id).ok and store.main_sin=="pride","load restores nominal sin")
	var restored:=StoreClass.new();restored.profile_path=store.profile_path;restored._load_profile()
	_check(restored.main_sin=="pride","restart restores nominal sin")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(store.profile_path));restored.free();store.free()
	var image:=Image.create(20,20,false,Image.FORMAT_RGBA8);image.fill(Color(0.8,0.4,0.2,0.3))
	var texture:=ImageTexture.create_from_image(image);var icon_id:="a".repeat(64)
	CardArtCache.textures[icon_id]=texture;FactionCatalog.entries={"test":{"name":"测试阵营","icon_id":icon_id,"color":"#aabbcc"}}
	var face:=Face.new();face.spec=defs[0].duplicate(true);face.spec.faction_id="test";root.add_child(face);await process_frame
	_check(face.faction_icon==texture,"card header retains faction icon")
	face.spec.sin="pride";face.refresh_art();_check(face.faction_icon==texture,"sin change does not change faction icon")
	face.spec.sin=null;face.refresh_art();_check(face.faction_icon==texture,"unassigned sin retains faction icon")
	face.spec=old.definition;face.refresh_art();_check(face.faction_icon==null,"removing faction clears old icon")
	face.queue_free();await process_frame
	print("SINS840: %d checks, %d failures" % [checks,failures]);quit(1 if failures else 0)
