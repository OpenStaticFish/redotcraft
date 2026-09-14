class_name GraphicsSectionPanel
extends Control

## One Advanced Graphics section (Lighting, Shadows, ...). Rows come from the
## shared GraphicsSections table; the Advanced hub owns the section list and
## restores focus to the button that opened it.

signal closed
signal graphics_changed

@export var section_title: String = "LIGHTING"

@onready var _panel: PanelContainer = $Center/Panel
@onready var _heading: Label = $Center/Panel/Box/Heading
@onready var _rows: VBoxContainer = $Center/Panel/Box/Scroll/Rows
@onready var _back_button: Button = $Center/Panel/Box/Footer/BackButton
@onready var _dim: ColorRect = $Dim

var _first_control: Control


func _ready() -> void:
	UITheme.apply(self)
	_style_static()
	_back_button.pressed.connect(close_panel)
	_rebuild()


func open_panel() -> void:
	_panel.custom_minimum_size.x = minf(680.0, get_viewport().get_visible_rect().size.x - 48.0)
	_rebuild()
	visible = true
	Motion.dim_in(_dim)
	Motion.pop_in(_panel)
	if _first_control != null:
		_first_control.grab_focus()


func close_panel() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


func refresh() -> void:
	if visible:
		_rebuild()


func _style_static() -> void:
	_dim.color = Color(UITheme.VOID.r, UITheme.VOID.g, UITheme.VOID.b, 0.74)
	_panel.add_theme_stylebox_override("panel", UITheme.modal_style())
	_heading.text = section_title.capitalize()
	_heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	UITheme.style_heading(_heading)
	var box := _heading.get_parent() as VBoxContainer
	var eyebrow := UITheme.eyebrow("Advanced Graphics")
	box.add_child(eyebrow)
	box.move_child(eyebrow, 0)
	UITheme.style_button_ghost(_back_button)


func _rebuild() -> void:
	_first_control = null
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	for row in GraphicsSections.rows_for(section_title):
		_add_row(row)


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
	graphics_changed.emit()
