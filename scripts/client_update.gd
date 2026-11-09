extends Node
## This bootstrap is loaded from the signed base application before any resource patch.
const BASE_BUILD := 909
const BASE_VERSION := "0.9.9"
const UPDATES_DISABLED := true
const ABI := "frontline-4.7-1"
const ORIGIN := "https://wzb.rainplay.cn:36410"
const DIRECTORY := "user://updates/"
var directory := DIRECTORY
var current_build := BASE_BUILD
var current_version := BASE_VERSION
var pending_build := 0
var available: Dictionary = {}
var envelope: Dictionary = {}
var public_key: CryptoKey
var busy := false
var progress := 0.0
var status := ""
var _http: HTTPRequest
signal changed

func _ready() -> void:
	public_key = CryptoKey.new()
	public_key.load("res://assets/update_public.pem", true)
	_restore_patch()

func _restore_patch() -> void:
	if UPDATES_DISABLED:return
	DirAccess.make_dir_recursive_absolute(directory)
	var active := directory + "active.json"
	if FileAccess.file_exists(active):
		var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(active))
		var verified := verify(saved)
		if not verified.is_empty() and int(verified.build) <= BASE_BUILD:
			# A newer complete installer supersedes an old patch without downgrading.
			DirAccess.remove_absolute(directory + "boot_pending")
			return
		if not verified.is_empty() and verified.minimum_base_build <= BASE_BUILD and verified.patch_abi == ABI:
			var file := directory + str(int(verified.build)) + ".pck"
			if FileAccess.file_exists(directory + "boot_pending"):
				status = "上次补丁未能启动，已恢复基础版本。"
				DirAccess.rename_absolute(active, directory + "failed.json")
				DirAccess.remove_absolute(directory + "boot_pending")
			elif _valid_file(file, verified.files.pck):
				var marker := FileAccess.open(directory + "boot_pending", FileAccess.WRITE)
				marker.store_string(str(verified.build))
				marker.close()
				if ProjectSettings.load_resource_pack(file, true):
					current_build = int(verified.build)
					current_version = verified.version

func verify(value: Variant) -> Dictionary:
	if not value is Dictionary or not value.get("payload") is String or not value.get("signature") is String: return {}
	if value.payload.length() > 32768 or value.signature.length() > 2048: return {}
	var digest := HashingContext.new()
	digest.start(HashingContext.HASH_SHA256)
	digest.update(value.payload.to_utf8_buffer())
	if not Crypto.new().verify(HashingContext.HASH_SHA256, digest.finish(), Marshalls.base64_to_raw(value.signature), public_key): return {}
	var parsed: Variant = JSON.parse_string(value.payload)
	if not parsed is Dictionary or parsed.get("schema") != 1 or not parsed.get("patch_abi") is String: return {}
	if not parsed.get("build") is float and not parsed.get("build") is int: return {}
	if parsed.build != int(parsed.build) or parsed.build < 800 or not parsed.get("version") is String or not parsed.get("files") is Dictionary: return {}
	if not parsed.get("minimum_base_build") is float and not parsed.get("minimum_base_build") is int: return {}
	if parsed.minimum_base_build != int(parsed.minimum_base_build) or parsed.minimum_base_build < 800 or parsed.minimum_base_build > parsed.build or parsed.version.length() > 64: return {}
	for extension in ["pck", "exe", "apk"]:
		var item: Variant = parsed.files.get(extension)
		if not item is Dictionary or not item.get("path") is String or not item.get("sha256") is String or not item.get("bytes") is float and not item.get("bytes") is int: return {}
		var pattern := RegEx.new()
		pattern.compile("^/v1/client-files/Frontline-[A-Za-z0-9.-]+\\." + extension + "$")
		if pattern.search(item.path) == null or item.bytes != int(item.bytes) or item.bytes < 1 or item.bytes > 536870912: return {}
		pattern.compile("^[a-f0-9]{64}$")
		if pattern.search(item.sha256) == null: return {}
	return parsed

func mark_healthy() -> void:
	DirAccess.remove_absolute(directory + "boot_pending")

func _process(_delta: float) -> void:
	if _http != null and busy and _http.get_body_size() > 0:
		progress = float(_http.get_downloaded_bytes()) / float(_http.get_body_size())
		changed.emit()

func _request(path: String, output: String = "") -> Array:
	_http = HTTPRequest.new()
	_http.timeout = 180.0 if not output.is_empty() else 12.0
	_http.body_size_limit = 536870912 if not output.is_empty() else 65536
	_http.max_redirects = 0
	var certificate := X509Certificate.new()
	certificate.load("res://assets/server_ca.crt")
	_http.set_tls_options(TLSOptions.client(certificate))
	_http.download_file = output
	add_child(_http)
	var error := _http.request(ORIGIN + path)
	if error != OK:
		_http.queue_free()
		_http = null
		return []
	var response: Array = await _http.request_completed
	_http.queue_free()
	_http = null
	return response

func check() -> void:
	if UPDATES_DISABLED:
		status="新版本请到 GitHub 下载"
		changed.emit()
		return
	if busy: return
	busy = true
	status = "正在检查更新"
	changed.emit()
	var response := await _request("/v1/client-release")
	busy = false
	if response.is_empty() or response[0] != HTTPRequest.RESULT_SUCCESS or response[1] != 200:
		status = "暂时无法检查更新"
	else:
		var value: Variant = JSON.parse_string(response[3].get_string_from_utf8())
		available = verify(value)
		if available.is_empty(): status = "更新签名无效"
		else:
			envelope = value
			status = "补丁已就绪，重启游戏后生效" if pending_build > current_build else ("发现新版本 " + available.version if available.build > current_build else "已是最新版本")
	changed.emit()

func _valid_file(path: String, item: Dictionary) -> bool:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null: return false
	var correct: bool = f.get_length() == int(item.bytes)
	f.close()
	return correct and FileAccess.get_sha256(path) == item.sha256

func download() -> void:
	if UPDATES_DISABLED:return
	if busy or available.is_empty() or available.build <= current_build: return
	busy = true
	progress = 0
	var full: bool = available.minimum_base_build > BASE_BUILD or available.patch_abi != ABI
	var extension := ("apk" if OS.get_name() == "Android" else "exe") if full else "pck"
	var item: Dictionary = available.files[extension]
	var target := directory + str(int(available.build)) + "." + extension
	status = "下载完整安装包" if full else "正在下载补丁"
	changed.emit()
	var result := await _request(item.path, target + ".part")
	if result.is_empty() or result[0] != HTTPRequest.RESULT_SUCCESS or result[1] != 200 or not _valid_file(target + ".part", item):
		status = "更新未完成，请重试"
		DirAccess.remove_absolute(target + ".part")
	elif DirAccess.rename_absolute(target + ".part", target) != OK:
		status = "无法保存更新文件"
	elif full:
		status = "安装包已下载"
		if OS.shell_open(ProjectSettings.globalize_path(target)) != OK:
			status = "无法打开安装包，请从网页下载新版"
	else:
		var file := FileAccess.open(directory + "next.json", FileAccess.WRITE)
		if file == null: status = "无法保存更新记录"
		else:
			file.store_string(JSON.stringify(envelope))
			file.close()
			if DirAccess.rename_absolute(directory + "next.json", directory + "active.json") == OK:
				pending_build = int(available.build)
				status = "补丁已就绪，重启游戏后生效"
			else: status = "无法启用补丁，请重试"
	busy = false
	changed.emit()
