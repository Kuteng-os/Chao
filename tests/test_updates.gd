extends SceneTree
## Run: FRONTLINE_UPDATE_FIXTURE=<signed client.json> godot --headless --path . -s tests/test_updates.gd
## The fixture is produced by tools/publish_client.mjs, so this proves Node signatures verify in Godot.
var checks := 0
var failures := 0
const Updater = preload("res://scripts/client_update.gd")

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, description: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(description)

func _signed_copy(envelope: Dictionary, change: Callable) -> Dictionary:
	var payload: Dictionary = JSON.parse_string(envelope.payload)
	change.call(payload)
	return {"payload": JSON.stringify(payload), "signature": envelope.signature}

func _run() -> void:
	var updater: Node = Updater.new()
	updater.public_key = CryptoKey.new()
	updater.public_key.load("res://assets/update_public.pem", true)
	var envelope: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(OS.get_environment("FRONTLINE_UPDATE_FIXTURE")))
	var release: Dictionary = updater.verify(envelope)
	check(not release.is_empty(), "Node RSA signature verifies in Godot")
	check(str(release.get("files", {}).get("exe", {}).get("url", "")).begins_with(Updater.DOWNLOAD_PREFIX), "installers come from GitHub Releases")

	var modified := envelope.duplicate(true)
	modified.payload += " "
	check(updater.verify(modified).is_empty(), "tampered payload rejected")
	modified = envelope.duplicate(true)
	modified.signature = "AAAA"
	check(updater.verify(modified).is_empty(), "invalid signature rejected")
	check(updater.verify({}).is_empty(), "missing fields rejected")
	check(updater.verify(_signed_copy(envelope, func(p): p.files.exe.url = "https://example.com/Frontline-9.exe")).is_empty(), "a modified installer URL is rejected")

	updater.available = release
	updater.current_build = int(release.build) - 1
	check(updater.newer(), "a higher signed build is offered")
	updater.current_build = int(release.build)
	check(not updater.newer(), "the same build is not offered again")

	var own: String = OS.get_executable_path()
	var sibling := own.get_base_dir().path_join("Frontline-0.9.9.exe")
	check(updater.replaced_path(PackedStringArray(["--replaced=" + sibling])) == sibling, "an older build in the same folder can be removed")
	check(updater.replaced_path(PackedStringArray(["--replaced=" + sibling.get_base_dir().replace("/", "\\").to_upper() + "\\" + sibling.get_file()])).to_lower() == sibling.to_lower(), "backslashes and letter case do not matter")
	check(updater.replaced_path(PackedStringArray(["--replaced=C:/Windows/notepad.exe"])).is_empty(), "other programs are never removed")
	check(updater.replaced_path(PackedStringArray(["--replaced=D:/elsewhere/Frontline-0.9.9.exe"])).is_empty(), "other folders are never touched")
	check(updater.replaced_path(PackedStringArray(["--replaced=" + own])).is_empty(), "the running build never removes itself")
	updater.free()
	print("update checks: ", checks, " failures: ", failures)
	quit(1 if failures > 0 else 0)
