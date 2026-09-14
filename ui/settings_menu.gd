class_name SettingsMenu
extends Control

## Settings hub. Presents one button per category submenu and owns cancel
## routing for the nested stack (advanced screen -> category -> hub), so each
## layer closes in order and restores focus to whatever opened it.

signal closed
signal setting_changed(key: String, value: Variant)

@onready var _panel: PanelContainer = $Center/Panel
@onready var _heading: Label = $Center/Panel/Box/Heading
@onready var _rows_box: VBoxContainer = $Center/Panel/Box/RowsBox
@onready var _done_button: Button = $Center/Panel/Box/Footer/DoneButton
@onready var _dim: ColorRect = $Dim
@onready var _graphics_panel: GraphicsPanel = $GraphicsPanel

var _buttons: Dictionary = {}
var _advanced_return: SettingsCategoryPanel


func _ready() -> void:
	UITheme.apply(self)
	_style_static()
	for child in get_children():
		if child is SettingsCategoryPanel:
			var panel: SettingsCategoryPanel = child
			var button := Button.new()
			button.text = panel.category_title()
			_rows_box.add_child(button)
			UITheme.style_button_ghost(button)
			_buttons[panel] = button
			button.pressed.connect(_open_category.bind(panel))
			panel.closed.connect(func() -> void: _restore_focus(panel))
			panel.advanced_requested.connect(func() -> void: _open_advanced(panel))
			panel.setting_changed.connect(func(key: String, value: Variant) -> void: setting_changed.emit(key, value))
	_graphics_panel.graphics_changed.connect(func() -> void: setting_changed.emit("graphics", null))
	_graphics_panel.closed.connect(_on_advanced_closed)
	_done_button.pressed.connect(close_panel)


func _style_static() -> void:
	_dim.color = Color(UITheme.VOID.r, UITheme.VOID.g, UITheme.VOID.b, 0.68)
	_panel.add_theme_stylebox_override("panel", UITheme.modal_style())
	_heading.text = "Settings"
	_heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	UITheme.style_heading(_heading)
	var box := _heading.get_parent() as VBoxContainer
	var eyebrow := UITheme.eyebrow("Configuration")
	box.add_child(eyebrow)
	box.move_child(eyebrow, 0)
	var divider := UITheme.divider()
	box.add_child(divider)
	box.move_child(divider, 2)
	UITheme.style_button_primary(_done_button)


func _unhandled_input(event: InputEvent) -> void:
	if not visible or not event.is_action_pressed("ui_cancel"):
		return
	get_viewport().set_input_as_handled()
	if _graphics_panel.visible:
		if not _graphics_panel.close_section():
			_graphics_panel.close_panel()
		return
	for child in get_children():
		if child is SettingsCategoryPanel and (child as SettingsCategoryPanel).visible:
			(child as SettingsCategoryPanel).close_panel()
			return
	close_panel()


func open_panel() -> void:
	_panel.custom_minimum_size.x = minf(560.0, get_viewport().get_visible_rect().size.x - 48.0)
	# The hub can be hidden directly (pause menu) while a submenu was open, so
	# always reset the stack before showing the category list.
	_graphics_panel.visible = false
	for child in get_children():
		if child is SettingsCategoryPanel:
			(child as SettingsCategoryPanel).visible = false
	visible = true
	Motion.dim_in(_dim)
	Motion.pop_in(_panel)
	if not _buttons.is_empty():
		(_buttons.values()[0] as Button).grab_focus()


func close_panel() -> void:
	if not visible:
		return
	_graphics_panel.visible = false
	for child in get_children():
		if child is SettingsCategoryPanel:
			(child as SettingsCategoryPanel).visible = false
	visible = false
	closed.emit()


func _open_category(panel: SettingsCategoryPanel) -> void:
	panel.open_panel()


func _restore_focus(panel: SettingsCategoryPanel) -> void:
	var button: Button = _buttons.get(panel)
	if button != null:
		button.grab_focus()


func _open_advanced(panel: SettingsCategoryPanel) -> void:
	_graphics_panel.open_panel()
	_advanced_return = panel


func _on_advanced_closed() -> void:
	if _advanced_return != null:
		_advanced_return.focus_advanced()
		_advanced_return = null
