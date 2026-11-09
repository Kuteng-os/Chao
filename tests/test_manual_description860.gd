extends "res://tests/test_generated_cards.gd"

func _initialize() -> void:
 var d:=_base("手写描述")
 d["display_text"]="部署：手写描述（不能自动精简）\n[b]纯文本[/b]"
 d.abilities=[{"trigger":"on_play","effects":[{"op":"draw","player":"owner","amount":1}]}]
 var compiled:=Runtime.compile_card(d,Runtime.builtin_keywords())
 _check(compiled.ok,"manual description compiles")
 var shown:=Runtime.display_definition(compiled)
 _check(Runtime.short_rules_text(shown)==d.display_text,"literal card-face text")
 _check(Runtime.detailed_rules_text(shown).contains("实际机制\n"),"details retain actual rules")
 _check(Runtime.rules_text(shown).contains("抽"),"automatic rules remain available")
 var face=load("res://scripts/ui/card_face.gd").new()
 face.spec=shown
 _check(face._rules_text()==d.display_text,"card face does not rewrite manual prefixes")
 face.free()
 _check(Runtime.bold_rules_text(d.display_text,shown).contains("[lb]b]"),"manual BBCode stays literal")
 d.display_text=" \n "
 _check(Runtime.short_rules_text(d).contains("抽"),"blank restores automatic description")
 for invalid in [2001,0]:
  d.display_text="x".repeat(invalid) if invalid else "bad"+String.chr(1)+"text"
  _check(not Runtime.compile_card(d,Runtime.builtin_keywords()).ok,"invalid text rejected")
 var token:=_token("order")
 token["display_text"]="衍生卡自写文字"
 token.abilities=[{"trigger":"on_play","effects":[{"op":"damage","target":"enemy_hq","amount":2}]}]
 var game:=_game()
 var owner: int=game.state.active_player
 _play(game,_maker(token))
 var entry: Dictionary=game.state.players[owner].hand.back()
 _check(Runtime.short_rules_text(Runtime.display_definition(entry.card))==token.display_text,"generated card inherits its own text")
 _play_child(game)
 _check(game.state.players[1-owner].hp==18,"written description never changes mechanics")
 print("MANUAL DESCRIPTION 860: %d checks, %d failures" % [checks,failures])
 quit(1 if failures else 0)
