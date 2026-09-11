extends Node3D

const UI := preload("res://UITheme.gd")

@onready var world = $World
@onready var player = $Player

const HOTBAR: Array[int] = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
const INITIAL_INVENTORY := {1: 64, 2: 64, 3: 64, 4: 64, 5: 32, 6: 32, 7: 32, 8: 32, 9: 16, 10: 32}
const CLOUD_FIELD_PATH := "res://CloudField.gd"
const PAUSE_MENU_PATH := "res://PauseMenu.gd"

var hud: CanvasLayer
var hud_root: Control
var coords_label: Label
var stats_label: Label
var status_label: Label
var underwater_overlay: ColorRect
var slot_panels: Array[PanelContainer] = []
var slot_labels: Array[Label] = []
var selected_slot := 0
var status_time := 6.0
var last_coords := Vector3i(999999, 999999, 999999)
var inventory: Dictionary = INITIAL_INVENTORY.duplicate()
var _cloud_field: Node3D
var _pause_menu: CanvasLayer
var _environment: Environment
var _stats_time := 0.0


func _ready() -> void:
	_setup_environment()
	_setup_clouds()
	_build_hud()
	_build_pause_menu()
	_apply_game_config()
	var spawn: Vector3 = world.get_spawn_position()
	player.global_position = spawn
	player.spawn_position = spawn
	world.setup_player(player)
	player.setup_world(world, self)
	player.set_selected_block(HOTBAR[selected_slot])
	_update_inventory_display()
	set_status("WASD move   double-tap SPACE to fly   ESC pause")


func _exit_tree() -> void:
	get_tree().paused = false


func _process(delta: float) -> void:
	status_time -= delta
	if status_time <= 0.0 and status_label:
		status_label.text = ""
	if underwater_overlay and player:
		underwater_overlay.visible = world.is_water_at(player.camera.global_position)
	_stats_time -= delta
	if _stats_time <= 0.0:
		_stats_time = 0.25
		_update_stats()


func _apply_game_config() -> void:
	var render_distance := int(GameConfig.settings["render_distance"])
	world.world_seed = int(GameConfig.world["seed"])
	world.world_type = int(GameConfig.world["world_type"])
	world.terrain_scale = float(GameConfig.world["terrain_scale"])
	world.tree_density = float(GameConfig.world["tree_density"])
	world.render_distance = render_distance
	world.unload_radius = render_distance + 2
	world.apply_world_config()
	if player.camera:
		player.camera.far = maxf(500.0, float(render_distance) * 16.0 * 1.6 + 160.0)
	player.apply_settings()


func _setup_environment() -> void:
	var environment_node := WorldEnvironment.new()
	environment_node.name = "WorldEnvironment"
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.29, 0.53, 1.0)
	sky_material.sky_horizon_color = Color(0.6, 0.78, 1.0)
	sky_material.sky_curve = 0.1
	sky_material.sky_energy_multiplier = 1.0
	sky_material.ground_bottom_color = Color(0.35, 0.52, 0.82)
	sky_material.ground_horizon_color = Color(0.55, 0.72, 0.95)
	sky_material.ground_curve = 0.05
	sky_material.sun_angle_max = 2.5
	sky_material.sun_curve = 0.02
	sky.sky_material = sky_material
	environment.sky = sky
	environment.background_energy_multiplier = 1.0
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.72, 0.85, 0.97)
	environment.ambient_light_energy = 0.4
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	environment.tonemap_exposure = 0.95
	environment.tonemap_white = 4.0
	environment.fog_enabled = true
	environment.fog_light_color = Color(0.66, 0.8, 0.98)
	environment.fog_light_energy = 1.0
	environment.fog_density = 0.0009
	environment.fog_aerial_perspective = 1.0
	environment.fog_sky_affect = 0.25
	environment.fog_height = 44.0
	environment.fog_height_density = 0.0

	var ambient_occlusion := bool(GameConfig.settings.get("ambient_occlusion", true))
	environment.ssao_enabled = ambient_occlusion
	environment.ssao_radius = 0.9
	environment.ssao_intensity = 0.9
	environment.ssao_power = 1.2
	environment.ssao_detail = 0.2
	environment.ssil_enabled = ambient_occlusion
	environment.ssil_intensity = 0.4
	environment.ssil_radius = 2.5

	environment.sdfgi_enabled = bool(GameConfig.settings.get("global_illumination", true))
	environment.sdfgi_cascades = 3
	environment.sdfgi_min_cell_size = 0.5
	environment.sdfgi_bounce_feedback = 0.55
	environment.sdfgi_use_occlusion = false
	environment.sdfgi_read_sky_light = true

	environment.glow_enabled = true
	environment.glow_intensity = 0.35
	environment.glow_bloom = 0.05
	environment.glow_hdr_threshold = 1.15
	environment.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT

	_environment = environment
	environment_node.environment = environment
	add_child(environment_node)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-50.0, -35.0, 0.0)
	sun.light_color = Color(1.0, 0.96, 0.86)
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	sun.shadow_bias = 0.015
	sun.shadow_normal_bias = 1.0
	sun.light_angular_distance = 0.8
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_blend_splits = true
	sun.directional_shadow_max_distance = 240.0
	sun.shadow_opacity = 0.9
	sun.shadow_blur = 1.0
	add_child(sun)

	var fill := DirectionalLight3D.new()
	fill.name = "SkyFill"
	fill.rotation_degrees = Vector3(42.0, 145.0, 0.0)
	fill.light_color = Color(0.62, 0.76, 1.0)
	fill.light_energy = 0.12
	fill.shadow_enabled = false
	add_child(fill)


