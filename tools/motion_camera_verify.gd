## Headless regression check for split camera controls and reduced UI motion.
## Run:
##   redot --headless --path . res://tools/motion_camera_verify.tscn
##
## The check snapshots user://settings.cfg before exercising both the legacy
## sensitivity migration and current persistence, then restores it exactly.
extends Node

const SETTINGS_PATH := "user://settings.cfg"

var _failures := 0
var _settings_existed := false
var _settings_backup := PackedByteArray()
var root: Window


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	root = get_tree().root
	var config: Node = root.get_node_or_null("GameConfig")
	if config == null:
		push_error("motion_camera_verify: GameConfig autoload is missing")
		get_tree().quit(1)
		return
	_backup_settings_file()
	_check_defaults_and_migration(config)
	_check_current_persistence(config)
	_check_player_camera_axes(config)
	_check_photo_camera_axes()
	await _check_settings_panel(config)
	await _check_reduced_motion(config)
	_restore_settings_file()
	config.load_settings()

	if _failures == 0:
		print("MOTION CAMERA VERIFY: PASS")
		get_tree().quit(0)
		return
	print("MOTION CAMERA VERIFY: FAIL (%d)" % _failures)
	get_tree().quit(1)


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


func _check_defaults_and_migration(config: Node) -> void:
	var defaults: Dictionary = config.DEFAULT_SETTINGS
	for key in ["mouse_sensitivity", "mouse_sensitivity_x", "mouse_sensitivity_y", "invert_y", "reduced_motion"]:
		_expect(defaults.has(key), "DEFAULT_SETTINGS is missing %s" % key)
	_expect(is_equal_approx(float(defaults["mouse_sensitivity_x"]), float(defaults["mouse_sensitivity"])),
		"horizontal sensitivity must retain the legacy default")
	_expect(is_equal_approx(float(defaults["mouse_sensitivity_y"]), float(defaults["mouse_sensitivity"])),
		"vertical sensitivity must retain the legacy default")

	# Simulate a pre-split settings.cfg containing only the old shared key.
	var legacy := ConfigFile.new()
	legacy.set_value("settings", "mouse_sensitivity", 0.0037)
	_expect(legacy.save(SETTINGS_PATH) == OK, "could not write legacy settings fixture")
	config.load_settings()
	_expect(is_equal_approx(float(config.get_mouse_sensitivity_x()), 0.0037),
		"legacy sensitivity did not migrate to the horizontal axis")
	_expect(is_equal_approx(float(config.get_mouse_sensitivity_y()), 0.0037),
		"legacy sensitivity did not migrate to the vertical axis")
	_expect(not config.is_invert_y(), "invert Y should default off for legacy users")
	_expect(not config.is_reduced_motion(), "reduced motion should default off for legacy users")


func _check_current_persistence(config: Node) -> void:
	config.set_setting("mouse_sensitivity_x", 0.0013)
	config.set_setting("mouse_sensitivity_y", 0.0041)
	config.set_setting("invert_y", true)
	config.set_setting("reduced_motion", true)
	config.save_settings()
	config.settings["mouse_sensitivity_x"] = 0.0022
	config.settings["mouse_sensitivity_y"] = 0.0022
	config.settings["invert_y"] = false
	config.settings["reduced_motion"] = false
	config.load_settings()
	_expect(is_equal_approx(float(config.get_mouse_sensitivity_x()), 0.0013), "horizontal sensitivity did not persist")
	_expect(is_equal_approx(float(config.get_mouse_sensitivity_y()), 0.0041), "vertical sensitivity did not persist")
	_expect(config.is_invert_y(), "invert Y did not persist")
	_expect(config.is_reduced_motion(), "reduced motion did not persist")


func _check_player_camera_axes(config: Node) -> void:
	config.set_setting("mouse_sensitivity_x", 0.001)
	config.set_setting("mouse_sensitivity_y", 0.004)
	config.set_setting("invert_y", false)
	var player_script: GDScript = load("res://player/player.gd")
	var player: Node3D = player_script.new()
	var head := Node3D.new()
	player.add_child(head)
	player.set("head", head)
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(10.0, 10.0)
	player.call("_apply_mouse_look", motion.relative)
	_expect(is_equal_approx(player.rotation.y, -0.01), "player did not use horizontal sensitivity")
	_expect(is_equal_approx(head.rotation.x, -0.04), "player did not use vertical sensitivity")
	config.set_setting("invert_y", true)
	motion.relative = Vector2(0.0, 10.0)
	player.call("_apply_mouse_look", motion.relative)
	_expect(is_equal_approx(head.rotation.x, 0.0), "player invert Y did not reverse vertical look")
	player.free()


