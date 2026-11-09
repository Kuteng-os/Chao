extends "res://tests/test_engine.gd"
var f: Dictionary
func _initialize() -> void:
 f=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/repairs857.json"))
 var expected: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/parity857.json"))
 var c:=_compile(f);if c.ok:_check(c.compiled_program_hash==expected.compiled_program_hash,"Node/native zero-multiplier parity")
 if failures:quit(1);return
 _check("不造成战斗伤害" in Runtime.rules_text(c),"zero prints as no combat damage")
 _comparison()
 _exchange(false,4)
 _exchange(true,4)
 _exchange(false,3)
 _exchange(true,3)
 print("REPAIRS 857: %d checks, %d failures" % [checks,failures]);quit(1 if failures else 0)

func _source(g: RefCounted,owner: int) -> Dictionary:
 var a: Dictionary=g._new_unit(owner,_compile(f));g._initialize_deployed_unit(a);return a

func _comparison() -> void:
 var g:=_game();var me:=_rich(g);var a:=_source(g,me)
 var def:=_base();def.health=20;var b: Dictionary=g._new_unit(1-me,_compile(def))
 for strength in [2,3,4,9]:
  b.attack=strength
  for phase in ["attack","retaliation"]:
   _check(g._combat_damage(a,b,phase)==(5 if strength>3 else 0),"compare actual pre-bonus attack "+phase+str(strength))
 _check(a.attack==3,"combat bonus does not change printed/current attack")
 b.attack=4
 _check(g._combat_damage(a,b,"attack")==5 and g._combat_damage(a,b,"attack")==5,"repeated calculations never accumulate +2")
 g._effect({"op":"modify_stats","target":"self","attack_delta":2,"health_delta":0,"duration":"battle"},g._context(me,a.uid,a.card))
 _check(g._combat_damage(a,b,"attack")==0,"existing permanent or battlefield stats participate in comparison")
 b.attack=6;_check(g._combat_damage(a,b,"attack")==7,"bonus applies to current buffed attack")
 b.attack=5
 g._effect({"op":"modify_incoming_damage","target":"self","amount":2,"multiplier":2,"damage_kind":"combat","duration":"battle"},g._context(1-me,b.uid,b.card))
 _check(g._combat_damage(a,b,"attack")==0,"incoming vulnerability cannot make zero packet positive")
 var before: int=b.hp;g._effect({"op":"damage","target":"chosen","amount":2},g._context(me,a.uid,a.card,b.uid))
 _check(b.hp==before-2,"independent skill damage remains normal")
 _check(g._combat_damage(a,{},"attack")==5,"unit attack comparison does not treat HQ as zero-attack unit")

func _exchange(as_defender: bool,enemy_attack: int) -> void:
 var g:=_game();var me:=_rich(g);var a:=_source(g,me)
 var def:=_base();def.health=20;def.attack=enemy_attack
 var b: Dictionary=g._new_unit(1-me,_compile(def))
 if as_defender:g._resolve_combat(b,a)
 else:g._resolve_combat(a,b)
 _check(a.hp==20-enemy_attack,"opponent always causes its normal damage "+str(as_defender)+str(enemy_attack))
 _check(b.hp==20-(5 if enemy_attack>3 else 0),"conditional attack/retaliation packet matches rule "+str(as_defender)+str(enemy_attack))
 _check(a.attack==3,"exchange leaves source attack unchanged")
