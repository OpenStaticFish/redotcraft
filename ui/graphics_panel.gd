class_name GraphicsPanel
extends Control

## Advanced Graphics hub: one button per fine-tune section. Each section opens
## its own GraphicsSectionPanel, and cancel closes the section before the hub.

signal graphics_changed
signal closed

@onready var _panel: PanelContainer = $Center/Panel
@onready var _heading: Label = $Center/Panel/Box/Heading
@onready var _hint: Label = $Center/Panel/Box/Hint
@onready var _rows: VBoxContainer = $Center/Panel/Box/Scroll/Rows
@onready var _status: Label = $Center/Panel/Box/Footer/StatusLabel
@onready var _reset_button: Button = $Center/Panel/Box/Footer/ResetButton
@onready var _back_button: Button = $Center/Panel/Box/Footer/BackButton
@onready var _dim: ColorRect = $Dim

var _buttons: Dictionary = {}
var _open_section: GraphicsSectionPanel = null


func _ready() -> void:
	_style_static()
	_reset_button.pressed.connect(_on_reset)
	_back_button.pressed.connect(close_panel)
	for child in get_children():
		if child is GraphicsSectionPanel:
			var section: GraphicsSectionPanel = child
			var button := Button.new()
			button.text = section.section_title.capitalize()
			_rows.add_child(button)
			UITheme.style_button_ghost(button)
			_buttons[section] = button
			button.pressed.connect(_open_section_panel.bind(section))
			section.closed.connect(func() -> void: _restore_focus(section))
			section.graphics_changed.connect(_on_section_changed)


func _style_static() -> void:
	_dim.color = Color(UITheme.VOID.r, UITheme.VOID.g, UITheme.VOID.b, 0.74)
	_panel.add_theme_stylebox_override("panel", UITheme.modal_style())
	_heading.text = "Advanced Graphics"
	_heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	UITheme.style_heading(_heading)
	var box := _heading.get_parent() as VBoxContainer
	var eyebrow := UITheme.eyebrow("Fine-Tune")
	box.add_child(eyebrow)
	box.move_child(eyebrow, 0)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_hint.add_theme_color_override("font_color", UITheme.MUTED)
	UITheme.apply_font_size(_hint, 14)
	_hint.text = "Fine-tune the active preset. Any change switches it to Custom."
	var divider := UITheme.divider()
	box.add_child(divider)
	box.move_child(divider, 3)
	_status.add_theme_font_override("font", UITheme.font_semi())
	_status.add_theme_color_override("font_color", UITheme.CYAN)
	UITheme.apply_font_size(_status, 14)
	_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	UITheme.style_button_ghost(_reset_button)
	UITheme.style_button_primary(_back_button)


func _unhandled_input(event: InputEvent) -> void:
	if not visible or not event.is_action_pressed("ui_cancel"):
		return
	get_viewport().set_input_as_handled()
	if _open_section != null and _open_section.visible:
		_open_section.close_panel()
		return
	close_panel()


func open_panel() -> void:
	_panel.custom_minimum_size.x = minf(620.0, get_viewport().get_visible_rect().size.x - 48.0)
	for child in get_children():
		if child is GraphicsSectionPanel:
			(child as GraphicsSectionPanel).visible = false
	_open_section = null
	_update_status()
	visible = true
	Motion.dim_in(_dim)
	Motion.pop_in(_panel)
	if not _buttons.is_empty():
		(_buttons.values()[0] as Button).grab_focus()


func close_panel() -> void:
	if not visible:
		return
	for child in get_children():
		if child is GraphicsSectionPanel:
			(child as GraphicsSectionPanel).visible = false
	_open_section = null
	visible = false
	closed.emit()


## Returns true when a nested section was open and got closed; the settings hub
## uses this so cancel unwinds one layer at a time.
func close_section() -> bool:
	for child in get_children():
		if child is GraphicsSectionPanel and (child as GraphicsSectionPanel).visible:
			(child as GraphicsSectionPanel).close_panel()
			return true
	return false


func _open_section_panel(section: GraphicsSectionPanel) -> void:
	_open_section = section
	section.open_panel()


func _restore_focus(section: GraphicsSectionPanel) -> void:
	var button: Button = _buttons.get(section)
	if button != null:
		button.grab_focus()
	if _open_section == section:
		_open_section = null


func _on_section_changed() -> void:
	_update_status()
	graphics_changed.emit()


func _on_reset() -> void:
	GameConfig.reset_graphics_to_preset()
	if _open_section != null and _open_section.visible:
		_open_section.refresh()
	_update_status()
	graphics_changed.emit()


func _update_status() -> void:
	var preset_name: String = GameConfig.PRESET_NAMES[GameConfig.get_graphics_preset()]
	if GameConfig.is_graphics_custom():
		_status.text = "Custom (base: %s)" % preset_name
	else:
		_status.text = "Preset: %s" % preset_name
