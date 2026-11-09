extends SceneTree
const Typography=preload("res://scripts/ui/card_typography.gd")
const Title=preload("res://scripts/ui/card_title.gd")
const Face=preload("res://scripts/ui/card_face.gd")
var checks:=0
var failures:=0
func check(ok:bool,message:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(message)

func _initialize()->void:
	call_deferred("run")

func run()->void:
	var chinese:=SystemFont.new();chinese.font_names=PackedStringArray(["Microsoft YaHei","sans-serif"])
	var latin:=Typography.font_for("Last Hatching",chinese)
	check(latin==ThemeDB.fallback_font,"Latin uses bundled proportional font")
	check(Typography.font_for("R-401孵化场",chinese)==chinese,"mixed CJK stays in CJK font")
	for name in ["Last Hatching","Royal Air Force","The Final Expedition"]:
		for compact in [false,true]:
			var layout:=Title.layout({"name":name},latin,67 if compact else 145,27 if compact else 37,13 if compact else 22,9 if compact else 14)
			check(not layout.overflow,"English title fits: "+name)
			check(" ".join(layout.lines)==name,"automatic wrapping preserves every word")
	var explicit:=Title.layout({"name":"Royal Air Force","appearance":{"name_break":6}},latin,145,37,22,14)
	check(explicit.lines[0]=="Royal ","explicit author break retained")
	var original:=Title.layout({"name":"这是很长很长的中文名称"},chinese,145,37,22,14)
	check(original.lines.size()==1 and original.overflow,"Chinese still asks creator to break long title")
	var phrase:="Deployment: Draw two cards. Give another friendly unit +2/+2 this turn."
	var wrapped:=Typography.wrap_words(phrase,latin,214,18)
	check(" ".join(wrapped)==phrase,"English body preserves word spacing")
	for line in wrapped:check(latin.get_string_size(line,HORIZONTAL_ALIGNMENT_LEFT,-1,18).x<=214,"rules line fits")
	check(not wrapped[0].ends_with("Depl"),"words are not cut like Chinese characters")
	var face:=Face.new();root.add_child(face)
	check(not face._rules_has_orphan_tail("Draw a card.",latin,18),"Chinese orphan-character heuristic does not shrink English")
	face.queue_free()
	print("TYPOGRAPHY846: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
