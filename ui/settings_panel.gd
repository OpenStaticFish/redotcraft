class_name SettingsPanel
extends Control

signal closed
signal setting_changed(key: String, value: Variant)

const SLIDERS := [
	{"label": "Render Distance", "key": "render_distance", "minimum": 4.0, "maximum": 32.0, "step": 1.0, "format": "%d chunks"},
	{"label": "Field of View", "key": "fov", "minimum": 60.0, "maximum": 100.0, "step": 1.0, "format": "%d"},
	{"label": "Mouse Sensitivity", "key": "mouse_sensitivity", "minimum": 0.0005, "maximum": 0.005, "step": 0.0001, "format": "%.2fx", "display_scale": 1000.0},
]
const VOLUME_SLIDERS := [
	{"label": "Master Volume", "key": "master_volume", "minimum": 0.0, "maximum": 1.0, "step": 0.05, "format": "%d%%", "display_scale": 100.0},
	{"label": "Sound Effects", "key": "sfx_volume", "minimum": 0.0, "maximum": 1.0, "step": 0.05, "format": "%d%%", "display_scale": 100.0},
	{"label": "Ambience", "key": "ambient_volume", "minimum": 0.0, "maximum": 1.0, "step": 0.05, "format": "%d%%", "display_scale": 100.0},
]
const RENDER_DISTANCE_MAX := 32.0
const RENDER_DISTANCE_EXTREME_MAX := 100.0
const EXTREME_WARNING := "Warning: extreme render distance can take minutes to load and use several GB of memory."

@onready var _panel: PanelContainer = $Center/Panel
@onready var _heading: Label = $Center/Panel/Box/Heading
@onready var _rows_box: VBoxContainer = $Center/Panel/Box/RowsBox
@onready var _done_button: Button = $Center/Panel/Box/Footer/DoneButton
@onready var _advanced_button: Button = $Center/Panel/Box/Footer/AdvancedButton
@onready var _graphics_panel: GraphicsPanel = $GraphicsPanel
@onready var _dim: ColorRect = $Dim

var _render_distance_slider: HSlider
var _extreme_toggle: CheckBox
var _extreme_warning: Label


func _ready() -> void:
	theme = UITheme.build()
	_style_static()
	for entry in SLIDERS:
		if entry["key"] == "render_distance":
			_add_section("GAMEPLAY")
			_add_render_distance_row(entry)
		elif entry["key"] == "fov":
			_add_slider(entry)
		else:
			_add_slider(entry)
	_add_section("DISPLAY")
	_add_check("Fullscreen", "fullscreen", true)
	_add_section("GRAPHICS")
	_add_option("Graphics Preset", "graphics_preset", GameConfig.PRESET_NAMES)
	_add_section("SOUND")
	for entry in VOLUME_SLIDERS:
		_add_slider(entry)
	_done_button.pressed.connect(close_panel)
	_advanced_button.pressed.connect(func() -> void: _graphics_panel.open_panel())
	_graphics_panel.graphics_changed.connect(func() -> void: setting_changed.emit("graphics", null))
	_graphics_panel.closed.connect(func() -> void: _advanced_button.grab_focus())


func _style_static() -> void:
	_dim.color = Color(UITheme.VOID.r, UITheme.VOID.g, UITheme.VOID.b, 0.68)
	_panel.add_theme_stylebox_override("panel", UITheme.modal_style())
	_heading.text = "Settings"
	_heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_heading.add_theme_font_override("font", UITheme.font_display())
	_heading.add_theme_font_size_override("font_size", UITheme.SIZE_DISPLAY)
	_heading.add_theme_color_override("font_color", UITheme.INK)
	var eyebrow := UITheme.eyebrow("Configuration")
	var box := _heading.get_parent() as VBoxContainer
	box.add_child(eyebrow)
	box.move_child(eyebrow, 0)
	var divider := UITheme.divider()
	box.add_child(divider)
	box.move_child(divider, 2)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 4)
	box.add_child(spacer)
	box.move_child(spacer, 3)
	UITheme.style_button_ghost(_advanced_button)
	UITheme.style_button_primary(_done_button)
	_advanced_button.text = "Advanced Graphics"


func _add_section(title: String) -> void:
	if not _rows_box.get_children().is_empty():
		_rows_box.add_child(UITheme.divider())
		var spacer := Control.new()
		spacer.custom_minimum_size = Vector2(0, 6)
		_rows_box.add_child(spacer)
	_rows_box.add_child(UITheme.eyebrow(title))


