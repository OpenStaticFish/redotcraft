class_name SettingsCategoryPanel
extends Control

## One settings submenu (Display, Sound, Gameplay, Graphics). Rows are declared
## per category and composed here; the SettingsMenu hub owns cancel routing and
## opens the nested advanced screen when a category supports one.

signal closed
signal advanced_requested
signal setting_changed(key: String, value: Variant)

@export var category: String = "display"

const RENDER_DISTANCE_MAX := 32.0
const RENDER_DISTANCE_EXTREME_MAX := 100.0
const EXTREME_WARNING := "Warning: extreme render distance can take minutes to load and use several GB of memory."

@onready var _panel: PanelContainer = $Center/Panel
@onready var _heading: Label = $Center/Panel/Box/Heading
@onready var _rows_box: VBoxContainer = find_child("RowsBox", true, false) as VBoxContainer
@onready var _advanced_button: Button = $Center/Panel/Box/Footer/AdvancedButton
@onready var _back_button: Button = $Center/Panel/Box/Footer/BackButton
@onready var _dim: ColorRect = $Dim

var _first_focus: Control


func _ready() -> void:
	theme = UITheme.build()
	_style_static()
	_build_rows()
	_advanced_button.pressed.connect(func() -> void: advanced_requested.emit())
	_back_button.pressed.connect(close_panel)


func open_panel() -> void:
	_panel.custom_minimum_size.x = minf(560.0, get_viewport().get_visible_rect().size.x - 48.0)
	visible = true
	Motion.dim_in(_dim)
	Motion.pop_in(_panel)
	if _first_focus != null:
		_first_focus.grab_focus()


func close_panel() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


func category_title() -> String:
	return String(_category_definition()["title"])


func focus_advanced() -> void:
	if visible:
		_advanced_button.grab_focus()


func _category_definition() -> Dictionary:
	match category:
		"graphics":
			return {
				"title": "Graphics",
				"advanced": true,
				"rows": [
					{"type": "option", "label": "Graphics Preset", "key": "graphics_preset", "options": GameConfig.PRESET_NAMES},
				],
			}
		"sound":
			return {
				"title": "Sound",
				"advanced": false,
				"rows": [
					{"type": "slider", "label": "Master Volume", "key": "master_volume", "min": 0.0, "max": 1.0, "step": 0.05, "format": "%d%%", "scale": 100.0},
					{"type": "slider", "label": "Sound Effects", "key": "sfx_volume", "min": 0.0, "max": 1.0, "step": 0.05, "format": "%d%%", "scale": 100.0},
					{"type": "slider", "label": "Ambience", "key": "ambient_volume", "min": 0.0, "max": 1.0, "step": 0.05, "format": "%d%%", "scale": 100.0},
				],
			}
		"gameplay":
			return {
				"title": "Gameplay",
				"advanced": false,
				"rows": [
					{"type": "slider", "label": "Mouse Sensitivity", "key": "mouse_sensitivity", "min": 0.0005, "max": 0.005, "step": 0.0001, "format": "%.2fx", "scale": 1000.0},
				],
			}
		_:
			return {
				"title": "Display",
				"advanced": false,
				"rows": [
					{"type": "render_distance", "label": "Render Distance", "key": "render_distance", "min": 4.0, "max": RENDER_DISTANCE_MAX, "step": 1.0, "format": "%d chunks"},
					{"type": "slider", "label": "Field of View", "key": "fov", "min": 60.0, "max": 100.0, "step": 1.0, "format": "%d"},
					{"type": "check", "label": "Fullscreen", "key": "fullscreen", "window": true},
					{"type": "option", "label": "V-Sync", "key": "vsync", "options": GameConfig.VSYNC_NAMES, "tooltip": "Synchronizes presented frames with the display."},
					{"type": "option", "label": "FPS Cap", "key": "fps_cap", "options": GameConfig.FPS_CAP_NAMES, "values": GameConfig.FPS_CAP_VALUES, "tooltip": "Unlimited lets the renderer run as fast as it can."},
					{"type": "check", "label": "Dynamic Resolution", "key": "dynamic_resolution", "tooltip": "Lowers the 3D render scale when the frame rate drops below the target, then raises it back when there is headroom."},
					{"type": "option", "label": "Dynamic Target", "key": "dynamic_resolution_target", "options": GameConfig.DYNAMIC_RESOLUTION_TARGET_NAMES, "values": GameConfig.DYNAMIC_RESOLUTION_TARGET_VALUES, "depends_on": "dynamic_resolution", "tooltip": "Frame-rate goal for dynamic resolution."},
				],
			}


func _style_static() -> void:
	var definition := _category_definition()
	_dim.color = Color(UITheme.VOID.r, UITheme.VOID.g, UITheme.VOID.b, 0.68)
	_panel.add_theme_stylebox_override("panel", UITheme.modal_style())
	_heading.text = definition["title"]
	_heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_heading.add_theme_font_override("font", UITheme.font_display())
	_heading.add_theme_font_size_override("font_size", UITheme.SIZE_DISPLAY)
	_heading.add_theme_color_override("font_color", UITheme.INK)
	var box := _heading.get_parent() as VBoxContainer
	var eyebrow := UITheme.eyebrow("Settings")
	box.add_child(eyebrow)
	box.move_child(eyebrow, 0)
	_advanced_button.text = "Advanced..."
	_advanced_button.visible = bool(definition["advanced"])
	UITheme.style_button_ghost(_advanced_button)
	UITheme.style_button_ghost(_back_button)


