## Headless check for the Display frame-pacing settings: key defaults, vsync and
## FPS-cap application, the option value tables rendered by the Display panel,
## and the pure dynamic-resolution stepping policy.
## Run:
##   redot --headless --path . --script res://tools/frame_pacing_verify.gd
##
## Nodes stay untyped and scenes are loaded at runtime: a --script SceneTree
## parses before autoloads exist, so naming UI classes at parse time fails.
extends SceneTree

var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var config: Node = root.get_node_or_null("GameConfig")
	if config == null:
		push_error("frame_pacing_verify: GameConfig autoload is missing")
		quit(1)
		return

	_check_defaults(config)
	_check_option_snapping(config)
	_check_engine_application(config)
	_check_policy(config)
	await _check_display_panel(config)

	if _failures == 0:
		print("FRAME PACING VERIFY: PASS")
		quit(0)
		return
	print("FRAME PACING VERIFY: FAIL (%d)" % _failures)
	quit(1)


func _check_defaults(config: Node) -> void:
	var defaults: Dictionary = config.DEFAULT_SETTINGS
	for key in ["vsync", "fps_cap", "dynamic_resolution", "dynamic_resolution_target"]:
		_expect(defaults.has(key), "DEFAULT_SETTINGS is missing %s" % key)
	_expect(int(defaults["vsync"]) == 1, "vsync should default to On")
	_expect(int(defaults["fps_cap"]) == 0, "fps_cap should default to Unlimited")
	_expect(bool(defaults["dynamic_resolution"]) == false, "dynamic resolution should default off")
	_expect(int(defaults["dynamic_resolution_target"]) == 60, "dynamic target should default to 60 FPS")
	_expect((config.FPS_CAP_VALUES as Array).size() == (config.FPS_CAP_NAMES as Array).size(), "FPS cap tables diverged")
	_expect((config.DYNAMIC_RESOLUTION_TARGET_VALUES as Array).size() == (config.DYNAMIC_RESOLUTION_TARGET_NAMES as Array).size(), "dynamic target tables diverged")
	_expect((config.VSYNC_NAMES as Array).size() == 4, "vsync should expose four modes")


func _check_option_snapping(config: Node) -> void:
	_expect(int(config.nearest_option(100, config.FPS_CAP_VALUES)) == 90, "an out-of-table FPS cap should snap to the nearest option")
	_expect(int(config.nearest_option(1000, config.FPS_CAP_VALUES)) == 240, "an oversized FPS cap should snap to the highest option")
	_expect(int(config.nearest_option(-5, config.FPS_CAP_VALUES)) == 0, "a negative FPS cap should snap to Unlimited")
	_expect(int(config.nearest_option(72, config.DYNAMIC_RESOLUTION_TARGET_VALUES)) == 60, "a 72 FPS target should snap to 60")


func _check_engine_application(config: Node) -> void:
	for value in [0, 30, 60, 144, 240]:
		config.set_setting("fps_cap", value)
		_expect(Engine.max_fps == value, "fps_cap %d did not reach Engine.max_fps" % value)
	config.set_setting("fps_cap", 0)
	_expect(Engine.max_fps == 0, "Unlimited should reset Engine.max_fps")
	for value in [0, 1, 2, 3, 7]:
		config.set_setting("vsync", value)
		_expect(config.get_vsync_mode() == clampi(value, 0, 3), "vsync %d did not clamp to a display mode" % value)
	config.set_setting("vsync", 1)


