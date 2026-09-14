class_name PauseMenu
extends CanvasLayer

signal resumed
signal setting_changed(key: String, value: Variant)
signal settings_closed
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
	UITheme.apply(_panel)
	_style_static()
	_resume_button.pressed.connect(close_menu)
	_settings_button.pressed.connect(func() -> void: _settings_menu.open_panel())
	_new_world_button.pressed.connect(func() -> void: new_world_requested.emit())
	_quit_button.pressed.connect(func() -> void: quit_requested.emit())
	_settings_menu.closed.connect(func() -> void:
		_settings_button.grab_focus()
		settings_closed.emit()
	)
	_settings_menu.setting_changed.connect(func(key: String, value: Variant) -> void: setting_changed.emit(key, value))


func _style_static() -> void:
	_dim.color = Color(UITheme.VOID.r, UITheme.VOID.g, UITheme.VOID.b, 0.66)
	_panel.add_theme_stylebox_override("panel", UITheme.modal_style())
	_heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	UITheme.style_heading(_heading)
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
	UITheme.apply_font_size(_hint, 13)
	_refresh_hint()


## Control hints follow the active bindings, so a remap in Settings is visible
## the next time the menu opens.
func _refresh_hint() -> void:
	var jump_key := GameConfig.input_key("jump")
	var sprint_key := GameConfig.input_key("sprint")
	var descend_key := GameConfig.input_key("fly_down")
	var vertical := (
		"%s sprint / descend" % sprint_key
		if sprint_key == descend_key
		else "%s sprint   %s descend" % [sprint_key, descend_key]
	)
	_hint.text = "%s move   %s jump   double-tap %s to fly\n%s   %s fast fly   LMB mine   RMB place\n1-9 / 0 or wheel select block   %s inventory   %s map   %s minimap   %s map mode\n%s hide HUD   %s screenshot   %s photo camera   %s worldgen map   ESC pause" % [
		GameConfig.input_move_hint(),
		jump_key,
		jump_key,
		vertical,
		GameConfig.input_key("fly_boost"),
		GameConfig.input_key("inventory"),
		GameConfig.input_key("map_overlay"),
		GameConfig.input_key("minimap"),
		GameConfig.input_key("minimap_mode"),
		GameConfig.input_key("hud_toggle"),
		GameConfig.input_key("screenshot"),
		GameConfig.input_key("photo_camera"),
		GameConfig.input_key("debug_worldgen"),
	]


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
	_refresh_hint()
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
