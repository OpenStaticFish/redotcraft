## Headless check for the menu information architecture: Play -> world setup ->
## advanced world gen, and Settings -> category submenus -> advanced graphics,
## including nested cancel routing and focus restoration.
## Run:
##   redot --headless --path . --script res://tools/ui_flow_verify.gd
##
## Nodes stay untyped and scenes are loaded at runtime: a --script SceneTree
## parses before autoloads exist, so naming UI classes at parse time fails.
extends SceneTree

var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var menu: Node = load("res://ui/main_menu.tscn").instantiate()
	root.add_child(menu)
	await process_frame

	var column: Node = menu.get_node("Center/Column")
	_expect(menu.get_node_or_null("Center/Column/WorldGenButton") == null, "standalone World Gen button should be gone")
	_expect(root.gui_get_focus_owner() == column.get_node("PlayButton"), "main menu did not focus Play")

	var play: Node = menu.get_node("PlayPanel")
	var worldgen: Node = menu.get_node("WorldGenPanel")
	menu._on_play()
	await process_frame
	_expect(play.visible, "Play did not open the world setup screen")
	_expect(root.gui_get_focus_owner() == play.get_node("Center/Panel/Box/SeedRow/SeedField"), "world setup did not focus the seed field")
	_expect(play.get_node("Center/Panel/Box/TypeRow/TypeOption").item_count == 3, "world type list is incomplete")

	# Advanced -> back restores the play screen.
	play.advanced_requested.emit()
	await process_frame
	_expect(worldgen.visible, "Advanced did not open the world gen screen")
	worldgen.close_panel()
	await process_frame
	_expect(play.visible and not worldgen.visible, "closing advanced should return to the play screen")
	_expect(root.gui_get_focus_owner() == play.get_node("Center/Panel/Box/Footer/AdvancedButton"), "advanced did not restore focus")

	# Config merge payload keeps every tunable the old combined panel created.
	var config: Dictionary = worldgen.build_config()
	for key in ["terrain_scale", "tree_density", "worldgen_version", "macro_scale", "biome_scale", "river_density", "erosion_strength", "regional_erosion", "hydraulic_erosion", "cave_density", "decoration_density"]:
		_expect(config.has(key), "advanced config is missing %s" % key)

	play.close_panel()
	await process_frame
	_expect(root.gui_get_focus_owner() == column.get_node("PlayButton"), "play screen did not restore focus")

	# Settings hub and category submenus.
	var settings: Node = menu.get_node("SettingsMenu")
	menu._on_settings()
	await process_frame
	_expect(settings.visible, "Settings did not open the hub")
	var display: Node = settings.get_node("DisplayCategory")
	var graphics: Node = settings.get_node("GraphicsCategory")
	var advanced: Node = settings.get_node("GraphicsPanel")
	display.open_panel()
	await process_frame
	_expect(display.visible and settings.visible, "display category did not open over the hub")
	_send_cancel()
	await process_frame
	_expect(not display.visible and settings.visible, "cancel should close only the display category")

	# Graphics -> advanced -> nested cancel -> hub -> menu.
	graphics.open_panel()
	await process_frame
	graphics.advanced_requested.emit()
	await process_frame
	_expect(advanced.visible, "Advanced graphics did not open")
	var lighting: Node = advanced.get_node("LightingSection")
	advanced._open_section_panel(lighting)
	await process_frame
	_expect(lighting.visible and advanced.visible, "advanced section did not open over the hub")
	_send_cancel()
	await process_frame
	_expect(not lighting.visible and advanced.visible, "cancel should close only the advanced section")
	_send_cancel()
	await process_frame
	_expect(graphics.visible and not advanced.visible, "cancel should close advanced graphics next")
	_expect(root.gui_get_focus_owner() == graphics.get_node("Center/Panel/Box/Footer/AdvancedButton"), "advanced did not restore focus to its opener")
	_send_cancel()
	await process_frame
	_expect(not graphics.visible and settings.visible, "cancel should close the graphics category next")
	_send_cancel()
	await process_frame
	_expect(not settings.visible, "cancel should close the settings hub last")
	_expect(root.gui_get_focus_owner() == column.get_node("SettingsButton"), "settings did not restore main-menu focus")

	if _failures == 0:
		print("UI FLOW VERIFY: PASS")
		quit(0)
		return
	print("UI FLOW VERIFY: FAIL (%d)" % _failures)
	quit(1)


func _send_cancel() -> void:
	var event := InputEventAction.new()
	event.action = "ui_cancel"
	event.pressed = true
	Input.parse_input_event(event)
	event = InputEventAction.new()
	event.action = "ui_cancel"
	event.pressed = false
	Input.parse_input_event(event)


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("ui_flow_verify: %s" % message)
