extends SceneTree
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

func _run() -> void:
	var updater := Updater.new()
	updater.public_key = CryptoKey.new()
	updater.public_key.load("res://assets/update_public.pem", true)
	var path := OS.get_environment("FRONTLINE_UPDATE_FIXTURE")
	var envelope: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	var release := updater.verify(envelope)
	check(not release.is_empty(), "Node RSA signature verifies in Godot")
	check(release.build == 802, "signed build is preserved")
	var modified := envelope.duplicate(true)
	modified.payload += " "
	check(updater.verify(modified).is_empty(), "tampered payload rejected")
	modified = envelope.duplicate(true)
	modified.signature = "AAAA"
	check(updater.verify(modified).is_empty(), "invalid signature rejected")
	check(updater.verify({}).is_empty(), "missing fields rejected")
	var file := path.get_base_dir().path_join("patch.pck")
	check(updater._valid_file(file, release.files.pck), "valid resource pack hash and size")
	var wrong: Dictionary = release.files.pck.duplicate()
	wrong.bytes += 1
	check(not updater._valid_file(file, wrong), "wrong size rejected")
	wrong.bytes -= 1
	wrong.sha256 = "0".repeat(64)
	check(not updater._valid_file(file, wrong), "wrong hash rejected")
	check(ProjectSettings.load_resource_pack(file, true), "patch mounts without replacing engine")
	check(FileAccess.get_file_as_string("res://patch_probe.txt") == "PATCH_ACTIVATED", "patched resource visible")
	var parser = preload("res://scripts/core/strict_json.gd").new()
	check(not parser.parse('{"rate":33.3}').ok, "card JSON continues to reject fractional numbers")
	check(parser.parse('{"rate":33.3}', 64, true).ok, "statistics JSON accepts measured rates")
	var transport = load("res://tests/update_transport_fixture.gd").new()
	transport.directory = path.get_base_dir() + "/install-test-%d/" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(transport.directory)
	transport.source = file
	transport.available = release
	transport.envelope = envelope
	await transport.download()
	var active: String = transport.directory + "active.json"
	check(FileAccess.file_exists(active), "verified download activates atomically")
	check(transport._valid_file(transport.directory + "802.pck",release.files.pck), "activated download retains exact bytes")
	var previous := FileAccess.get_file_as_string(active)
	transport.corrupt = true
	await transport.download()
	check(FileAccess.get_file_as_string(active) == previous, "failed transfer preserves last working patch")
	check(not FileAccess.file_exists(transport.directory + "802.pck.part"), "failed transfer removes incomplete file")
	var boot := Updater.new()
	boot.directory = transport.directory
	boot._ready()
	check(boot.current_build == 802, "bootstrap mounts signed installed patch")
	check(FileAccess.file_exists(boot.directory + "boot_pending"), "patch startup is marked until main scene is healthy")
	boot.free()
	boot = Updater.new()
	boot.directory = transport.directory
	boot._ready()
	check(boot.current_build == 801 and not FileAccess.file_exists(active), "incomplete previous startup falls back to base")
	check(FileAccess.file_exists(boot.directory + "failed.json"), "failed patch record retained for diagnosis")
	for name in ["802.pck", "failed.json"]: DirAccess.remove_absolute(boot.directory + name)
	DirAccess.remove_absolute(boot.directory)
	boot.free()
	transport.free()
	updater.free()
	print("UPDATE_TEST_RESULT checks=%d failures=%d" % [checks,failures])
	quit(0 if failures == 0 else 1)