func _check_photo_camera_axes() -> void:
	var root_node := Node3D.new()
	root.add_child(root_node)
	var player_camera := Camera3D.new()
	root_node.add_child(player_camera)
	var hud := Control.new()
	root_node.add_child(hud)
	var photo_script: GDScript = load("res://game/photo_mode.gd")
	var photo: Node = photo_script.new()
	photo.initialize(player_camera, hud)
	photo.mouse_sensitivity_x_provider = func() -> float: return 0.001
	photo.mouse_sensitivity_y_provider = func() -> float: return 0.004
	photo.invert_y_provider = func() -> bool: return false
	root_node.add_child(photo)
	photo.set_free_camera(true)
	photo._look(Vector2(10.0, 10.0))
	_expect(is_equal_approx(photo.get_camera().rotation.y, -0.01), "photo camera did not use horizontal sensitivity")
	_expect(is_equal_approx(photo.get_camera().rotation.x, -0.04), "photo camera did not use vertical sensitivity")
	photo.invert_y_provider = func() -> bool: return true
	photo._look(Vector2(0.0, 10.0))
	_expect(is_equal_approx(photo.get_camera().rotation.x, 0.0), "photo camera invert Y did not reverse vertical look")
	root_node.queue_free()


func _check_settings_panel(config: Node) -> void:
	var menu: Node = load("res://ui/main_menu.tscn").instantiate()
	root.add_child(menu)
	await get_tree().process_frame
	menu._on_settings()
	var gameplay: Node = menu.get_node("SettingsMenu/GameplayCategory")
	gameplay.open_panel()
	await get_tree().process_frame
	_expect(_find_label(gameplay, "Horizontal Sensitivity") != null, "Gameplay is missing Horizontal Sensitivity")
	_expect(_find_label(gameplay, "Vertical Sensitivity") != null, "Gameplay is missing Vertical Sensitivity")
	var invert := _find_check(gameplay, "Invert Y Axis")
	var reduced := _find_check(gameplay, "Reduced Motion")
	_expect(invert != null, "Gameplay is missing Invert Y Axis")
	_expect(reduced != null, "Gameplay is missing Reduced Motion")
	if invert != null:
		invert.toggled.emit(false)
		_expect(not config.is_invert_y(), "Invert Y checkbox did not update GameConfig")
	if reduced != null:
		reduced.toggled.emit(true)
		_expect(config.is_reduced_motion(), "Reduced Motion checkbox did not update GameConfig")
	menu.queue_free()
	await get_tree().process_frame


func _check_reduced_motion(config: Node) -> void:
	config.set_setting("reduced_motion", true)
	var motion: GDScript = load("res://ui/motion.gd")
	var control := Control.new()
	control.visible = true
	control.modulate.a = 0.25
	control.scale = Vector2(0.5, 0.5)
	root.add_child(control)
	motion.call("pop_in", control)
	_expect(control.scale.is_equal_approx(Vector2.ONE) and is_equal_approx(control.modulate.a, 1.0),
		"reduced-motion pop should finish immediately")
	control.modulate.a = 0.25
	motion.call("fade_in", control)
	_expect(is_equal_approx(control.modulate.a, 1.0), "reduced-motion fade should finish immediately")
	control.scale = Vector2(0.5, 0.5)
	motion.call("pulse", control)
	_expect(control.scale.is_equal_approx(Vector2.ONE), "reduced-motion pulse should not tween")
	var dim := ColorRect.new()
	dim.modulate.a = 0.25
	root.add_child(dim)
	motion.call("dim_in", dim)
	_expect(is_equal_approx(dim.modulate.a, 1.0), "reduced-motion dim should finish immediately")
	var second := Control.new()
	second.modulate.a = 0.25
	second.scale = Vector2(0.5, 0.5)
	root.add_child(second)
	motion.call("stagger_in", [control, second])
	_expect(is_equal_approx(second.modulate.a, 1.0) and second.scale.is_equal_approx(Vector2.ONE),
		"reduced-motion stagger should finish immediately")
	config.set_setting("reduced_motion", false)
	control.queue_free()
	dim.queue_free()
	second.queue_free()
	await get_tree().process_frame


func _find_label(panel: Node, text: String) -> Label:
	var rows := panel.find_child("RowsBox", true, false)
	if rows == null:
		return null
	for row in rows.get_children():
		for child in row.get_children():
			if child is Label and (child as Label).text == text:
				return child
	return null


func _find_check(panel: Node, text: String) -> CheckBox:
	var rows := panel.find_child("RowsBox", true, false)
	if rows == null:
		return null
	for child in rows.get_children():
		if child is CheckBox and (child as CheckBox).text == text:
			return child
	return null


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("motion_camera_verify: %s" % message)
