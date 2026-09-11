class_name PauseMenu
extends CanvasLayer

signal resumed
signal setting_changed(key: String, value: Variant)
signal new_world_requested
signal quit_requested

@onready var _panel: PanelContainer = $Center/Panel
@onready var _resume_button: Button = $Center/Panel/Box/ResumeButton
@onready var _settings_button: Button = $Center/Panel/Box/SettingsButton
@onready var _new_world_button: Button = $Center/Panel/Box/NewWorldButton
@onready var _quit_button: Button = $Center/Panel/Box/QuitGameButton
@onready var _settings_panel: SettingsPanel = $SettingsPanel


func _ready() -> void:
	_panel.theme = UITheme.build()
	_resume_button.pressed.connect(close_menu)
	_settings_button.pressed.connect(func() -> void: _settings_panel.open_panel())
	_new_world_button.pressed.connect(func() -> void: new_world_requested.emit())
	_quit_button.pressed.connect(func() -> void: quit_requested.emit())
	_settings_panel.closed.connect(func() -> void: _resume_button.grab_focus())
	_settings_panel.setting_changed.connect(func(key: String, value: Variant) -> void: setting_changed.emit(key, value))


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		if _settings_panel.visible:
			_settings_panel.close_panel()
		else:
			close_menu()
		get_viewport().set_input_as_handled()


func open_menu() -> void:
	visible = true
	get_tree().paused = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_resume_button.grab_focus()


func close_menu() -> void:
	visible = false
	_settings_panel.visible = false
	get_tree().paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	resumed.emit()
