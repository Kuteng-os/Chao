extends "res://tests/test_engine.gd"
const Controller=preload("res://scripts/network/match_controller.gd")
const Console=preload("res://scripts/ui/practice_console.gd")
const View=preload("res://scripts/ui/battle_view.gd")
var emitted: Array=[]

class SlowApi extends Node:
	var polls:=0
	var actions:=0
	func request(path: String,_method: int=0,_body: Dictionary={}) -> Dictionary:
		if path.ends_with("/state"): polls+=1
		if path.ends_with("/actions"): actions+=1
		await get_tree().create_timer(0.1).timeout
		return {"ok":false,"code":503,"error":"test outage"}

func _initialize() -> void: run.call_deferred()
func run() -> void:
	var c:=Controller.new();root.add_child(c);c.mode="solo";c.connected=true;c._engine=_game();c.debug_ai_paused=true
	var game=c._engine
	var card:=_compile(_base("控制台测试"));var catalog: Array=[card]
	var before: Dictionary=game.state.duplicate(true)
	for mode in ["cloud","host","client","menu"]:
		c.mode=mode;_check("仅限" in c.debug_session.execute(c,"费用 12",catalog),"network mode rejects console");_check(game.state==before,"no mutation in "+mode)
	c.mode="solo"
	_check("已执行" in c.debug_session.execute(c,"费用 12",catalog),"set credits")
	_check(game.state.players[0].credits==12 and game.state.players[0].max_credits==12,"credits valid")
	_check("已恢复" in c.debug_session.execute(c,"撤销",catalog),"undo")
	_check(game.state.players[0].credits==before.players[0].credits,"undo restores credits")
	var count: int=game.state.players[0].deck.size()
	c.debug_session.execute(c,"抽牌 2",catalog)
	_check(game.state.players[0].deck.size()==count-2,"draw uses actual deck")
	var hand: int=game.state.players[1].hand.size()
	c.debug_session.execute(c,"手牌 1 敌方",catalog)
	_check(game.state.players[1].hand.size()==hand+1,"give enemy card")
	c.debug_session.execute(c,"召唤 1 敌方",catalog)
	_check(game.state.units.size()==1 and game.state.units[0].owner==1,"summon enemy")
	c.debug_session.execute(c,"总部 35",catalog)
	_check(game.state.players[0].hp==35 and game.state.players[0].max_hp==35,"HQ edit")
	for invalid in ["费用 -1","抽牌 1000","手牌 2","费用 5 garbage","eval hello","费用 4.5"]:
		before=game.state.duplicate(true);c.debug_session.execute(c,invalid,catalog);_check(game.state==before,"invalid command leaves state "+invalid)
	game.state.pending_choice={"owner":0}
	before=game.state.duplicate(true);c.debug_session.execute(c,"费用 7",catalog);_check(game.state==before,"pending choice cannot be edited");game.state.erase("pending_choice")
	_check("UID" in c.debug_session.execute(c,"状态",catalog),"state inspection")
	_check("控制台测试" in c.debug_session.execute(c,"卡库 测试",catalog),"search")
	for viewport in [Vector2i(1440,900),Vector2i(1024,600),Vector2i(2412,1080)]:
		root.size=viewport
		var console:=Console.new();console.controller=c;console.catalog=catalog;root.add_child(console);await process_frame
		_check(c.debug_console_open,"console pauses AI")
		_check(console.output.size.y>100 and console.entry.get_global_rect().end.y<=root.get_visible_rect().size.y,"fixed console fits "+str(viewport))
		console.run("状态");_check("回合" in console.output.text,"console displays output")
		console.dismiss();await process_frame;_check(not c.debug_console_open,"closing resumes auto pause")
	var v:=View.new();v.me=0;v.state=game.view_for(0);v.connected=true;v.spectating=true;v.size=Vector2(1440,900);root.add_child(v);await process_frame
	v.action_requested.connect(func(a):emitted.append(a));v._emit_action({"type":"end_turn"})
	_check(emitted.is_empty() and not v.my_turn and not v.choosing,"spectator UI is read only")
	_check(v.emote_hud==null or not v.emote_hud.enabled,"spectator cannot emit player emotes")
	v.queue_free();await process_frame
	c.leave_game();_check(c.debug_session.undo_states.is_empty(),"practice history reset per match")
	var api:=SlowApi.new();root.add_child(api);c.mode="cloud";c._cloud_store=api;c.cloud_room_id="test";c.connected=true;c._cloud_pending=true
	await create_timer(1.0).timeout
	_check(api.polls>0,"state heartbeat continues while action pending")
	_check("同步暂时失败" in c.status,"transient errors have accurate status")
	c.spectating=true;c.submit_action({"type":"end_turn"});_check(api.actions==0,"spectator action blocked in controller")
	c.leave_game();c.queue_free();await create_timer(0.2).timeout;api.queue_free()
	print("FEATURES859: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
