class_name ControlsPanel
extends SettingsCategoryPanel

## Controls category. Rows come from GameConfig's rebindable action table (one
## key button per action); clicking a button starts capture, the next key press
## becomes the binding, and Escape or a mouse click cancels. Bindings apply to
## the InputMap immediately and persist through GameConfig.settings.

@onready var _hint: Label = $Center/Panel/Box/RowsBox/Hint
@onready var _shared_label: Label = $Center/Panel/Box/SharedLabel
@onready var _reset_button: Button = $Center/Panel/Box/Footer/ResetButton

var _binding_buttons: Dictionary = {}
var _capture_action := ""
var _capture_button: Button


func _category_definition() -> Dictionary:
	return {"title": "Controls", "advanced": false, "rows": []}


func _style_static() -> void:
	super()
	_hint.add_theme_color_override("font_color", UITheme.MUTED)
	UITheme.apply_font_size(_hint, 13)
	_hint.text = "Click a key to rebind it. Press Esc while listening to cancel; a key may drive more than one action."
	UITheme.apply_font_size(_shared_label, 13)
	UITheme.style_button_ghost(_reset_button)
	_reset_button.pressed.connect(_on_reset)


func _build_rows() -> void:
	var current_group := ""
	for entry in GameConfig.rebindable_actions():
		if String(entry["group"]) != current_group:
			current_group = String(entry["group"])
			_rows_box.add_child(UITheme.eyebrow(current_group))
		_add_binding_row(entry)
	_update_shared_text()


func open_panel() -> void:
	_cancel_capture()
	_refresh_bindings()
	super()
	# The hint and shared-key label wrap text whose minimum height is unknown
	# until the panel has measured itself, so re-fit the scroll after layout.
	_resize_to_viewport.call_deferred()


func close_panel() -> void:
	_cancel_capture()
	super()


func _add_binding_row(entry: Dictionary) -> void:
	var action: String = entry["action"]
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	_rows_box.add_child(row)
	var name_label := Label.new()
	name_label.text = entry["label"]
	name_label.custom_minimum_size = Vector2(190.0, 0.0)
	name_label.add_theme_font_override("font", UITheme.font_semi())
	if String(entry["group"]) == "Debug":
		name_label.add_theme_color_override("font_color", UITheme.MUTED)
	row.add_child(name_label)
	var button := Button.new()
	button.text = GameConfig.input_key(action)
	button.tooltip_text = "Click, then press a key to rebind %s." % entry["label"]
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.style_button_flat(button)
	button.pressed.connect(_begin_capture.bind(action, button))
	row.add_child(button)
	if _first_focus == null:
		_first_focus = button
	_binding_buttons[action] = button


func _begin_capture(action: String, button: Button) -> void:
	_capture_action = action
	_capture_button = button
	button.text = "Press a key..."
	button.grab_focus()
	_hint.add_theme_color_override("font_color", UITheme.EMBER)
	_hint.text = "Listening for %s...  Esc cancels." % GameConfig.input_action_label(action)


func _finish_capture() -> void:
	_end_capture()
	_update_shared_text()


func _cancel_capture() -> void:
	if _capture_action.is_empty():
		return
	_end_capture()


func _end_capture() -> void:
	var action := _capture_action
	var button := _capture_button
	_capture_action = ""
	_capture_button = null
	_restore_hint()
	if button != null and is_instance_valid(button):
		button.text = GameConfig.input_key(action)


func _restore_hint() -> void:
	_hint.add_theme_color_override("font_color", UITheme.MUTED)
	_hint.text = "Click a key to rebind it. Press Esc while listening to cancel; a key may drive more than one action."


func _refresh_bindings() -> void:
	for action in _binding_buttons.keys():
		var button: Button = _binding_buttons[action]
		if is_instance_valid(button):
			button.text = GameConfig.input_key(action)
	_update_shared_text()


## Accepted keys are applied as-is (no conflict rejection) because the shipped
## defaults already share Space and Shift across walking/flying actions. The
## summary line keeps accidental sharing visible.
func _update_shared_text() -> void:
	var by_key: Dictionary = {}
	for entry in GameConfig.rebindable_actions():
		var keycode := GameConfig.get_input_binding(entry["action"])
		if keycode == 0:
			continue
		var labels: Array = by_key.get(keycode, [])
		labels.append(String(entry["label"]))
		by_key[keycode] = labels
	var parts: PackedStringArray = []
	for keycode in by_key.keys():
		var labels: Array = by_key[keycode]
		if labels.size() < 2:
			continue
		parts.append("%s — %s" % [GameConfig.key_label(keycode), ", ".join(PackedStringArray(labels))])
	_shared_label.text = "" if parts.is_empty() else "Shared keys:  %s" % "  ·  ".join(parts)


func _on_reset() -> void:
	GameConfig.reset_input_bindings()
	_refresh_bindings()


func _input(event: InputEvent) -> void:
	if _capture_action.is_empty() or not visible:
		return
	if event is InputEventKey:
		var key := event as InputEventKey
		if not key.pressed or key.echo:
			return
		get_viewport().set_input_as_handled()
		var keycode := key.physical_keycode if key.physical_keycode != 0 else key.keycode
		if keycode == KEY_ESCAPE or keycode == 0:
			_cancel_capture()
			return
		GameConfig.set_input_binding(_capture_action, keycode)
		_finish_capture()
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		get_viewport().set_input_as_handled()
		_cancel_capture()
