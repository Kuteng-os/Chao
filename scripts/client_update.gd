extends Node
## Finds new clients through a signed manifest kept in the GitHub repository and installs them from GitHub Releases.
## The manifest is signed with the maintainer's offline key, so write access to the repository alone cannot ship a client.
const BASE_BUILD := 1000
const BASE_VERSION := "0.10.0"
const MANIFEST := "release/client.json"
const RELEASES := "https://github.com/xiangwu738-design/Chao/releases"
const DOWNLOAD_PREFIX := RELEASES + "/download/"
const DIRECTORY := "user://updates/"
const MANIFEST_LIMIT := 65536
const MAX_INSTALLER := 536870912
const PRIMARY_TIMEOUT := 12.0
const MIRROR_TIMEOUT := 30.0
const DOWNLOAD_TIMEOUT := 900.0
const REMOVE_ATTEMPTS := 20
var current_build := BASE_BUILD
var current_version := BASE_VERSION
var available: Dictionary = {}
var public_key: CryptoKey
var busy := false
var progress := 0.0
var status := ""
var signature_failed := false
## A verified installer on disk, ready to launch.
var ready_path := ""
var _http: HTTPRequest
signal changed

func _ready() -> void:
	public_key = CryptoKey.new()
	public_key.load("res://assets/update_public.pem", true)
	DirAccess.make_dir_recursive_absolute(DIRECTORY)
	_remove_replaced.call_deferred()

## Whether this build can replace its own executable; editor runs and other platforms only open the release page.
func installs_in_place() -> bool:
	return OS.get_name() == "Windows" and OS.has_feature("template")

func _file_entry(value: Variant, extension: String) -> bool:
	if not value is Dictionary or not value.get("url") is String or not value.get("sha256") is String: return false
	if not value.get("bytes") is float and not value.get("bytes") is int: return false
	if value.bytes != int(value.bytes) or value.bytes < 1 or value.bytes > MAX_INSTALLER: return false
	var url: String = value.url
	var name := url.get_file()
	var pattern := RegEx.new()
	pattern.compile("^Frontline-[A-Za-z0-9.-]+\\." + extension + "$")
	if not url.begins_with(DOWNLOAD_PREFIX) or url.contains("..") or url.contains("?") or url.contains("#") or pattern.search(name) == null: return false
	pattern.compile("^[a-f0-9]{64}$")
	return pattern.search(value.sha256) != null

## Returns the release a manifest describes, or an empty dictionary unless the maintainer's key signed it.
func verify(value: Variant) -> Dictionary:
	if not value is Dictionary or not value.get("payload") is String or not value.get("signature") is String: return {}
	if value.payload.length() > MANIFEST_LIMIT or value.signature.length() > 2048: return {}
	var digest := HashingContext.new()
	digest.start(HashingContext.HASH_SHA256)
	digest.update(value.payload.to_utf8_buffer())
	if not Crypto.new().verify(HashingContext.HASH_SHA256, digest.finish(), Marshalls.base64_to_raw(value.signature), public_key): return {}
	var parsed: Variant = JSON.parse_string(value.payload)
	if not parsed is Dictionary or parsed.get("schema") != 2: return {}
	if not parsed.get("build") is float and not parsed.get("build") is int: return {}
	if parsed.build != int(parsed.build) or parsed.build < 900 or not parsed.get("version") is String or parsed.version.length() > 32: return {}
	if not parsed.get("files") is Dictionary or not _file_entry(parsed.files.get("exe"), "exe") or not _file_entry(parsed.files.get("apk"), "apk"): return {}
	if parsed.has("notes") and (not parsed.notes is String or parsed.notes.length() > 4000): return {}
	return parsed

func newer() -> bool:
	return not available.is_empty() and int(available.build) > current_build

func _process(_delta: float) -> void:
	if _http != null and busy and _http.get_body_size() > 0:
		progress = float(_http.get_downloaded_bytes()) / float(_http.get_body_size())
		status = "正在下载 %d%%" % int(progress * 100.0)
		changed.emit()

func _request(url: String, timeout: float, limit: int, output: String = "", redirects: int = 0) -> Array:
	_http = HTTPRequest.new()
	_http.timeout = timeout
	_http.body_size_limit = limit
	_http.max_redirects = redirects
	_http.download_file = output
	add_child(_http)
	if _http.request(url) != OK:
		_http.queue_free()
		_http = null
		return []
	var response: Array = await _http.request_completed
	_http.queue_free()
	_http = null
	return response

