class_name SurvivalUI
extends CanvasLayer

signal respawn_requested
signal menu_requested

var _vitals: Label
var _death: Control
var _cause: Label
var _respawn: Button
var _player: Player
var _previous_focus: Control


func setup(hud: Control, player: Player) -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 30
	_player = player
	var vitals_center := CenterContainer.new()
	hud.add_child(vitals_center)
	vitals_center.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	vitals_center.offset_top = 16
	vitals_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vitals = Label.new()
	_vitals.name = "Vitals"
	vitals_center.add_child(_vitals)
	_vitals.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_vitals.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vitals.add_theme_stylebox_override("normal", UITheme.chip_style())
	UITheme.apply_font_size(_vitals, 14)
	player.vitals_changed.connect(_update_vitals)
	_update_vitals()
	_death = Control.new()
	add_child(_death)
	_death.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	UITheme.apply(_death)
	var dim := ColorRect.new()
	dim.color = Color(UITheme.VOID, 0.85)
	_death.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	_death.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UITheme.modal_style())
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.custom_minimum_size.x = 300
	box.add_theme_constant_override("separation", 16)
	panel.add_child(box)
	var heading := Label.new()
	heading.text = "Expedition Ended"
	UITheme.style_heading(heading)
	box.add_child(heading)
	_cause = Label.new()
	box.add_child(_cause)
	_respawn = Button.new()
	_respawn.text = "Respawn"
	UITheme.style_button_primary(_respawn)
	box.add_child(_respawn)
	_respawn.pressed.connect(func() -> void: respawn_requested.emit())
	var menu := Button.new()
	menu.text = "Main Menu"
	UITheme.style_button_ghost(menu)
	box.add_child(menu)
	menu.pressed.connect(func() -> void: menu_requested.emit())
	_death.hide()


func _update_vitals() -> void:
	_vitals.visible = _player.game_mode == GameMode.SURVIVAL
	_vitals.text = "Health %d/20   Hunger %d/20   Air %d/10" % [ceili(_player.health), ceili(_player.hunger), ceili(_player.air)]


func show_death(cause: String) -> void:
	if _player.game_mode != GameMode.SURVIVAL:
		return
	_previous_focus = get_viewport().gui_get_focus_owner()
	_cause.text = cause.capitalize()
	_death.show()
	_respawn.grab_focus()


func hide_death() -> void:
	_death.hide()
	if is_instance_valid(_previous_focus) and _previous_focus.is_visible_in_tree():
		_previous_focus.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if _death.visible:
		if event.is_action_pressed("ui_cancel"):
			_respawn.grab_focus()
		get_viewport().set_input_as_handled()