func _setup_clouds() -> void:
	var script := load(CLOUD_FIELD_PATH) as Script
	if not script:
		return
	_cloud_field = Node3D.new()
	_cloud_field.name = "Clouds"
	_cloud_field.set_script(script)
	add_child(_cloud_field)


func _build_pause_menu() -> void:
	_pause_menu = load(PAUSE_MENU_PATH).new()
	add_child(_pause_menu)
	_pause_menu.setting_changed.connect(_on_setting_changed)
	_pause_menu.new_world_requested.connect(_on_new_world)
	_pause_menu.quit_requested.connect(_on_quit_game)


func _build_hud() -> void:
	hud = CanvasLayer.new()
	hud.name = "HUD"
	hud.layer = 10
	hud.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(hud)

	hud_root = Control.new()
	hud_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_root.theme = UI.build()
	hud.add_child(hud_root)

	underwater_overlay = ColorRect.new()
	underwater_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	underwater_overlay.color = Color(0.08, 0.3, 0.65, 0.42)
	underwater_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	underwater_overlay.visible = false
	hud_root.add_child(underwater_overlay)

	var crosshair := Label.new()
	crosshair.text = "+"
	crosshair.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	crosshair.offset_left = -18.0
	crosshair.offset_top = -22.0
	crosshair.offset_right = 18.0
	crosshair.offset_bottom = 22.0
	crosshair.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	crosshair.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	crosshair.add_theme_font_size_override("font_size", 30)
	crosshair.add_theme_color_override("font_color", Color("#fff9dc"))
	crosshair.add_theme_color_override("font_shadow_color", Color(0.02, 0.04, 0.05, 0.9))
	crosshair.add_theme_constant_override("shadow_offset_x", 2)
	crosshair.add_theme_constant_override("shadow_offset_y", 2)
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_root.add_child(crosshair)

	var coords_panel := PanelContainer.new()
	coords_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	coords_panel.position = Vector2(16.0, 16.0)
	coords_panel.custom_minimum_size = Vector2(230.0, 62.0)
	coords_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_root.add_child(coords_panel)

	coords_label = Label.new()
	coords_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	coords_label.add_theme_font_size_override("font_size", 15)
	coords_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	coords_panel.add_child(coords_label)

	var stats_panel := PanelContainer.new()
	stats_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	stats_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	stats_panel.position = Vector2(0.0, 0.0)
	stats_panel.offset_left = -252.0
	stats_panel.offset_top = 16.0
	stats_panel.offset_right = -16.0
	stats_panel.offset_bottom = 78.0
	stats_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_root.add_child(stats_panel)

	stats_label = Label.new()
	stats_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	stats_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	stats_label.add_theme_font_size_override("font_size", 15)
	stats_label.add_theme_color_override("font_color", UI.MUTED)
	stats_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stats_panel.add_child(stats_label)

	status_label = Label.new()
	status_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	status_label.offset_left = -420.0
	status_label.offset_top = -152.0
	status_label.offset_right = 420.0
	status_label.offset_bottom = -122.0
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.add_theme_font_size_override("font_size", 16)
	status_label.add_theme_color_override("font_color", UI.INK)
	status_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	status_label.add_theme_constant_override("shadow_offset_x", 2)
	status_label.add_theme_constant_override("shadow_offset_y", 2)
	status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_root.add_child(status_label)

	var hotbar_width := HOTBAR.size() * 92.0 + (HOTBAR.size() - 1) * 6.0 + 18.0
	var hotbar := Panel.new()
	hotbar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	hotbar.offset_left = -hotbar_width * 0.5
	hotbar.offset_top = -104.0
	hotbar.offset_right = hotbar_width * 0.5
	hotbar.offset_bottom = -22.0
	hotbar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hotbar.add_theme_stylebox_override("panel", UI.panel_style(UI.PANEL, UI.BORDER, 1, 10))
	hud_root.add_child(hotbar)

	var row := HBoxContainer.new()
	row.position = Vector2(9.0, 9.0)
	row.size = Vector2(hotbar_width - 18.0, 64.0)
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hotbar.add_child(row)

	for index in HOTBAR.size():
		var slot := PanelContainer.new()
		slot.custom_minimum_size = Vector2(92.0, 64.0)
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(slot)
		slot_panels.append(slot)
		var label := Label.new()
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 12)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(label)
		slot_labels.append(label)

	_update_slot_styles()


