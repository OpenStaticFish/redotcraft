class_name SettingsPanel
extends Control

signal closed
signal setting_changed(key: String, value: Variant)

const SLIDERS := [
	{"label": "Render Distance", "key": "render_distance", "minimum": 4.0, "maximum": 32.0, "step": 1.0, "format": "%d chunks"},
	{"label": "Field of View", "key": "fov", "minimum": 60.0, "maximum": 100.0, "step": 1.0, "format": "%d"},
	{"label": "Mouse Sensitivity", "key": "mouse_sensitivity", "minimum": 0.0005, "maximum": 0.005, "step": 0.0001, "format": "%.4f"},
]

@onready var _rows_box: VBoxContainer = $Center/Panel/Box/RowsBox
@onready var _done_button: Button = $Center/Panel/Box/Footer/DoneButton
@onready var _advanced_button: Button = $Center/Panel/Box/Footer/AdvancedButton
@onready var _graphics_panel: GraphicsPanel = $GraphicsPanel


func _ready() -> void:
	theme = UITheme.build()
	for entry in SLIDERS:
		_add_slider(entry)
	_add_check("Fullscreen", "fullscreen", true)
	_rows_box.add_child(UITheme.muted_label("GRAPHICS", 14))
	_add_option("Graphics Preset", "graphics_preset", GameConfig.PRESET_NAMES)
	_done_button.pressed.connect(close_panel)
	_advanced_button.pressed.connect(func() -> void: _graphics_panel.open_panel())
	_graphics_panel.graphics_changed.connect(func() -> void: setting_changed.emit("graphics", null))


func open_panel() -> void:
	visible = true
	_done_button.grab_focus()


func close_panel() -> void:
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
		entry["format"])
	slider.value_changed.connect(func(value: float) -> void:
		GameConfig.set_setting(key, value)
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
	row.add_theme_constant_override("separation", 12)
	_rows_box.add_child(row)
	var name_label := Label.new()
	name_label.text = label_text
	name_label.custom_minimum_size = Vector2(200.0, 0.0)
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