func _check_policy(config: Node) -> void:
	var target := 1.0 / 60.0
	var max_scale := 0.77
	_expect(is_equal_approx(config.dynamic_resolution_scale(0.70, 0.033, target, max_scale), 0.65), "an over-budget frame should step the scale down")
	_expect(is_equal_approx(config.dynamic_resolution_scale(0.70, target, target, max_scale), 0.70), "a frame inside the target band should not move the scale")
	_expect(is_equal_approx(config.dynamic_resolution_scale(0.70, 0.008, target, max_scale), 0.75), "a frame under budget should step the scale up")
	_expect(is_equal_approx(config.dynamic_resolution_scale(max_scale, 0.008, target, max_scale), max_scale), "the configured render scale is the ceiling")
	_expect(is_equal_approx(config.dynamic_resolution_scale(float(config.DYNAMIC_RESOLUTION_MIN_SCALE), 0.033, target, max_scale), float(config.DYNAMIC_RESOLUTION_MIN_SCALE)), "the floor is never crossed")
	_expect(is_equal_approx(config.dynamic_resolution_scale(0.70, 1.0 / 30.0, target, max_scale, 1.0 / 30.0), 0.70), "a 30 FPS cap should not read as GPU load against a 60 FPS target")
	_expect(is_equal_approx(config.dynamic_resolution_scale(0.70, 0.033, target, 0.4), float(config.DYNAMIC_RESOLUTION_MIN_SCALE)), "a sub-floor render scale clamps to the floor")


func _check_display_panel(config: Node) -> void:
	config.set_setting("dynamic_resolution", false)
	config.set_setting("fps_cap", 0)
	config.set_setting("dynamic_resolution_target", 60)
	var menu: Node = load("res://ui/main_menu.tscn").instantiate()
	root.add_child(menu)
	await process_frame
	menu._on_settings()
	var display: Node = menu.get_node("SettingsMenu/DisplayCategory")
	display.open_panel()
	await process_frame

	var vsync_option := _find_option(display, "V-Sync")
	var cap_option := _find_option(display, "FPS Cap")
	var target_option := _find_option(display, "Dynamic Target")
	var dynamic_check := _find_check(display, "Dynamic Resolution")
	_expect(vsync_option != null and vsync_option.item_count == 4, "Display is missing the four-mode V-Sync row")
	_expect(cap_option != null and cap_option.item_count == (config.FPS_CAP_VALUES as Array).size(), "Display is missing the FPS Cap row")
	_expect(target_option != null, "Display is missing the Dynamic Target row")
	_expect(dynamic_check != null, "Display is missing the Dynamic Resolution row")
	if target_option != null:
		_expect(not target_option.is_visible_in_tree(), "the dynamic target row should hide while dynamic resolution is off")
	if cap_option != null:
		cap_option.item_selected.emit(2)
		_expect(int(config.get_setting("fps_cap")) == 60, "selecting 60 FPS should store the mapped value")
		_expect(Engine.max_fps == 60, "selecting 60 FPS should cap the engine")
	if target_option != null:
		target_option.item_selected.emit(3)
		_expect(int(config.get_setting("dynamic_resolution_target")) == 120, "selecting 120 FPS should store the mapped dynamic target")
	if dynamic_check != null:
		dynamic_check.button_pressed = true
		_expect(bool(config.get_setting("dynamic_resolution")), "toggling dynamic resolution should store the setting")
		if target_option != null:
			_expect(target_option.is_visible_in_tree(), "the dynamic target row should appear while dynamic resolution is on")
		dynamic_check.button_pressed = false
		if target_option != null:
			_expect(not target_option.is_visible_in_tree(), "the dynamic target row should hide again when dynamic resolution is off")
	menu.queue_free()


func _find_option(panel: Node, label_text: String) -> OptionButton:
	var rows := panel.find_child("RowsBox", true, false)
	if rows == null:
		return null
	for row in rows.get_children():
		if not row is HBoxContainer:
			continue
		var name_label := row.get_child(0) as Label
		if name_label == null or name_label.text != label_text:
			continue
		for child in row.get_children():
			if child is OptionButton:
				return child
	return null


func _find_check(panel: Node, label_text: String) -> CheckBox:
	var rows := panel.find_child("RowsBox", true, false)
	if rows == null:
		return null
	for row in rows.get_children():
		if row is CheckBox and (row as CheckBox).text == label_text:
			return row
	return null


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("frame_pacing_verify: %s" % message)