## Reads the manifest from GitHub, falling back to the mirror; the signature makes both sources equally trustworthy.
func check() -> void:
	if busy: return
	busy = true
	signature_failed = false
	status = "正在检查更新"
	changed.emit()
	var roots: Array = CardArtCache.remote_roots
	var reached := false
	var found: Dictionary = {}
	for index in roots.size():
		var response := await _request(str(roots[index]) + MANIFEST, PRIMARY_TIMEOUT if index == 0 and roots.size() > 1 else MIRROR_TIMEOUT, MANIFEST_LIMIT)
		if response.is_empty() or response[0] != HTTPRequest.RESULT_SUCCESS or response[1] != 200: continue
		reached = true
		found = verify(JSON.parse_string(response[3].get_string_from_utf8()))
		if not found.is_empty(): break
	busy = false
	if not found.is_empty():
		available = found
		status = ("发现新版本 " + str(found.version)) if newer() else "已是最新版本"
	elif reached:
		signature_failed = true
		status = "更新信息签名无效，已忽略"
	else:
		status = "暂时无法检查更新"
	changed.emit()

func _valid_file(path: String, item: Dictionary) -> bool:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return false
	var correct: bool = file.get_length() == int(item.bytes)
	file.close()
	return correct and FileAccess.get_sha256(path) == item.sha256

## Installers land beside the running game when that folder is writable, so the new build replaces it in place.
func _install_directory() -> String:
	var folder := OS.get_executable_path().get_base_dir()
	var probe := folder.path_join(".frontline-write-test")
	var file := FileAccess.open(probe, FileAccess.WRITE)
	if file == null: return ProjectSettings.globalize_path(DIRECTORY)
	file.close()
	DirAccess.remove_absolute(probe)
	return folder

func download() -> void:
	if busy or not newer(): return
	if not installs_in_place():
		# Android installs only through the system installer, which also enforces the same signing key.
		var key := "apk" if OS.get_name() == "Android" else "exe"
		status = "已在浏览器中打开下载，安装后重新打开游戏" if OS.shell_open(available.files[key].url) == OK else "无法打开浏览器，请到 GitHub Releases 下载"
		changed.emit()
		return
	var item: Dictionary = available.files.exe
	var target := _install_directory().path_join(str(item.url).get_file())
	if target == OS.get_executable_path(): return
	busy = true
	progress = 0.0
	status = "正在下载 0%"
	changed.emit()
	if not _valid_file(target, item):
		var part := target + ".part"
		# GitHub serves release assets through a redirect to its file host.
		var result := await _request(item.url, DOWNLOAD_TIMEOUT, int(item.bytes) + 1024, part, 5)
		if result.is_empty() or result[0] != HTTPRequest.RESULT_SUCCESS or result[1] != 200 or not _valid_file(part, item):
			DirAccess.remove_absolute(part)
			busy = false
			status = "下载未完成或文件校验失败，请重试"
			changed.emit()
			return
		DirAccess.remove_absolute(target)
		if DirAccess.rename_absolute(part, target) != OK:
			busy = false
			status = "无法保存安装包"
			changed.emit()
			return
	busy = false
	ready_path = target
	status = "新版本已下载，点击“安装并重启”"
	changed.emit()

## Starts the new build and exits; the new build removes this executable once it has closed.
func install() -> void:
	if ready_path.is_empty() or busy: return
	if not _valid_file(ready_path, available.files.exe):
		ready_path = ""
		status = "安装包已损坏，请重新下载"
		changed.emit()
		return
	if OS.create_process(ready_path, ["--", "--replaced=" + OS.get_executable_path()]) <= 0:
		status = "无法启动新版本，请手动打开 " + ready_path.get_file()
		changed.emit()
		return
	get_tree().quit()

## Only an older Frontline executable in the same folder is ever removed, and only when this build was started to replace it.
func replaced_path(arguments: PackedStringArray) -> String:
	for argument in arguments:
		if not argument.begins_with("--replaced="): continue
		# Windows paths compare case-insensitively and may use either slash.
		var path := argument.trim_prefix("--replaced=").replace("\\", "/")
		var pattern := RegEx.new()
		pattern.compile("^Frontline-[A-Za-z0-9.-]+\\.exe$")
		var own := OS.get_executable_path().replace("\\", "/")
		if pattern.search(path.get_file()) != null and path.get_base_dir().to_lower() == own.get_base_dir().to_lower() and path.to_lower() != own.to_lower(): return path
	return ""

func _remove_replaced() -> void:
	if not installs_in_place(): return
	var path := replaced_path(OS.get_cmdline_user_args())
	if path.is_empty(): return
	for attempt in REMOVE_ATTEMPTS:
		if not FileAccess.file_exists(path) or DirAccess.remove_absolute(path) == OK: return
		await get_tree().create_timer(0.5).timeout

func action_text() -> String:
	if busy: return "请稍候…"
	if not ready_path.is_empty(): return "安装并重启"
	if newer(): return ("下载 " if installs_in_place() else "前往下载 ") + str(available.version)
	return "检查更新"

func act() -> void:
	if busy: return
	if not ready_path.is_empty(): install()
	elif newer(): await download()
	else: await check()
