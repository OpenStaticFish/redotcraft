class_name PauseMenu
extends CanvasLayer

signal resumed
signal setting_changed(key: String, value: Variant)
signal new_world_requested
signal quit_requested

@onready var _panel: PanelContainer = $Center/Panel
@onready var _heading: Label = $Center/Panel/Box/Heading
@onready var _resume_button: Button = $Center/Panel/Box/ResumeButton
@onready var _settings_button: Button = $Center/Panel/Box/SettingsButton
@onready var _new_world_button: Button = $Center/Panel/Box/NewWorldButton
@onready var _quit_button: Button = $Center/Panel/Box/QuitGameButton
@onready var _hint: Label = $Center/Panel/Box/Hint
@onready var _dim: ColorRect = $Dim
@onready var _settings_menu: SettingsMenu = $SettingsMenu


func _ready() -> void:
	_panel.theme = UITheme.build()
	_style_static()
	_resume_button.pressed.connect(close_menu)
	_settings_button.pressed.connect(func() -> void: _settings_menu.open_panel())
	_new_world_button.pressed.connect(func() -> void: new_world_requested.emit())
	_quit_button.pressed.connect(func() -> void: quit_requested.emit())
	_settings_menu.closed.connect(func() -> void: _settings_button.grab_focus())
	_settings_menu.setting_changed.connect(func(key: String, value: Variant) -> void: setting_changed.emit(key, value))


func _style_static() -> void:
	_dim.color = Color(UITheme.VOID.r, UITheme.VOID.g, UITheme.VOID.b, 0.66)
	_panel.add_theme_stylebox_override("panel", UITheme.modal_style())
	_heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_heading.add_theme_font_override("font", UITheme.font_display())
	_heading.add_theme_font_size_override("font_size", UITheme.SIZE_DISPLAY)
	_heading.add_theme_color_override("font_color", UITheme.INK)
	var box := _heading.get_parent() as VBoxContainer
	var eyebrow := UITheme.eyebrow("Expedition Halted")
	box.add_child(eyebrow)
	box.move_child(eyebrow, 0)
	var divider := UITheme.divider()
	box.add_child(divider)
	box.move_child(divider, box.get_child_count() - 2)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 4)
	box.add_child(spacer)
	box.move_child(spacer, box.get_child_count() - 2)
	UITheme.style_button_primary(_resume_button)
	UITheme.style_button_ghost(_settings_button)
	UITheme.style_button_ghost(_new_world_button)
	UITheme.style_button_ghost(_quit_button)
	_hint.add_theme_color_override("font_color", UITheme.MUTED)
	_hint.add_theme_font_size_override("font_size", 13)


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		if _settings_menu.visible:
			_settings_menu.close_panel()
		else:
			close_menu()
		get_viewport().set_input_as_handled()


func open_menu() -> void:
	visible = true
	get_tree().paused = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	Motion.dim_in(_dim)
	Motion.pop_in(_panel)
	_resume_button.grab_focus()


func close_menu() -> void:
	visible = false
	_settings_menu.visible = false
	get_tree().paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	resumed.emit()
