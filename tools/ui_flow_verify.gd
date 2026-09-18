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
var _library_root := "user://ui_flow_verify_%d" % Time.get_ticks_usec()


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var game_config: Node = root.get_node("GameConfig")
	var menu: Node = load("res://ui/main_menu.tscn").instantiate()
	root.add_child(menu)
	await process_frame

	var column: Node = menu.get_node("Center/Column")
	_expect(menu.get_node_or_null("Center/Column/WorldGenButton") == null, "standalone World Gen button should be gone")
	_expect(root.gui_get_focus_owner() == column.get_node("PlayButton"), "main menu did not focus Play")

	var play: Node = menu.get_node("PlayPanel")
	var worldgen: Node = menu.get_node("WorldGenPanel")
	play._library_root = _library_root
	menu._on_play()
	await process_frame
	_expect(play.visible, "Play did not open the worlds hub")
	_expect(root.gui_get_focus_owner() == play.get_node("Center/Panel/Box/LandingBox/NewWorldButton"),
		"worlds hub did not focus New World for an empty library")
	play.get_node("Center/Panel/Box/LandingBox/NewWorldButton").pressed.emit()
	await process_frame
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

	# Saved-world library: compatible worlds load, future worlds remain
	# selectable for deletion, confirmation unwinds first, and deleting the
	# active final world clears both active state and the list.
	play.get_node("Center/Panel/Box/Footer/BackButton").pressed.emit()
	await process_frame
	_create_world_fixture("alpha", "Alpha Ridge", 101, 100, false)
	_create_world_fixture("beta", "Beta Shore", 202, 200, false)
	_create_world_fixture("future", "Future Keep", 303, 300, true)
	play._refresh_landing()
	_expect(play.get_node("Center/Panel/Box/LandingBox/LandingHint").text.begins_with("3 saved worlds"),
		"worlds hub did not count saved worlds")
	play.get_node("Center/Panel/Box/LandingBox/LoadWorldButton").pressed.emit()
	await process_frame
	_expect(play._cards.size() == 3, "load view did not list every saved world")
	var future_card: Button = play._cards.get("future")
	_expect(future_card != null and not future_card.disabled,
		"incompatible world cannot be selected for deletion")
	if future_card != null:
		future_card.pressed.emit()
	_expect(play._selected_world_id == "future", "incompatible world was not selectable")
	_expect(play.get_node("Center/Panel/Box/LoadBox/LoadFooter/LoadButton").disabled,
		"incompatible world incorrectly enabled loading")
	_expect(not play.get_node("Center/Panel/Box/LoadBox/LoadFooter/DeleteButton").disabled,
		"incompatible world did not enable deletion")

	# Disconnect the menu's scene-changing handler while verifying the panel's
	# public signal in isolation.
	play.load_requested.disconnect(menu._on_load_world)
	var loaded_ids: Array[String] = []
	play.load_requested.connect(func(id: String) -> void: loaded_ids.append(id))
	var beta_card: Button = play._cards.get("beta")
	if beta_card != null:
		beta_card.pressed.emit()
	play.get_node("Center/Panel/Box/LoadBox/LoadFooter/LoadButton").pressed.emit()
	_expect(loaded_ids == ["beta"], "selected compatible world did not emit load_requested")

	var beta_metadata: Dictionary = WorldStorage.new(_library_root).open_world("beta")
	_expect(game_config.activate_world(beta_metadata), "could not activate deletion fixture")
	play.get_node("Center/Panel/Box/LoadBox/LoadFooter/DeleteButton").pressed.emit()
	await process_frame
	_expect(play._confirming_delete, "delete did not open confirmation")
	_expect(root.gui_get_focus_owner() == play.get_node("Center/Panel/Box/LoadBox/ConfirmRow/CancelDeleteButton"),
		"delete confirmation did not focus the safe choice")
	_send_cancel()
	await process_frame
	_expect(not play._confirming_delete, "cancel did not close delete confirmation first")
	_expect(play._selected_world_id == "beta", "canceling deletion lost the world selection")
	play.get_node("Center/Panel/Box/LoadBox/LoadFooter/DeleteButton").pressed.emit()
	play.get_node("Center/Panel/Box/LoadBox/ConfirmRow/ConfirmDeleteButton").pressed.emit()
	await process_frame
	_expect(String(game_config.active_world_id).is_empty(), "deleting the active world did not clear active state")
	_expect(not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(_library_root + "/beta")),
		"confirmed deletion left the world directory behind")

	var alpha_metadata: Dictionary = WorldStorage.new(_library_root).open_world("alpha")
	_expect(game_config.activate_world(alpha_metadata), "could not activate bulk-deletion fixture")
	var delete_all_button: Button = play.get_node("Center/Panel/Box/LoadBox/LoadFooter/DeleteAllButton")
	_expect(not delete_all_button.disabled, "Delete All was disabled with saved worlds present")
	delete_all_button.pressed.emit()
	await process_frame
	_expect(play._confirming_delete and play._confirming_delete_all,
		"Delete All did not open bulk confirmation")
	_expect(play.get_node("Center/Panel/Box/LoadBox/ConfirmRow/ConfirmLabel").text.begins_with("Delete all 2 saved worlds"),
		"Delete All confirmation did not report the affected world count")
	_send_cancel()
	await process_frame
	_expect(not play._confirming_delete and play._cards.size() == 2,
		"canceling Delete All removed worlds or left confirmation open")
	_expect(root.gui_get_focus_owner() == delete_all_button,
		"canceling Delete All did not restore focus")
	delete_all_button.pressed.emit()
	play.get_node("Center/Panel/Box/LoadBox/ConfirmRow/ConfirmDeleteButton").pressed.emit()
	await process_frame
	_expect(play._cards.is_empty(), "deleting every world did not empty the library")
	_expect(String(game_config.active_world_id).is_empty(), "Delete All did not clear the active world")
	_expect(delete_all_button.disabled, "Delete All remained enabled for an empty library")
	_expect(play.get_node("Center/Panel/Box/LoadBox/LoadScroll/EmptyState").visible,
		"empty-library state was not shown")
	_expect(root.gui_get_focus_owner() == play.get_node("Center/Panel/Box/LoadBox/LoadScroll/EmptyState/EmptyCreateButton"),
		"empty-library state did not focus Create")
	_send_cancel()
	await process_frame
	_expect(root.gui_get_focus_owner() == play.get_node("Center/Panel/Box/LandingBox/NewWorldButton"),
		"returning from an empty load view did not focus an enabled landing action")

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


func _create_world_fixture(id: String, display_name: String, seed: int, updated: int, future: bool) -> void:
	var storage := WorldStorage.new(_library_root)
	var config := WorldGenConfig.new({"seed": seed}).to_dictionary()
	var metadata: Dictionary = storage.create_world(config, {}, id)
	metadata["name"] = display_name
	metadata["created_unix"] = updated - 10
	metadata["updated_unix"] = updated
	if future:
		(metadata["worldgen"] as Dictionary)["worldgen_version"] = WorldGenConfig.CURRENT_VERSION + 1
	var file := FileAccess.open(_library_root + "/" + id + "/metadata.json", FileAccess.WRITE)
	if file == null:
		_expect(false, "could not write saved-world UI fixture %s" % id)
		return
	file.store_string(JSON.stringify(metadata, "\t"))


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("ui_flow_verify: %s" % message)
