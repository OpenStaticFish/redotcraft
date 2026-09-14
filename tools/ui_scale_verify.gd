## Headless check for the interface scale settings: key defaults, option
## tables, the window content-scale application, the UITheme text multiplier
## and its live refresh, and the Display panel rows.
## Run:
##   redot --headless --path . --script res://tools/ui_scale_verify.gd
##
## Nodes stay untyped and scenes are loaded at runtime: a --script SceneTree
## parses before autoloads exist, so naming UI classes at parse time fails.
extends SceneTree

var _failures := 0
var _signal_count := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var config: Node = root.get_node_or_null("GameConfig")
	if config == null:
		push_error("ui_scale_verify: GameConfig autoload is missing")
		quit(1)
		return

	_check_defaults(config)
	_check_option_snapping(config)
	_check_window_application(config)
	_check_signal(config)
	_check_theme_scaling(config)
	await _check_live_refresh(config)
	await _check_display_panel(config)

	config.set_setting("text_scale", 1.0)
	config.set_setting("ui_scale", 1.0)

	if _failures == 0:
		print("UI SCALE VERIFY: PASS")
		quit(0)
		return
	print("UI SCALE VERIFY: FAIL (%d)" % _failures)
	quit(1)


func _check_defaults(config: Node) -> void:
	var defaults: Dictionary = config.DEFAULT_SETTINGS
	for key in ["ui_scale", "text_scale"]:
		_expect(defaults.has(key), "DEFAULT_SETTINGS is missing %s" % key)
	_expect(is_equal_approx(float(defaults["ui_scale"]), 1.0), "ui_scale should default to 100%")
	_expect(is_equal_approx(float(defaults["text_scale"]), 1.0), "text_scale should default to 100%")
	_expect((config.UI_SCALE_VALUES as Array).size() == (config.UI_SCALE_NAMES as Array).size(), "UI scale tables diverged")
	_expect((config.TEXT_SCALE_VALUES as Array).size() == (config.TEXT_SCALE_NAMES as Array).size(), "text scale tables diverged")
	_expect(float(config.UI_SCALE_VALUES[0]) > 0.0, "UI scale lower bound must stay positive")


func _check_option_snapping(config: Node) -> void:
	_expect(is_equal_approx(float(config.nearest_option(1.3, config.UI_SCALE_VALUES)), 1.25), "1.3 UI scale should snap to 125%")
	_expect(is_equal_approx(float(config.nearest_option(9.0, config.UI_SCALE_VALUES)), 2.0), "an oversized UI scale should snap to the highest option")
	_expect(is_equal_approx(float(config.nearest_option(0.1, config.TEXT_SCALE_VALUES)), 0.85), "a tiny text scale should snap to the lowest option")


func _check_window_application(config: Node) -> void:
	for value in config.UI_SCALE_VALUES:
		config.set_setting("ui_scale", value)
		_expect(is_equal_approx(root.content_scale_factor, float(value)), "ui_scale %s did not reach the window content scale" % value)
		_expect(is_equal_approx(float(config.get_ui_scale()), float(value)), "get_ui_scale should report the stored option")
	config.set_setting("ui_scale", 1.0)
	_expect(is_equal_approx(root.content_scale_factor, 1.0), "resetting the UI scale should restore 100%")


func _check_signal(config: Node) -> void:
	_signal_count = 0
	config.interface_scale_changed.connect(_on_scale_changed)
	config.set_setting("text_scale", 1.15)
	_expect(_signal_count == 1, "set_setting should emit interface_scale_changed")
	config.interface_scale_changed.disconnect(_on_scale_changed)
	config.set_setting("text_scale", 1.0)


func _on_scale_changed() -> void:
	_signal_count += 1