func _add_render_distance_row(entry: Dictionary) -> void:
	var extreme := bool(GameConfig.get_setting("extreme_render_distance"))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	_rows_box.add_child(row)

	var name_label := Label.new()
	name_label.text = entry["label"]
	name_label.custom_minimum_size = Vector2(160.0, 0.0)
	name_label.add_theme_font_override("font", UITheme.font_semi())
	row.add_child(name_label)

	_render_distance_slider = HSlider.new()
	_render_distance_slider.min_value = entry["minimum"]
	_render_distance_slider.max_value = RENDER_DISTANCE_EXTREME_MAX if extreme else RENDER_DISTANCE_MAX
	_render_distance_slider.step = entry["step"]
	_render_distance_slider.value = clampf(float(GameConfig.get_setting(entry["key"])), entry["minimum"], _render_distance_slider.max_value)
	_render_distance_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_render_distance_slider.custom_minimum_size = Vector2(120.0, 0.0)
	_render_distance_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_render_distance_slider)

	var value_label := UITheme.value_label()
	value_label.custom_minimum_size = Vector2(72.0, 0.0)
	value_label.text = entry["format"] % roundi(_render_distance_slider.value)
	row.add_child(value_label)

	_extreme_toggle = CheckBox.new()
	_extreme_toggle.text = "Extreme"
	_extreme_toggle.tooltip_text = "Allow render distance up to 100 chunks."
	_extreme_toggle.button_pressed = extreme
	row.add_child(_extreme_toggle)

	_extreme_warning = UITheme.muted_label(EXTREME_WARNING, 13)
	_extreme_warning.add_theme_color_override("font_color", UITheme.WARN)
	_extreme_warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_extreme_warning.visible = extreme
	_rows_box.add_child(_extreme_warning)

	_render_distance_slider.value_changed.connect(func(value: float) -> void:
		value_label.text = entry["format"] % roundi(value)
		GameConfig.set_setting(entry["key"], value)
		setting_changed.emit(entry["key"], value)
	)
	_extreme_toggle.toggled.connect(func(pressed: bool) -> void:
		GameConfig.set_setting("extreme_render_distance", pressed)
		_render_distance_slider.max_value = RENDER_DISTANCE_EXTREME_MAX if pressed else RENDER_DISTANCE_MAX
		if not pressed and _render_distance_slider.value > RENDER_DISTANCE_MAX:
			_render_distance_slider.value = RENDER_DISTANCE_MAX
		_extreme_warning.visible = pressed
	)


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		if _graphics_panel.visible:
			_graphics_panel.close_panel()
		else:
			close_panel()
		get_viewport().set_input_as_handled()


func open_panel() -> void:
	_panel.custom_minimum_size.x = minf(640.0, get_viewport().get_visible_rect().size.x - 48.0)
	visible = true
	Motion.dim_in(_dim)
	Motion.pop_in(_panel)
	_render_distance_slider.grab_focus()


func close_panel() -> void:
	if not visible:
		return
	GameConfig.save_settings()
	visible = false
	closed.emit()


func _add_slider(entry: Dictionary) -> void:
	var key: String = entry["key"]
	var slider := UITheme.slider_row(
		_rows_box,
		entry["label"],
		entry["minimum"],
		entry["maximum"],
		entry["step"],
		float(GameConfig.get_setting(key)),
		entry["format"],
		entry.get("display_scale", 1.0))
	slider.value_changed.connect(func(value: float) -> void:
		GameConfig.set_setting(key, value)
		if key.ends_with("_volume"):
			AudioManager.apply_volumes()
		setting_changed.emit(key, value)
	)


func _add_check(label_text: String, key: String, applies_window_mode: bool) -> void:
	var check := CheckBox.new()
	check.text = label_text
	check.button_pressed = bool(GameConfig.get_setting(key))
	check.toggled.connect(func(pressed: bool) -> void:
		GameConfig.set_setting(key, pressed)
		if applies_window_mode:
			GameConfig.apply_window_mode()
		setting_changed.emit(key, pressed)
	)
	_rows_box.add_child(check)


func _add_option(label_text: String, key: String, options: Array) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	_rows_box.add_child(row)
	var name_label := Label.new()
	name_label.text = label_text
	name_label.custom_minimum_size = Vector2(160.0, 0.0)
	name_label.add_theme_font_override("font", UITheme.font_semi())
	row.add_child(name_label)
	var option := OptionButton.new()
	for text in options:
		option.add_item(text)
	option.selected = clampi(int(GameConfig.get_setting(key)), 0, options.size() - 1)
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(option)
	option.item_selected.connect(func(index: int) -> void:
		GameConfig.set_setting(key, index)
		setting_changed.emit(key, index)
	)
