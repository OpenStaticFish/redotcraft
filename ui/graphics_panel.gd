class_name GraphicsPanel
extends Control

signal graphics_changed

const SECTIONS := [
	{"title": "LIGHTING", "rows": [
		{"type": "check", "key": "ssao_ssil", "label": "Ambient Occlusion / SSIL"},
		{"type": "check", "key": "ssr", "label": "Screen-Space Reflections"},
		{"type": "check", "key": "sdfgi", "label": "SDFGI (stutters with day/night)"},
	]},
	{"title": "SHADOWS", "rows": [
		{"type": "slider", "key": "shadow_max_distance", "label": "Shadow Distance", "min": 64.0, "max": 512.0, "step": 8.0, "format": "%d m"},
		{"type": "slider", "key": "shadow_opacity", "label": "Shadow Opacity", "min": 0.0, "max": 1.0, "step": 0.05, "format": "%.2f"},
		{"type": "slider", "key": "shadow_blur", "label": "Shadow Blur", "min": 0.0, "max": 4.0, "step": 0.1, "format": "%.1f"},
	]},
	{"title": "SKY & ATMOSPHERE", "rows": [
		{"type": "check", "key": "volumetric_fog", "label": "Volumetric Fog"},
		{"type": "slider", "key": "volumetric_fog_density", "label": "Volumetric Density", "min": 0.0, "max": 0.03, "step": 0.001, "format": "%.3f"},
		{"type": "slider", "key": "volumetric_fog_length", "label": "Volumetric Length", "min": 32.0, "max": 256.0, "step": 8.0, "format": "%d m"},
		{"type": "slider", "key": "fog_density", "label": "Distance Fog", "min": 0.0, "max": 0.003, "step": 0.0001, "format": "%.4f"},
	]},
	{"title": "POST-PROCESSING", "rows": [
		{"type": "option", "key": "tonemap", "label": "Tonemapper", "options": ["Linear", "Reinhardt", "Filmic", "ACES", "AgX"]},
		{"type": "slider", "key": "tonemap_exposure", "label": "Exposure", "min": 0.5, "max": 2.0, "step": 0.05, "format": "%.2f"},
		{"type": "slider", "key": "saturation", "label": "Saturation", "min": 0.5, "max": 2.0, "step": 0.05, "format": "%.2f"},
		{"type": "slider", "key": "contrast", "label": "Contrast", "min": 0.5, "max": 2.0, "step": 0.05, "format": "%.2f"},
		{"type": "slider", "key": "glow_intensity", "label": "Glow Intensity", "min": 0.0, "max": 1.0, "step": 0.05, "format": "%.2f"},
	]},
	{"title": "PERFORMANCE", "rows": [
		{"type": "option", "key": "msaa", "label": "MSAA", "options": ["Off", "2x", "4x", "8x"]},
		{"type": "slider", "key": "fsr_scale", "label": "Render Scale (FSR2)", "min": 0.5, "max": 1.0, "step": 0.01, "format": "%d%%", "display_scale": 100.0},
	]},
]

@onready var _rows: VBoxContainer = $Center/Panel/Box/Scroll/Rows
@onready var _status: Label = $Center/Panel/Box/Footer/StatusLabel
@onready var _reset_button: Button = $Center/Panel/Box/Footer/ResetButton
@onready var _back_button: Button = $Center/Panel/Box/Footer/BackButton


func _ready() -> void:
	_reset_button.pressed.connect(_on_reset)
	_back_button.pressed.connect(close_panel)
	_rebuild()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close_panel()
		get_viewport().set_input_as_handled()


func open_panel() -> void:
	visible = true
	_rebuild()
	_back_button.grab_focus()


func close_panel() -> void:
	visible = false


func _rebuild() -> void:
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	for section in SECTIONS:
		_rows.add_child(UITheme.muted_label(section["title"], 13))
		for row in section["rows"]:
			_add_row(row)
	_update_status()


func _add_row(row: Dictionary) -> void:
	match row["type"]:
		"check":
			var check := CheckBox.new()
			check.text = row["label"]
			check.button_pressed = bool(GameConfig.get_graphics()[row["key"]])
			check.toggled.connect(_on_value_changed.bind(row["key"]))
			_rows.add_child(check)
		"slider":
			var slider := UITheme.slider_row(
				_rows,
				row["label"],
				row["min"],
				row["max"],
				row["step"],
				float(GameConfig.get_graphics()[row["key"]]),
				row["format"],
				row.get("display_scale", 1.0))
			slider.value_changed.connect(_on_value_changed.bind(row["key"]))
		"option":
			_add_option_row(row)


func _add_option_row(row: Dictionary) -> void:
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	_rows.add_child(hbox)
	var label := Label.new()
	label.text = row["label"]
	label.custom_minimum_size = Vector2(200.0, 0.0)
	hbox.add_child(label)
	var option := OptionButton.new()
	for text in row["options"]:
		option.add_item(text)
	option.selected = clampi(int(GameConfig.get_graphics()[row["key"]]), 0, row["options"].size() - 1)
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(option)
	option.item_selected.connect(_on_value_changed.bind(row["key"]))


func _on_value_changed(value: Variant, key: String) -> void:
	GameConfig.set_graphics_value(key, value)
	_update_status()
	graphics_changed.emit()


func _on_reset() -> void:
	GameConfig.reset_graphics_to_preset()
	_rebuild()
	graphics_changed.emit()


func _update_status() -> void:
	var preset_name: String = GameConfig.PRESET_NAMES[GameConfig.get_graphics_preset()]
	if GameConfig.is_graphics_custom():
		_status.text = "Custom (base: %s)" % preset_name
	else:
		_status.text = "Preset: %s" % preset_name
