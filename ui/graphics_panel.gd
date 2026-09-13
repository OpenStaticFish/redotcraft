class_name GraphicsPanel
extends Control

signal graphics_changed
signal closed

const SECTIONS := [
	{"title": "LIGHTING", "rows": [
		{"type": "check", "key": "ssao_ssil", "label": "Ambient Occlusion / SSIL"},
		{"type": "check", "key": "ssr", "label": "Screen-Space Reflections"},
		{"type": "check", "key": "sdfgi", "label": "SDFGI", "tooltip": "Stutters while the day/night cycle moves the sun."},
	]},
	{"title": "SHADOWS", "rows": [
		{"type": "check", "key": "soft_shadows", "label": "Soft Shadows", "tooltip": "Shadow edges vibrate without TAA or FSR2."},
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
		{"type": "check", "key": "taa", "label": "Temporal AA (TAA)"},
		{"type": "slider", "key": "fsr_scale", "label": "Render Scale", "tooltip": "Below 100% uses FSR2 upscaling.", "min": 0.5, "max": 1.0, "step": 0.01, "format": "%d%%", "display_scale": 100.0},
	]},
]

@onready var _panel: PanelContainer = $Center/Panel
@onready var _heading: Label = $Center/Panel/Box/Heading
@onready var _hint: Label = $Center/Panel/Box/Hint
@onready var _rows: VBoxContainer = $Center/Panel/Box/Scroll/Rows
@onready var _status: Label = $Center/Panel/Box/Footer/StatusLabel
@onready var _reset_button: Button = $Center/Panel/Box/Footer/ResetButton
@onready var _back_button: Button = $Center/Panel/Box/Footer/BackButton
@onready var _dim: ColorRect = $Dim

var _first_control: Control


func _ready() -> void:
	_style_static()
	_reset_button.pressed.connect(_on_reset)
	_back_button.pressed.connect(close_panel)
	_rebuild()


func _style_static() -> void:
	_dim.color = Color(UITheme.VOID.r, UITheme.VOID.g, UITheme.VOID.b, 0.74)
	_panel.add_theme_stylebox_override("panel", UITheme.modal_style())
	_heading.text = "Advanced Graphics"
	_heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_heading.add_theme_font_override("font", UITheme.font_display())
	_heading.add_theme_font_size_override("font_size", UITheme.SIZE_DISPLAY)
	_heading.add_theme_color_override("font_color", UITheme.INK)
	var box := _heading.get_parent() as VBoxContainer
	var eyebrow := UITheme.eyebrow("Fine-Tune")
	box.add_child(eyebrow)
	box.move_child(eyebrow, 0)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_hint.add_theme_color_override("font_color", UITheme.MUTED)
	_hint.add_theme_font_size_override("font_size", 14)
	_hint.text = "Fine-tune the active preset. Any change switches it to Custom."
	var divider := UITheme.divider()
	box.add_child(divider)
	box.move_child(divider, 3)
	_status.add_theme_font_override("font", UITheme.font_semi())
	_status.add_theme_font_size_override("font_size", 14)
	_status.add_theme_color_override("font_color", UITheme.CYAN)
	_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	UITheme.style_button_ghost(_reset_button)
	UITheme.style_button_primary(_back_button)


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close_panel()
		get_viewport().set_input_as_handled()


func open_panel() -> void:
	_panel.custom_minimum_size.x = minf(760.0, get_viewport().get_visible_rect().size.x - 48.0)
	visible = true
	_rebuild()
	Motion.dim_in(_dim)
	Motion.pop_in(_panel)
	if _first_control != null:
		_first_control.grab_focus()


func close_panel() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


func _rebuild() -> void:
	_first_control = null
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	for section in SECTIONS:
		if not _rows.get_children().is_empty():
			var spacer := Control.new()
			spacer.custom_minimum_size = Vector2(0, 8)
			_rows.add_child(spacer)
			_rows.add_child(UITheme.divider())
			var after := Control.new()
			after.custom_minimum_size = Vector2(0, 8)
			_rows.add_child(after)
		_rows.add_child(UITheme.eyebrow(section["title"]))
		for row in section["rows"]:
			_add_row(row)
	_update_status()


func _add_row(row: Dictionary) -> void:
	match row["type"]:
		"check":
			var check := CheckBox.new()
			check.text = row["label"]
			if row.has("tooltip"):
				check.tooltip_text = row["tooltip"]
			check.button_pressed = bool(GameConfig.get_graphics()[row["key"]])
			check.toggled.connect(_on_value_changed.bind(row["key"]))
			_rows.add_child(check)
			if _first_control == null:
				_first_control = check
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
			if row.has("tooltip"):
				(slider.get_parent() as Control).tooltip_text = row["tooltip"]
			slider.value_changed.connect(_on_value_changed.bind(row["key"]))
			if _first_control == null:
				_first_control = slider
		"option":
			_add_option_row(row)


func _add_option_row(row: Dictionary) -> void:
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 14)
	_rows.add_child(hbox)
	var label := Label.new()
	label.text = row["label"]
	label.custom_minimum_size = Vector2(160.0, 0.0)
	label.add_theme_font_override("font", UITheme.font_semi())
	hbox.add_child(label)
	var option := OptionButton.new()
	for text in row["options"]:
		option.add_item(text)
	option.selected = clampi(int(GameConfig.get_graphics()[row["key"]]), 0, row["options"].size() - 1)
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(option)
	option.item_selected.connect(_on_value_changed.bind(row["key"]))
	if _first_control == null:
		_first_control = option


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
