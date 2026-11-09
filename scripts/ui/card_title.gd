extends RefCounted
const Typography = preload("res://scripts/ui/card_typography.gd")
## A visual line break never changes the canonical card name used by effects.
static func lines(spec: Dictionary) -> PackedStringArray:
	var title := str(spec.get("name", "未命名"))
	var split := int(spec.get("appearance", {}).get("name_break", 0))
	if split > 0 and split < title.length(): return PackedStringArray([title.left(split), title.substr(split)])
	return PackedStringArray([title])

static func layout(spec: Dictionary, font: Font, width: float, height: float, maximum: int, minimum: int) -> Dictionary:
	var parts := lines(spec)
	var automatic := parts.size()==1 and Typography.is_latin(parts[0])
	var fs := maximum
	while fs > minimum and not _fits(parts,font,width,height,fs): fs -= 1
	# English can wrap at spaces automatically, without altering its saved name.
	# Prefer two readable lines over a cramped single line at the lower limit.
	if automatic and fs<=mini(maximum,minimum+1):
		var title: String=parts[0]
		for candidate_size in range(maximum,minimum-1,-1):
			var best: PackedStringArray=[]
			var balance := INF
			for at in title.length():
				if title[at]!=" ": continue
				var pair:=PackedStringArray([title.left(at).strip_edges(),title.substr(at+1).strip_edges()])
				if pair[0].is_empty() or pair[1].is_empty() or not _fits(pair,font,width,height,candidate_size): continue
				var difference:=absf(font.get_string_size(pair[0],HORIZONTAL_ALIGNMENT_LEFT,-1,candidate_size).x-font.get_string_size(pair[1],HORIZONTAL_ALIGNMENT_LEFT,-1,candidate_size).x)
				if difference<balance:best=pair;balance=difference
			if not best.is_empty():parts=best;fs=candidate_size;break
	return {"lines":parts,"font_size":fs,"overflow":not _fits(parts,font,width,height,fs)}

static func _fits(parts: PackedStringArray, font: Font, width: float, height: float, fs: int) -> bool:
	if (fs + 2) * parts.size() > height: return false
	for line in parts:
		if font.get_string_size(line,HORIZONTAL_ALIGNMENT_LEFT,-1,fs).x > width: return false
	return true
