extends "res://tests/test_latest841.gd"
func _initialize() -> void:
	records=JSON.parse_string(FileAccess.get_file_as_string("res://tests/provider841.json")).cards
	for r in records:
		var c:=_compile(r.definition)
		_check(c.definition_hash==r.definition_hash and c.compiled_program_hash==r.compiled_program_hash,"actual DeepSeek output agrees with authority")
	_draws()
	_delayed()
	var g:=_game();var p:=_rich(g);g.state.players[p].hand=[];g.state.players[p].deck=[]
	_play(g,records[1].definition)
	_check(g.state.players[p].credits==9,"actual model previous-card condition excludes current card")
	_play(g,records[1].definition)
	_check(g.state.players[p].credits==11,"actual model previous-card condition grants once")
	var count:int=g.state.discard.size();_play(g,records[4].definition)
	_check(g.state.players[p].credits==9 and g.state.discard.size()==count+1,"actual model noop pays and discards")
	var uid:=_play(g,records[3].definition);var unit:Dictionary=g._unit(uid)
	var enemy:Dictionary=g._new_unit(1-p,_compile(_base("目标")))
	unit.attack=9;enemy.attack=4
	_check(g._incoming_damage(unit,4,"combat",enemy)==2,"actual model formula computes floor positive attack difference")
	_check(g._incoming_damage(unit,4,"effect",enemy)==4,"actual model formula excludes effect damage")
	print("PROVIDER841: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