func _build_rows() -> void:
	var controls := {}
	for entry in _category_definition()["rows"]:
		var control: Control = null
		match String(entry["type"]):
			"render_distance":
				control = _add_render_distance(entry)
			"slider":
				control = _add_slider(entry)
			"check":
				control = _add_check(entry)
			"option":
				control = _add_option(entry)
		if control != null:
			controls[entry["key"]] = control
	# Rows tagged `depends_on` (the dynamic-resolution target) only show while
	# the controlling checkbox is on.
	for entry in _category_definition()["rows"]:
		if not entry.has("depends_on"):
			continue
		var target := controls.get(entry["key"]) as Control
		var source := controls.get(entry["depends_on"]) as CheckBox
		if target == null or source == null:
			continue
		target.visible = bool(GameConfig.get_setting(entry["depends_on"]))
		source.toggled.connect(func(pressed: bool) -> void: target.visible = pressed)


func _add_slider(entry: Dictionary) -> Control:
	var key: String = entry["key"]
	var slider := UITheme.slider_row(
		_rows_box,
		entry["label"],
		entry["min"],
		entry["max"],
		entry["step"],
		float(GameConfig.get_setting(key)),
		entry["format"],
		entry.get("scale", 1.0))
	if _first_focus == null:
		_first_focus = slider
	slider.value_changed.connect(func(value: float) -> void:
		GameConfig.set_setting(key, value)
		if key.ends_with("_volume"):
			AudioManager.apply_volumes()
		setting_changed.emit(key, value)
	)
	return slider.get_parent() as Control


func _add_check(entry: Dictionary) -> Control:
	var key: String = entry["key"]
	var check := CheckBox.new()
	check.text = entry["label"]
	check.button_pressed = bool(GameConfig.get_setting(key))
	if entry.has("tooltip"):
		check.tooltip_text = entry["tooltip"]
	if _first_focus == null:
		_first_focus = check
	check.toggled.connect(func(pressed: bool) -> void:
		GameConfig.set_setting(key, pressed)
		if bool(entry.get("window", false)):
			GameConfig.apply_window_mode()
		setting_changed.emit(key, pressed)
	)
	_rows_box.add_child(check)
	return check


func _add_option(entry: Dictionary) -> Control:
	var key: String = entry["key"]
	var values: Array = entry.get("values", [])
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	_rows_box.add_child(row)
	var name_label := Label.new()
	name_label.text = entry["label"]
	name_label.custom_minimum_size = Vector2(160.0, 0.0)
	name_label.add_theme_font_override("font", UITheme.font_semi())
	if entry.has("tooltip"):
		name_label.tooltip_text = entry["tooltip"]
	row.add_child(name_label)
	var option := OptionButton.new()
	var options: Array = entry["options"]
	for text in options:
		option.add_item(text)
	option.selected = clampi(_option_index(values, GameConfig.get_setting(key)), 0, options.size() - 1)
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if entry.has("tooltip"):
		option.tooltip_text = entry["tooltip"]
	row.add_child(option)
	if _first_focus == null:
		_first_focus = option
	option.item_selected.connect(func(index: int) -> void:
		var value: Variant = values[index] if not values.is_empty() else index
		GameConfig.set_setting(key, value)
		setting_changed.emit(key, value)
	)
	return row


## Option rows without a value table store the option index directly; rows with
## one (FPS cap, dynamic target) store the mapped engine value.
func _option_index(values: Array, current: Variant) -> int:
	if values.is_empty():
		return maxi(int(current), 0)
	return maxi(values.find(current), 0)


## Extreme distances get their own toggle and warning, same as the old combined
## settings screen.
func _add_render_distance(entry: Dictionary) -> Control:
	var key: String = entry["key"]
	var extreme := bool(GameConfig.get_setting("extreme_render_distance"))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	_rows_box.add_child(row)
	var name_label := Label.new()
	name_label.text = entry["label"]
	name_label.custom_minimum_size = Vector2(160.0, 0.0)
	name_label.add_theme_font_override("font", UITheme.font_semi())
	row.add_child(name_label)
	var slider := HSlider.new()
	slider.min_value = entry["min"]
	slider.max_value = RENDER_DISTANCE_EXTREME_MAX if extreme else RENDER_DISTANCE_MAX
	slider.step = entry["step"]
	slider.value = clampf(float(GameConfig.get_setting(key)), entry["min"], slider.max_value)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(slider)
	var value_label := UITheme.value_label()
	value_label.custom_minimum_size = Vector2(72.0, 0.0)
	value_label.text = entry["format"] % roundi(slider.value)
	row.add_child(value_label)
	var toggle := CheckBox.new()
	toggle.text = "Extreme"
	toggle.tooltip_text = "Allow render distance up to 100 chunks."
	toggle.button_pressed = extreme
	row.add_child(toggle)
	var warning := UITheme.muted_label(EXTREME_WARNING, 13)
	warning.add_theme_color_override("font_color", UITheme.WARN)
	warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	warning.visible = extreme
	_rows_box.add_child(warning)
	if _first_focus == null:
		_first_focus = slider
	slider.value_changed.connect(func(value: float) -> void:
		value_label.text = entry["format"] % roundi(value)
		GameConfig.set_setting(key, value)
		setting_changed.emit(key, value)
	)
	toggle.toggled.connect(func(pressed: bool) -> void:
		GameConfig.set_setting("extreme_render_distance", pressed)
		slider.max_value = RENDER_DISTANCE_EXTREME_MAX if pressed else RENDER_DISTANCE_MAX
		if not pressed and slider.value > RENDER_DISTANCE_MAX:
			slider.value = RENDER_DISTANCE_MAX
		warning.visible = pressed
	)
	return row
