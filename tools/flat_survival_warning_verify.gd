## Run with --headless --path . --script res://tools/flat_survival_warning_verify.gd
extends SceneTree

var _failures := PackedStringArray()


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var panel = load("res://ui/play_panel.tscn").instantiate()
	root.add_child(panel)
	var config: Node = root.get_node("GameConfig")
	var previous_type: int = config.world["world_type"]
	config.world["world_type"] = WorldGenConfig.WORLD_TYPE_FLAT
	panel._show_view(panel.View.CREATE)
	_expect("resource-limited" in panel._mode_hint.text, "initial Flat Survival warning missing")
	_expect("no trees or ores" in panel._mode_hint.text, "warning must explain missing resources")
	for mode in [GameMode.CREATIVE, GameMode.SURVIVAL]:
		panel._mode_option.select(panel._mode_option.get_item_index(mode))
		panel._mode_option.item_selected.emit(panel._mode_option.selected)
		_expect(("resource-limited" in panel._mode_hint.text) == (mode == GameMode.SURVIVAL),
			"warning did not follow mode selection")
		for world_type in [WorldGenConfig.WORLD_TYPE_NORMAL, WorldGenConfig.WORLD_TYPE_AMPLIFIED,
				WorldGenConfig.WORLD_TYPE_FLAT]:
			panel._type_option.select(world_type)
			panel._type_option.item_selected.emit(world_type)
			_expect(("resource-limited" in panel._mode_hint.text) ==
				(mode == GameMode.SURVIVAL and world_type == WorldGenConfig.WORLD_TYPE_FLAT),
				"warning did not follow type selection")
	config.world["world_type"] = previous_type
	panel.queue_free()
	await process_frame
	for failure in _failures:
		push_error(failure)
	print("FLAT SURVIVAL WARNING VERIFY: ", "PASS" if _failures.is_empty() else "FAIL")
	quit(0 if _failures.is_empty() else 1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
