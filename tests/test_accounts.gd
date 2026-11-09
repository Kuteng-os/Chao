extends SceneTree
const Store = preload("res://scripts/app_store.gd")
var checks := 0
var failures := 0
func check(value: bool, description: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(description)
func _initialize() -> void:
	if OS.get_environment("FRONTLINE_PROFILE_PATH").is_empty() or OS.get_environment("FRONTLINE_TEST_SERVER_URL").is_empty():
		quit(1)
		return
	call_deferred("run_tests")
func run_tests() -> void:
	var store := Store.new()
	root.add_child(store)
	store.set_process(false)
	store.settings.backend_url = OS.get_environment("FRONTLINE_TEST_SERVER_URL")
	var password := "isolated-test-password-123"
	var result := await store.account_register("游戏测试员", password)
	check(result.ok, "Game supports open registration")
	check(store.authenticated, "Registration authenticates game")
	check(store.account_identity.get("role") == "player", "Ordinary role")
	var owner := str(store.settings.owner_id)
	var old_token := str(store.settings.api_token)
	var pairing := await store.request("/v1/browser-sessions", HTTPClient.METHOD_POST, {})
	var browser := await store.request("/v1/browser-sessions/exchange", HTTPClient.METHOD_POST, {"code":pairing.data.code})
	check(browser.ok and browser.data.owner_id == owner, "Browser shares the game account")
	check(browser.data.access_token != old_token, "Browser has a separate session")
	result = await store.account_logout()
	check(result.ok and not store.authenticated, "Logout clears game identity")
	check(str(store.settings.api_token).is_empty(), "Logout clears persistent token")
	result = await store.account_login("游戏测试员", "incorrect")
	check(not result.ok, "Wrong password rejected")
	result = await store.account_login("游戏测试员", password)
	check(result.ok and store.settings.owner_id == owner, "Login recovers same player")
	result = await store.change_password(password, "changed-test-password-456")
	check(result.ok, "Change password works in game")
	check(store.settings.api_token != old_token, "Password change rotates token")
	check(not FileAccess.get_file_as_string(store.profile_path).contains(password), "Profile contains no password")
	await store.account_logout()
	result = await store.account_login("Xiangwu", password)
	check(result.ok and store.account_identity.get("role") == "admin", "Admin login")
	check(store.account_identity.get("must_change_password", false), "Initial password requires change")
	check(store.connection_note == "请修改初始密码", "Game shows required password change")
	var blocked := await store.request("/v1/admin/accounts")
	check(not blocked.ok, "Initial password session cannot administer")
	result = await store.change_password(password, "admin-changed-password-789")
	check(result.ok and not store.account_identity.get("must_change_password", true), "Admin can change initial password")
	var listing := await store.request("/v1/admin/accounts")
	check(listing.ok and listing.data.accounts.size() == 5, "Same five accounts on authoritative service")
	await store.account_logout()
	store.queue_free()
	await process_frame
	print("ACCOUNT_GAME_TESTS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
