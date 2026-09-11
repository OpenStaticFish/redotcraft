extends Control

const UI := preload("res://UITheme.gd")

signal closed
signal setting_changed(key: String, value: Variant)

var _value_labels: Dictionary = {}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = UI.build()

	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.0, 0.02, 0.03, 0.62)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(560.0, 0.0)
	center.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)
	box.add_child(UI.heading("SETTINGS", 30))

	_add_slider(box, "Render Distance", "render_distance", 4.0, 16.0, 1.0, "%d chunks")
	_add_slider(box, "Field of View", "fov", 60.0, 100.0, 1.0, "%d")
	_add_slider(box, "Mouse Sensitivity", "mouse_sensitivity", 0.0005, 0.005, 0.0001, "%.4f")
	_add_check(box, "Fullscreen", "fullscreen")

	var graphics := UI.muted_label("GRAPHICS", 14)
	box.add_child(graphics)
	_add_check(box, "Ambient Occlusion", "ambient_occlusion")
	_add_check(box, "Global Illumination (SDFGI)", "global_illumination")

	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_END
	footer.add_theme_constant_override("separation", 10)
	box.add_child(footer)
	var done := Button.new()
	done.text = "Done"
	done.custom_minimum_size = Vector2(150.0, 0.0)
	done.pressed.connect(close_panel)
	footer.add_child(done)

	visible = false


func open_panel() -> void:
	visible = true
	for key in _value_labels.keys():
		_refresh_label(key)
	var focus := _find_first_button()
	if focus:
		focus.grab_focus()


func close_panel() -> void:
	GameConfig.save_settings()
	visible = false
	closed.emit()


func _find_first_button() -> Button:
	for child in find_children("*", "Button", true, false):
		return child
	return null


func _add_slider(box: VBoxContainer, label_text: String, key: String, minimum: float, maximum: float, step: float, format: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)

	var name_label := Label.new()
	name_label.text = label_text
	name_label.custom_minimum_size = Vector2(200.0, 0.0)
	row.add_child(name_label)

	var slider := HSlider.new()
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = step
	slider.value = float(GameConfig.settings[key])
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size = Vector2(220.0, 0.0)
	row.add_child(slider)

	var value_label := Label.new()
	value_label.custom_minimum_size = Vector2(90.0, 0.0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.add_theme_color_override("font_color", UI.TEAL)
	row.add_child(value_label)
	_value_labels[key] = [value_label, format, slider]

	slider.value_changed.connect(func(value: float) -> void:
		GameConfig.settings[key] = value
		_refresh_label(key)
		setting_changed.emit(key, value)
	)


func _add_check(box: VBoxContainer, label_text: String, key: String) -> void:
	var check := CheckBox.new()
	check.text = label_text
	check.button_pressed = bool(GameConfig.settings[key])
	check.toggled.connect(func(pressed: bool) -> void:
		GameConfig.settings[key] = pressed
		GameConfig.apply_window_mode()
		setting_changed.emit(key, pressed)
	)
	box.add_child(check)


func _refresh_label(key: String) -> void:
	if not _value_labels.has(key):
		return
	var entry: Array = _value_labels[key]
	var slider: HSlider = entry[2]
	var value: float = slider.value
	if key == "render_distance" or key == "fov":
		(entry[0] as Label).text = str(roundi(value))
	else:
		(entry[0] as Label).text = "%.4f" % value
