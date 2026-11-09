extends "res://tests/test_engine.gd"
func _initialize() -> void:
	var fixture: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/text844-fixtures.json"))
	var lines:=PackedStringArray()
	for card in fixture.cards:
		var c:=Runtime.compile_card(card.definition,fixture.keywords.values())
		_check(c.ok,"existing card compiles")
		_check(c.definition_hash==card.definition_hash and c.compiled_program_hash==card.compiled_program_hash,"frozen program unchanged")
		var d:=Runtime.display_definition(c)
		var short:=Runtime.short_rules_text(d)
		lines.append(card.definition.name+"\n"+short)
		_check(not short.contains("++") and not short.contains("X为1") and not short.contains("X为2"),"numeric buffs remain simple")
		if card.card_id=="06c0ce91-5cf3-4ff9-97ff-d2f1fe341371":
			var face:=CardFace.new();face.spec=d
			_check(face._rules_text().contains("部署：抽1张牌"),"granted deployment trigger stays on order face")
			face.free()
		if card.card_id=="716ceade-4d40-4224-aa9c-c71c199ee92d":
			_check(short.contains("闪击") and not short.contains("继承"),"rabbit short text")
			_check(Runtime.detailed_rules_text(d).contains("最后的孵化"),"inheritance restriction remains in details")
			_check(Runtime.bold_rules_text(short,d).contains("[b]闪击[/b]"),"keyword bold")
	print("\n".join(lines))
	print("TEXT844: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
