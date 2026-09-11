extends Control

const UI := preload("res://UITheme.gd")

var _settings_panel: Control
var _world_gen_panel: Control


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UI.build()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_build_background()
	_build_content()
	_build_panels()


func _build_background() -> void:
	var gradient := GradientTexture2D.new()
	gradient.gradient = Gradient.new()
	gradient.gradient.colors = PackedColorArray([
		Color(0.08, 0.2, 0.55),
		Color(0.29, 0.53, 1.0),
		Color(0.6, 0.78, 1.0),
		Color(0.83, 0.87, 0.8),
		Color(0.36, 0.52, 0.3),
	])
	gradient.gradient.offsets = PackedFloat32Array([0.0, 0.35, 0.58, 0.74, 1.0])
	gradient.fill_from = Vector2(0.0, 0.0)
	gradient.fill_to = Vector2(0.0, 1.0)
	var background := TextureRect.new()
	background.texture = gradient
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_SCALE
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	for index in 5:
		var cloud := ColorRect.new()
		cloud.color = Color(1.0, 1.0, 1.0, 0.85)
		cloud.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var width := 120.0 + float(index) * 46.0
		cloud.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		cloud.position = Vector2(60.0 + float(index) * 190.0, 70.0 + float(index % 3) * 58.0)
		cloud.size = Vector2(width, 26.0)
		add_child(cloud)


func _build_content() -> void:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 12)
	column.custom_minimum_size = Vector2(320.0, 0.0)
	center.add_child(column)

	var title := Label.new()
	title.text = "REDOTCRAFT"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 64)
	title.add_theme_color_override("font_color", Color.WHITE)
	title.add_theme_color_override("font_shadow_color", Color(0.02, 0.06, 0.12, 0.75))
	title.add_theme_constant_override("shadow_offset_x", 3)
	title.add_theme_constant_override("shadow_offset_y", 4)
	column.add_child(title)

	var subtitle := UI.muted_label("A VOXEL SANDBOX FOR REDOT", 15)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_color_override("font_color", Color(0.9, 0.96, 1.0, 0.92))
	column.add_child(subtitle)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0.0, 30.0)
	column.add_child(spacer)

	_add_menu_button(column, "Play", _on_play)
	_add_menu_button(column, "World Gen", _on_world_gen)
	_add_menu_button(column, "Settings", _on_settings)
	_add_menu_button(column, "Quit", _on_quit)

	var footer := UI.muted_label("Double-tap SPACE to fly in game  ·  ESC pauses", 14)
	footer.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.offset_top = -44.0
	footer.offset_bottom = -18.0
	add_child(footer)


func _add_menu_button(column: VBoxContainer, text: String, handler: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(320.0, 48.0)
	button.pressed.connect(handler)
	column.add_child(button)


func _build_panels() -> void:
	_settings_panel = load("res://SettingsPanel.gd").new()
	_settings_panel.visible = false
	add_child(_settings_panel)
	_settings_panel.closed.connect(_on_panel_closed)

	_world_gen_panel = load("res://WorldGenPanel.gd").new()
	_world_gen_panel.visible = false
	add_child(_world_gen_panel)
	_world_gen_panel.closed.connect(_on_panel_closed)
	_world_gen_panel.create_world.connect(_on_create_world)


func _on_panel_closed() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _on_play() -> void:
	GameConfig.randomize_world()
	GameConfig.world["world_type"] = 0
	GameConfig.world["terrain_scale"] = 1.0
	GameConfig.world["tree_density"] = 1.0
	_start_game()


func _on_world_gen() -> void:
	_world_gen_panel.open_panel()


func _on_settings() -> void:
	_settings_panel.open_panel()


func _on_create_world(config: Dictionary) -> void:
	GameConfig.world = config.duplicate()
	_start_game()


func _start_game() -> void:
	get_tree().change_scene_to_file("res://Main.tscn")


func _on_quit() -> void:
	get_tree().quit()
