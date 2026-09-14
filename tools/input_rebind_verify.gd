## Headless check for key rebinding: the GameConfig binding table covers every
## non-`ui_*` InputMap action, overrides apply to the InputMap, reset restores
## project defaults, settings.cfg round-trips bindings, and the Controls screen
## captures a key and cancels on Escape.
## Run:
##   redot --headless --path . --script res://tools/input_rebind_verify.gd
##
## The check snapshots user://settings.cfg before touching bindings and restores
## the exact bytes at the end, so a developer's real settings survive.
##
## Nodes stay untyped and scenes are loaded at runtime: a --script SceneTree
## parses before autoloads exist, so naming UI classes at parse time fails.
extends SceneTree

const SETTINGS_PATH := "user://settings.cfg"

var _failures := 0
var _settings_existed := false
var _settings_backup := PackedByteArray()


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var config: Node = root.get_node_or_null("GameConfig")
	if config == null:
		push_error("input_rebind_verify: GameConfig autoload is missing")
		quit(1)
		return
	_backup_settings_file()
	config.reset_input_bindings()

	_check_defaults(config)
	_check_coverage(config)
	_check_apply_and_reset(config)
	_check_conflicts(config)
	_check_required_labels(config)
	_check_multi_default_safety(config)
	_check_persistence(config)
	await _check_controls_panel(config)
	await _check_pause_settings_signal()

	_restore_settings_file()
	config.load_settings()

	if _failures == 0:
		print("INPUT REBIND VERIFY: PASS")
		quit(0)
		return
	print("INPUT REBIND VERIFY: FAIL (%d)" % _failures)
	quit(1)


func _backup_settings_file() -> void:
	_settings_existed = FileAccess.file_exists(SETTINGS_PATH)
	if _settings_existed:
		_settings_backup = FileAccess.get_file_as_bytes(SETTINGS_PATH)


func _restore_settings_file() -> void:
	if _settings_existed:
		var file := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
		if file != null:
			file.store_buffer(_settings_backup)
	else:
		DirAccess.remove_absolute(SETTINGS_PATH)


func _check_defaults(config: Node) -> void:
	var defaults: Dictionary = config.DEFAULT_SETTINGS
	_expect(defaults.has("input_bindings"), "DEFAULT_SETTINGS is missing input_bindings")
	_expect(not config.has_custom_input_bindings(), "a fresh reset should report no custom bindings")
	_expect(config.default_input_binding("move_forward") == KEY_W, "move_forward should default to W")
	_expect(config.default_input_binding("inventory") == KEY_E, "inventory should default to E")
	_expect(config.default_input_binding("jump") == KEY_SPACE, "jump should default to Space")
	_expect(config.key_label(KEY_W) == "W", "key_label should render a physical key name")
	_expect(config.key_label(KEY_BRACKETRIGHT) == "]", "key_label should prefer punctuation glyphs")


func _check_coverage(config: Node) -> void:
	var known := {}
	for entry in config.rebindable_actions():
		known[String(entry["action"])] = true
	for action_name in InputMap.get_actions():
		var action := String(action_name)
		if action.begins_with("ui_"):
			continue
		_expect(known.has(action), "action %s is missing from the Controls rows" % action)
		_expect(config.default_input_binding(action) != 0, "action %s has no project default key" % action)


func _check_apply_and_reset(config: Node) -> void:
	config.set_input_binding("move_forward", KEY_I)
	_expect(config.get_input_binding("move_forward") == KEY_I, "set_input_binding did not store the override")
	_expect(config.has_custom_input_bindings(), "override should mark the bindings custom")
	_expect(_event_matches("move_forward", KEY_I), "the InputMap did not receive the new key")
	config.set_input_binding("move_forward", KEY_W)
	_expect(not config.has_custom_input_bindings(), "binding a key back to its default should drop the override")
	_expect(_event_matches("move_forward", KEY_W), "the InputMap should return to the project default")

	config.set_input_binding("jump", KEY_J)
	_expect(_event_matches("jump", KEY_J), "jump did not accept the override")
	config.reset_input_bindings()
	_expect(not config.has_custom_input_bindings(), "reset should clear every override")
	_expect(_event_matches("jump", KEY_SPACE), "reset did not restore the project default")


func _check_conflicts(config: Node) -> void:
	var shared: Array = config.actions_for_key(KEY_SPACE, "jump")
	_expect(shared.has("fly_up"), "Space should report fly_up as a shared action")
	config.set_input_binding("move_forward", KEY_E)
	var conflicts: Array = config.actions_for_key(KEY_E, "move_forward")
	_expect(conflicts.has("inventory"), "conflict lookup missed inventory sharing E")
	config.reset_input_bindings()


func _check_required_labels(config: Node) -> void:
	_expect(config.input_action_label("move_forward") == "Move Forward", "known actions should keep their display label")
	_expect(config.input_action_label("some_future_action") == "Some Future Action", "unknown actions should get a generated label")
	_expect(config.input_move_hint() == "WASD", "single-character move keys should compact to WASD")
	config.set_input_binding("move_forward", KEY_UP)
	_expect(config.input_move_hint() == "Up/A/S/D", "multi-character move keys should be slash-joined")
	config.reset_input_bindings()


