extends "res://tests/test_engine.gd"
var fixtures: Dictionary
func _initialize() -> void:
	var data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/repairs904.json"))
	fixtures=data.fixtures
	for key in fixtures:
		var c:=_compile(fixtures[key]);_check(c.get("compiled_program_hash")==data.hashes[key],"Node/native parity "+key)
	if failures: quit(1);return
	_test_swap()
	_test_armor()
	print("REPAIRS 904: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)

func _test_swap() -> void:
	var g:=_game();var me:=_rich(g)
	var spec:=_base("受伤目标");spec.attack=7;spec.health=9
	var u: Dictionary=g._new_unit(1-me,_compile(spec));u.damage_taken=5;g._recompute(u)
	var c:=_compile(fixtures.swap);var ctx: Dictionary=g._context(me,-1,c,u.uid)
	var swap: Dictionary=fixtures.swap.abilities[0].effects[0]
	g._effect(swap,ctx);_check(u.attack==4 and u.hp==7 and u.max_hp==7,"7 attack / 4 remaining defense swaps atomically")
	g._unit_damage(u,2,ctx);_check(u.hp==5,"damage after swap remains normal")
	g._effect({"op":"heal","target":"chosen","amount":10},ctx);_check(u.hp==7,"overheal stops at swapped maximum")
	g._unit_damage(u,1,ctx);_check(u.hp==6,"overheal cannot create hidden damage immunity")
	g._effect({"op":"repair","target":"chosen"},ctx);g._unit_damage(u,1,ctx);_check(u.hp==6,"repair also respects new damage baseline")
	g._effect(swap,ctx);_check(u.attack==6 and u.hp==4,"repeated swap reads latest values")
	g._leave_battlefield(u,true);var returned: Dictionary=g.state.players[1-me].hand.back().card
	u=g._new_unit(1-me,returned);_check(u.attack==7 and u.hp==9,"swap ends on return and redeploy")
	var high:=_base("上限受伤");high.attack=12;high.health=12
	u=g._new_unit(me,_compile(high));ctx=g._context(me,-1,c,u.uid)
	for i in 5:g._effect({"op":"modify_stats","target":"chosen","attack_delta":5,"health_delta":5,"duration":"battle"},ctx)
	u.damage_taken=28;g._recompute(u);_check(u.attack==30 and u.hp==2,"capped fixture")
	g._effect(swap,ctx);_check(u.attack==2 and u.hp==30,"swap at stat cap ignores old damage and excess modifiers")
	var zero:=_base("零攻目标");zero.attack=0
	u=g._new_unit(me,_compile(zero));ctx=g._context(me,-1,c,u.uid);var uid: int=u.uid
	g._effect(swap,ctx);g._checkpoint();_check(g._unit(uid).is_empty(),"zero attack becomes zero defense and dies")
	# A disappeared target does not consume another unit or cancel subsequent effects.
	g._effect(swap,ctx);_check(g._fault.is_empty(),"missing target safely skips")
	var aura:=_base("光环");aura.abilities=[{"trigger":"while_active","effects":[{"op":"modify_stats","target":"all_friendly_units","attack_delta":1,"health_delta":2,"duration":"battle"}]}]
	var source: Dictionary=g._new_unit(me,_compile(aura));u=g._new_unit(me,_compile(_base("光环目标")));g._checkpoint()
	ctx=g._context(me,-1,c,u.uid);g._effect(swap,ctx);_check(u.attack==6 and u.hp==4,"aura is included exactly once")
	g._leave_battlefield(source,false);g._checkpoint();_check(u.attack==5 and u.hp==2,"aura removal updates swapped values normally")

func _test_armor() -> void:
	var g:=_game();var me:=_rich(g);var id:=_play(g,fixtures.armor);var u: Dictionary=g._unit(id)
	_check(g.stack_count(u,"heavy_armor")==100,"100 armor is not truncated to ten")
	var enemy: Dictionary=g._new_unit(1-me,_compile(_base("伤害来源")))
	enemy.attack=30
	g._effect({"op":"set_combat_damage_multiplier","target":"self","against":"any","applies_to":"both","multiplier":4,"duration":"battle"},g._context(1-me,enemy.uid,enemy.card))
	enemy.attack=30
	_check(g._combat_damage(enemy,u,"attack")==20,"120 combat damage minus 100 armor leaves 20")
	_check(g._incoming_damage(u,101,"effect",enemy)==101,"armor does not block effect damage")
	g._effect({"op":"modify_stacks","stack":"heavy_armor","target":"self","amount":-100,"duration":"battle"},g._context(me,u.uid,u.card));_check(g.stack_count(u,"heavy_armor")==0,"100 armor removable")
	id=_play(g,fixtures.reduction);u=g._unit(id)
	_check(g._incoming_damage(u,101,"combat",enemy)==1,"fixed reduction is not immunity")
	_check(g._incoming_damage(u,50,"combat",enemy)==0,"fixed reduction floors at zero")
	_check(g._incoming_damage(u,101,"effect",enemy)==101,"combat reduction leaves effect damage unchanged")
