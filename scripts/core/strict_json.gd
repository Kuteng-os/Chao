extends RefCounted
## Godot JSON is intentionally permissive; this lexical gate is used for imports.
var text := ""
var cursor := 0
var error := ""
var allow_decimals := false

func parse(source: String, max_bytes: int = 32768, decimals: bool = false) -> Dictionary:
	allow_decimals = decimals
	text = source
	cursor = 0
	error = ""
	if source.to_utf8_buffer().size() > max_bytes:
		return {"ok": false, "error": "JSON 超过字节限制", "value": null}
	var value: Variant = _value(0)
	_space()
	if error.is_empty() and cursor != text.length():
		error = "JSON 后包含多余内容"
	return {"ok": error.is_empty(), "error": error, "value": value if error.is_empty() else null}

func _space() -> void:
	while cursor < text.length() and text[cursor] in [" ", "\t", "\n", "\r"]:
		cursor += 1

func _value(depth: int) -> Variant:
	_space()
	if not error.is_empty(): return null
	if depth > 16:
		error = "JSON 嵌套超过 16 层"
		return null
	if cursor >= text.length():
		error = "JSON 不完整"
		return null
	var first := text[cursor]
	if first == '"': return _string()
	if first == "{":
		cursor += 1
		_space()
		var object := {}
		if _take("}"): return object
		while error.is_empty():
			_space()
			if cursor >= text.length() or text[cursor] != '"':
				error = "JSON 对象需要字符串键"
				break
			var key := _string()
			if object.has(key):
				error = "JSON 包含重复键：" + key
				break
			_space()
			if not _take(":"):
				error = "JSON 对象缺少冒号"
				break
			object[key] = _value(depth + 1)
			_space()
			if _take("}"): return object
			if not _take(","):
				error = "JSON 对象缺少逗号或结束符"
				break
		return null
	if first == "[":
		cursor += 1
		_space()
		var values := []
		if _take("]"): return values
		while error.is_empty():
			values.append(_value(depth + 1))
			_space()
			if _take("]"): return values
			if not _take(","):
				error = "JSON 数组缺少逗号或结束符"
				break
		return null
	for literal in ["null", "true", "false"]:
		if text.substr(cursor, literal.length()) == literal:
			cursor += literal.length()
			return null if literal == "null" else literal == "true"
	var regex := RegEx.new()
	regex.compile("^-?(0|[1-9][0-9]*)(\\.[0-9]+)?([eE][+-]?[0-9]+)?")
	var number := regex.search(text.substr(cursor))
	if number == null:
		error = "JSON 包含非法值"
		return null
	var number_text := number.get_string()
	cursor += number_text.length()
	var exponent_at := number_text.to_lower().find("e")
	if exponent_at >= 0 and abs(number_text.substr(exponent_at + 1).to_int()) > 308:
		error = "JSON 数字指数超出安全范围"
		return null
	var numeric: Variant = JSON.parse_string(number_text)
	if numeric == null or not is_finite(float(numeric)) or (not allow_decimals and float(numeric) != floor(float(numeric))) or abs(float(numeric)) > 9007199254740991.0:
		error = "JSON 数字必须为安全范围内整数"
		return null
	return float(numeric) if allow_decimals and float(numeric) != floor(float(numeric)) else int(numeric)

func _take(character: String) -> bool:
	if cursor < text.length() and text[cursor] == character:
		cursor += 1
		return true
	return false

func _hex4(at: int) -> int:
	if at + 4 > text.length(): return -1
	var fragment := text.substr(at, 4)
	for character in fragment:
		if not character in "0123456789abcdefABCDEF": return -1
	return fragment.hex_to_int()

func _string() -> String:
	var start := cursor
	cursor += 1
	while cursor < text.length():
		var code := text.unicode_at(cursor)
		if code == 34:
			cursor += 1
			var decoded: Variant = JSON.parse_string(text.substr(start, cursor - start))
			if decoded is String: return decoded
			error = "JSON 字符串解码失败"
			return ""
		if code < 32 or (code >= 0xd800 and code <= 0xdfff):
			error = "JSON 字符串包含控制字符或孤立代理码位"
			return ""
		if code == 92:
			cursor += 1
			if cursor >= text.length() or not text[cursor] in ['"', "\\", "/", "b", "f", "n", "r", "t", "u"]:
				error = "JSON 转义错误"
				return ""
			if text[cursor] == "u":
				var unicode_code := _hex4(cursor + 1)
				if unicode_code < 0:
					error = "JSON Unicode 转义错误"
					return ""
				cursor += 4
				if unicode_code >= 0xd800 and unicode_code <= 0xdbff:
					if text.substr(cursor + 1, 2) != "\\u":
						error = "JSON 高代理码位缺少低代理"
						return ""
					var low := _hex4(cursor + 3)
					if low < 0xdc00 or low > 0xdfff:
						error = "JSON 代理对错误"
						return ""
					cursor += 6
				elif unicode_code >= 0xdc00 and unicode_code <= 0xdfff:
					error = "JSON 孤立低代理码位"
					return ""
		cursor += 1
	error = "JSON 字符串未结束"
	return ""
