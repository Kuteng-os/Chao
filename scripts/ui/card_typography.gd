extends RefCounted
static var _card_fonts: Dictionary = {}
static var _weights: Dictionary = {}
## Card captures already sample at 2–4x. Rasterize glyphs at 4x as well:
## runtime MSDF generation of a previously unseen CJK name can stall a draw.
## Share the atlas across cards, captures, inspectors and rebuilt UI themes.
static func card_font(source: Font) -> Font:
	if not source is SystemFont or not source.multichannel_signed_distance_field: return source
	var key := str([source.font_names,source.font_weight,source.font_italic,source.font_stretch])
	if not _card_fonts.has(key):
		var font: SystemFont = source.duplicate()
		font.multichannel_signed_distance_field = false
		font.oversampling = 4.0
		_card_fonts[key] = font
	return _card_fonts[key]

static func weighted_font(source: Font, weight: float) -> FontVariation:
	var key := str(source.get_instance_id())+":"+str(weight)
	if not _weights.has(key):
		var font := FontVariation.new()
		font.base_font = source
		font.variation_embolden = weight
		_weights[key] = font
	return _weights[key]

## Latin text uses the bundled proportional face and word boundaries. Mixed
## CJK names keep the Chinese face and the creator's explicit break.
static func is_latin(value: String) -> bool:
	var letters := false
	for c in value:
		var code := c.unicode_at(0)
		if (code>=0x2e80 and code<=0x9fff) or (code>=0xac00 and code<=0xd7af) or code>=0x20000: return false
		if (code>=65 and code<=90) or (code>=97 and code<=122) or (code>=0xc0 and code<=0x24f): letters=true
	return letters

static func font_for(value: String, chinese: Font) -> Font:
	return ThemeDB.fallback_font if is_latin(value) else chinese

static func wrap_words(value: String, font: Font, width: float, fs: int) -> Array[String]:
	var result: Array[String]=[]
	for paragraph in value.split("\n"):
		var line := ""
		for word in paragraph.split(" ",false):
			if not line.is_empty():
				if font.get_string_size(line+" "+word,HORIZONTAL_ALIGNMENT_LEFT,-1,fs).x<=width:
					line+=" "+word;continue
				result.append(line);line=""
			# Only unbreakable words wider than the entire line may split.
			for letter in word:
				if font.get_string_size(line+letter,HORIZONTAL_ALIGNMENT_LEFT,-1,fs).x>width and not line.is_empty():
					result.append(line);line=""
				line+=letter
		if not line.strip_edges().is_empty(): result.append(line.strip_edges())
	return result
