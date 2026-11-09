extends SceneTree
const Controller=preload("res://scripts/network/match_controller.gd")
const TestApi=preload("res://tests/test_cloud_controller.gd").TestApi
var checks:=0
var failures:=0
func _initialize() -> void:run.call_deferred()
func run() -> void:
	var api:=TestApi.new();api.base=OS.get_environment("CLOUD_TEST_URL");api.token=OS.get_environment("CLOUD_TEST_TOKEN_C");root.add_child(api)
	var c:=Controller.new();root.add_child(c)
	_check(await c.watch_cloud(api,OS.get_environment("CLOUD_TEST_ROOM"),1)==OK,"watch connects")
	_check(c.spectating and c.local_player==1 and c.connected,"watch seat bound")
	_check(c.state.players[1].hand.size()>0 and c.state.players[0].hand.is_empty(),"real client hand visibility")
	var sequence:int=c.state.state_seq
	c.submit_action({"type":"concede"});c.send_emote("test",Vector2.ZERO)
	await create_timer(0.8).timeout
	_check(c.state.state_seq==sequence and c.state.winner==-1,"read only after polling")
	c.leave_game();await create_timer(0.25).timeout
	_check(c.mode=="menu" and not c.spectating,"exit local state")
	var room:Dictionary=await api.request("/v1/rooms/"+OS.get_environment("CLOUD_TEST_ROOM")+"/state")
	_check(room.code==403,"unwatch revokes state")
	_check(await c.watch_cloud(api,OS.get_environment("CLOUD_TEST_ROOM"),0)!=OK,"cannot switch after exit")
	_check(await c.watch_cloud(api,OS.get_environment("CLOUD_TEST_ROOM"),1)==OK,"same perspective reconnects")
	c.leave_game();await create_timer(0.2).timeout
	print("SPECTATOR_HTTP: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
func _check(ok:bool,message:String) -> void:
	checks+=1
	if not ok:failures+=1;push_error(message)