func _update_slot_styles() -> void:
	for index in slot_panels.size():
		var selected := index == selected_slot
		var style := UI.panel_style(
			Color(0.16, 0.3, 0.3, 0.96) if selected else Color(0.06, 0.11, 0.13, 0.92),
			UI.TEAL if selected else Color(0.45, 0.65, 0.64, 0.3),
			2 if selected else 1,
			6)
		style.content_margin_left = 6.0
		style.content_margin_right = 6.0
		style.content_margin_top = 6.0
		style.content_margin_bottom = 6.0
		slot_panels[index].add_theme_stylebox_override("panel", style)
		slot_labels[index].add_theme_color_override("font_color", Color.WHITE if selected else UI.INK)


func activate_pause() -> void:
	if _pause_menu:
		_pause_menu.open_menu()


func _on_setting_changed(key: String, value: Variant) -> void:
	match key:
		"render_distance":
			world.render_distance = int(value)
			world.unload_radius = int(value) + 2
			world._rebuild_desired()
			if player.camera:
				player.camera.far = maxf(500.0, float(value) * 16.0 * 1.6 + 160.0)
		"fov":
			player.set_fov(float(value))
		"ambient_occlusion":
			if _environment:
				_environment.ssao_enabled = bool(value)
				_environment.ssil_enabled = bool(value)
		"global_illumination":
			if _environment:
				_environment.sdfgi_enabled = bool(value)


func _on_new_world() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://MainMenu.tscn")


func _on_quit_game() -> void:
	get_tree().quit()


func select_slot(index: int) -> void:
	selected_slot = clampi(index, 0, HOTBAR.size() - 1)
	_update_slot_styles()
	if player:
		player.set_selected_block(HOTBAR[selected_slot])
	set_status("Selected %s (%d)" % [world.get_block_name(HOTBAR[selected_slot]), inventory.get(HOTBAR[selected_slot], 0)])


func can_place_selected() -> bool:
	return inventory.get(HOTBAR[selected_slot], 0) > 0


func collect_block(block_id: int) -> void:
	inventory[block_id] = inventory.get(block_id, 0) + 1
	_update_inventory_display()


func consume_selected_block() -> void:
	var block_id: int = HOTBAR[selected_slot]
	inventory[block_id] = maxi(inventory.get(block_id, 0) - 1, 0)
	_update_inventory_display()


func _update_inventory_display() -> void:
	for index in slot_labels.size():
		var block_id: int = HOTBAR[index]
		var key_label := str(index + 1) if index < 9 else "0"
		slot_labels[index].text = "%s  %s\n   x%d" % [key_label, world.get_block_name(block_id), inventory.get(block_id, 0)]


func set_status(message: String) -> void:
	if status_label:
		status_label.text = message
		status_time = 3.5


func _update_stats() -> void:
	if not coords_label or not player:
		return
	var coords := Vector3i(floori(player.global_position.x), floori(player.global_position.y), floori(player.global_position.z))
	if coords != last_coords:
		last_coords = coords
	coords_label.text = "X %d   Y %d   Z %d\n%s" % [
		coords.x, coords.y, coords.z,
		world.get_biome_name(player.global_position),
	]
	stats_label.text = "%d FPS\n%d chunks" % [
		Engine.get_frames_per_second(),
		world.get_loaded_chunk_count(),
	]
