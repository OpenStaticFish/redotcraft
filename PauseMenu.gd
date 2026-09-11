extends CanvasLayer

const UI := preload("res://UITheme.gd")

signal resumed
signal setting_changed(key: String, value: Variant)
signal new_world_requested
signal quit_requested

var _settings_panel: Control
var _resume_button: Button


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false

	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.0, 0.02, 0.03, 0.6)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.theme = UI.build()
	panel.custom_minimum_size = Vector2(420.0, 0.0)
	center.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	box.add_child(UI.heading("PAUSED", 32))

	_resume_button = _add_button(box, "Resume", close_menu)
	_add_button(box, "Settings", func() -> void: _settings_panel.open_panel())
	_add_button(box, "New World", func() -> void: new_world_requested.emit())
	_add_button(box, "Quit Game", func() -> void: quit_requested.emit())

	var hint := UI.muted_label("WASD move   SPACE jump   double-tap SPACE to fly\nSHIFT sprint / descend   LMB mine   RMB place\n1-9 / 0 or wheel select block", 13)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(hint)

	_settings_panel = load("res://SettingsPanel.gd").new()
	_settings_panel.visible = false
	add_child(_settings_panel)
	_settings_panel.closed.connect(func() -> void: _resume_button.grab_focus())
	_settings_panel.setting_changed.connect(func(key: String, value: Variant) -> void: setting_changed.emit(key, value))


func _add_button(box: VBoxContainer, text: String, handler: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0.0, 44.0)
	button.pressed.connect(handler)
	box.add_child(button)
	return button


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
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