func _check_theme_scaling(config: Node) -> void:
	config.set_setting("text_scale", 1.0)
	var base := UITheme.build()
	_expect(base.default_font_size == UITheme.font_size(UITheme.SIZE_BODY), "theme body size should follow the text multiplier")
	_expect(UITheme.font_size(20) == 20, "a 100% text scale should keep base font sizes")

	config.set_setting("text_scale", 1.3)
	var scaled := UITheme.build()
	_expect(scaled != base, "changing the text scale should rebuild the shared theme")
	_expect(scaled.default_font_size == roundi(float(UITheme.SIZE_BODY) * 1.3), "the rebuilt theme should scale the body size")
	_expect(UITheme.font_size(20) == 26, "a 130% text scale should scale font sizes")
	config.set_setting("text_scale", 1.0)
	var restored := UITheme.build()
	_expect(restored.default_font_size == UITheme.font_size(UITheme.SIZE_BODY), "returning to 100% should rebuild a theme with the base sizes")
	_expect(UITheme.font_size(20) == 20, "a restored 100% text scale should keep base font sizes")
	_expect(UITheme.build() == restored, "the same text scale should reuse the cached theme")


func _check_live_refresh(config: Node) -> void:
	config.set_setting("text_scale", 1.0)
	var menu: Node = load("res://ui/main_menu.tscn").instantiate()
	root.add_child(menu)
	await process_frame

	var probe := Label.new()
	UITheme.apply_font_size(probe, 20)
	menu.add_child(probe)
	_expect(probe.get_theme_font_size("font_size") == 20, "a fresh font size should start at its base size")

	config.set_setting("text_scale", 1.3)
	await process_frame
	_expect(probe.get_theme_font_size("font_size") == 26, "a live text-size change should re-scale tagged font sizes")
	_expect(menu.theme.default_font_size == roundi(float(UITheme.SIZE_BODY) * 1.3), "a live text-size change should rebuild the screen theme")
	var play_button := menu.get_node("Center/Column/PlayButton") as Button
	_expect(play_button.get_theme_font_size("font_size") == roundi(float(UITheme.SIZE_BODY) * 1.3), "theme-driven button text should follow the rebuilt theme")

	menu.queue_free()
	await process_frame
	config.set_setting("text_scale", 1.0)
	await process_frame


func _check_display_panel(config: Node) -> void:
	config.set_setting("ui_scale", 1.0)
	config.set_setting("text_scale", 1.0)
	var menu: Node = load("res://ui/main_menu.tscn").instantiate()
	root.add_child(menu)
	await process_frame
	menu._on_settings()
	var display: Node = menu.get_node("SettingsMenu/DisplayCategory")
	display.open_panel()
	await process_frame

	var ui_option := _find_option(display, "UI Scale")
	var text_option := _find_option(display, "Text Size")
	_expect(ui_option != null and ui_option.item_count == (config.UI_SCALE_NAMES as Array).size(), "Display is missing the UI Scale row")
	_expect(text_option != null and text_option.item_count == (config.TEXT_SCALE_NAMES as Array).size(), "Display is missing the Text Size row")
	var scroll := display.find_child("OptionsScroll", true, false)
	_expect(scroll is ScrollContainer, "the Display rows should stay scrollable at large scales")
	_expect(scroll != null and scroll.find_child("RowsBox", true, false) != null, "Display rows should sit inside the scroll container")
	if ui_option != null:
		_expect(ui_option.selected == 1, "UI Scale should start on 100%")
		ui_option.item_selected.emit(3)
		_expect(is_equal_approx(float(config.get_setting("ui_scale")), 1.5), "selecting 150% should store the mapped UI scale")
		_expect(is_equal_approx(root.content_scale_factor, 1.5), "selecting 150% should resize the window content scale")
		# A live change moves the logical viewport under the open panel; its
		# rows must re-fit instead of clipping the heading and footer.
		ui_option.item_selected.emit(4)
		await process_frame
		await process_frame
		var panel := display.get_node("Center/Panel") as Control
		var viewport_rect := Rect2(Vector2.ZERO, root.get_visible_rect().size)
		_expect(viewport_rect.encloses(panel.get_global_rect()), "the Display panel should stay inside the viewport after a live 200% change")
	if text_option != null:
		text_option.item_selected.emit(2)
		_expect(is_equal_approx(float(config.get_setting("text_scale")), 1.15), "selecting Large should store the mapped text scale")

	menu.queue_free()
	await process_frame


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


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("ui_scale_verify: %s" % message)