## Latent case: an action whose project default declares two keys must keep
## both after the default is re-applied (no override stored).
func _check_multi_default_safety(config: Node) -> void:
	ProjectSettings.set_setting("input/rebind_probe", {
		"deadzone": 0.5,
		"events": [_key_event(KEY_W, true), _key_event(KEY_UP, false)],
	})
	InputMap.add_action("rebind_probe")
	config.apply_input_binding("rebind_probe")
	var keycodes: Array[int] = []
	for event in InputMap.action_get_events("rebind_probe"):
		if event is InputEventKey:
			var key := event as InputEventKey
			keycodes.append(key.physical_keycode if key.physical_keycode != 0 else key.keycode)
	_expect(keycodes.has(KEY_W) and keycodes.has(KEY_UP), "a multi-key default should keep every key")
	_expect(config.default_input_binding("rebind_probe") == KEY_W, "the first default key should be reported")
	InputMap.erase_action("rebind_probe")
	ProjectSettings.set_setting("input/rebind_probe", null)


func _key_event(keycode: int, physical: bool) -> InputEventKey:
	var event := InputEventKey.new()
	if physical:
		event.physical_keycode = keycode
	else:
		event.keycode = keycode
	return event


func _check_persistence(config: Node) -> void:
	config.set_input_binding("inventory", KEY_TAB)
	config.settings["input_bindings"] = {}
	config.apply_input_bindings()
	config.load_settings()
	_expect(config.get_input_binding("inventory") == KEY_TAB, "settings.cfg did not round-trip the binding")
	_expect(_event_matches("inventory", KEY_TAB), "loading settings did not apply the saved binding")


func _check_controls_panel(config: Node) -> void:
	config.set_input_binding("inventory", KEY_E)
	var menu: Node = load("res://ui/main_menu.tscn").instantiate()
	root.add_child(menu)
	await process_frame
	menu._on_settings()
	await process_frame
	var settings_menu: Node = menu.get_node("SettingsMenu")
	var controls: Node = settings_menu.get_node_or_null("ControlsCategory")
	_expect(controls != null, "settings hub is missing the Controls category")
	if controls == null:
		menu.queue_free()
		return
	controls.open_panel()
	await process_frame
	_expect(controls.visible and settings_menu.visible, "Controls did not open over the hub")

	var button := _find_key_button(controls, "Inventory")
	_expect(button != null, "Controls is missing the Inventory row")
	if button == null:
		menu.queue_free()
		return
	button.pressed.emit()
	await process_frame
	_expect(button.text == "Press a key...", "clicking a key button should start listening")

	_send_key(KEY_J)
	await process_frame
	_expect(config.get_input_binding("inventory") == KEY_J, "capturing a key did not rebind the action")
	_expect(_event_matches("inventory", KEY_J), "the captured key did not reach the InputMap")

	button.pressed.emit()
	await process_frame
	_send_key(KEY_ESCAPE)
	await process_frame
	_expect(config.get_input_binding("inventory") == KEY_J, "Escape during capture should not change the binding")
	_expect(controls.visible and settings_menu.visible, "Escape during capture should not close the Controls panel")

	var reset_button := controls.get_node("Center/Panel/Box/Footer/ResetButton") as Button
	reset_button.pressed.emit()
	await process_frame
	_expect(config.get_input_binding("inventory") == KEY_E, "Reset to Defaults did not restore the binding")

	controls.close_panel()
	settings_menu.close_panel()
	menu.queue_free()
	await process_frame


## The in-game status toast refreshes off PauseMenu.settings_closed, so check
## the pause menu forwards its nested Settings close through that signal.
func _check_pause_settings_signal() -> void:
	var pause: Node = load("res://ui/pause_menu.tscn").instantiate()
	root.add_child(pause)
	await process_frame
	var emitted := [false]
	pause.settings_closed.connect(func() -> void: emitted[0] = true)
	var settings_menu: Node = pause.get_node("SettingsMenu")
	settings_menu.open_panel()
	await process_frame
	settings_menu.close_panel()
	await process_frame
	_expect(emitted[0], "closing Settings in the pause menu should emit settings_closed")
	pause.queue_free()
	await process_frame


func _find_key_button(panel: Node, label_text: String) -> Button:
	for child in panel.get_node("Center/Panel/Box/Scroll/RowsBox").get_children():
		if not child is HBoxContainer:
			continue
		var name_label := child.get_child(0) as Label
		if name_label == null or name_label.text != label_text:
			continue
		for row_child in child.get_children():
			if row_child is Button:
				return row_child
	return null


func _send_key(keycode: int) -> void:
	var pressed := InputEventKey.new()
	pressed.physical_keycode = keycode
	pressed.pressed = true
	Input.parse_input_event(pressed)
	var released := InputEventKey.new()
	released.physical_keycode = keycode
	released.pressed = false
	Input.parse_input_event(released)


func _event_matches(action: String, keycode: int) -> bool:
	for event in InputMap.action_get_events(action):
		if event is InputEventKey and (event as InputEventKey).physical_keycode == keycode:
			return true
	return false


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("input_rebind_verify: %s" % message)
