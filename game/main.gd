class_name Main
extends Node3D

const PauseMenuScene := preload("res://ui/pause_menu.tscn")
const ShadowCaptureScript := preload("res://game/shadow_capture.gd")

const HOTBAR: Array[int] = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 27]
const INITIAL_INVENTORY := {1: 64, 2: 64, 3: 64, 4: 64, 5: 32, 6: 32, 7: 32, 8: 32, 9: 16, 10: 32, 27: 32}
const STATS_INTERVAL := 0.25
const NEAR_SHADOW_DISTANCE := 6.0
const SLOT_WIDTH := 92.0
const SLOT_HEIGHT := 64.0
const SLOT_GAP := 6.0

@onready var world: VoxelWorld = $World
@onready var player: Player = $Player
@onready var _environment: Environment = $WorldEnvironment.environment
@onready var _sun: DirectionalLight3D = $Sun
@onready var _hud_root: Control = $HUD/HudRoot
@onready var _underwater_overlay: ColorRect = $HUD/HudRoot/UnderwaterOverlay
@onready var _coords_label: Label = $HUD/HudRoot/CoordsPanel/CoordsLabel
@onready var _stats_label: Label = $HUD/HudRoot/StatsPanel/StatsLabel
@onready var _status_label: Label = $HUD/HudRoot/StatusLabel
@onready var _hotbar: Panel = $HUD/HudRoot/Hotbar
@onready var _day_night: DayNightCycle = $DayNight
@onready var _weather: WeatherSystem = $Weather
@onready var _inventory_overlay: InventoryOverlay = $InventoryOverlay

var slot_panels: Array[PanelContainer] = []
var slot_labels: Array[Label] = []
var selected_slot := 0
var status_time := 6.0
var inventory: Dictionary = INITIAL_INVENTORY.duplicate()
var _pause_menu: PauseMenu
var _stats_time := 0.0


func _ready() -> void:
	_hud_root.theme = UITheme.build()
	_apply_config()
	_build_hotbar()
	_build_pause_menu()
	_connect_player()
	_inventory_overlay.opened.connect(_on_inventory_opened)
	_inventory_overlay.closed.connect(_on_inventory_closed)
	_inventory_overlay.time_selected.connect(_on_inventory_time_selected)
	var spawn := world.get_spawn_position()
	player.global_position = spawn
	player.spawn_position = spawn
	world.setup_player(player)
	spawn = world.find_safe_spawn(spawn)
	player.global_position = spawn
	player.spawn_position = spawn
	player.setup_world(world)
	_weather.setup(player.camera, _day_night)
	_weather.weather_changed.connect(_on_weather_changed)
	_inventory_overlay.weather_toggled.connect(_on_weather_toggled)
	player.set_selected_block(HOTBAR[selected_slot])
	_update_inventory_display()
	set_status("WASD move   double-tap SPACE to fly   ESC pause")
	var shadow_capture := ShadowCaptureScript.new()
	shadow_capture.name = "ShadowCapture"
	shadow_capture.state_provider = _get_shadow_capture_state
	shadow_capture.status_requested.connect(set_status)
	add_child(shadow_capture)


func _get_shadow_capture_state() -> Dictionary:
	var viewport := get_viewport()
	return {
		"engine": Engine.get_version_info(),
		"world": GameConfig.world.duplicate(true),
		"edited_blocks": world.get("_edited_blocks").duplicate(),
		"paused": get_tree().paused,
		"camera_transform": str(player.camera.global_transform),
		"camera_fov": player.camera.fov,
		"camera_far": player.camera.far,
		"sun_transform": str(_sun.global_transform),
		"sun_processing": _sun.can_process(),
		"day_night_processing": _day_night.can_process(),
		"time_hours": _day_night.time_hours,
		"shadow_enabled": _sun.shadow_enabled,
		"shadow_opacity": _sun.shadow_opacity,
		"shadow_blur": _sun.shadow_blur,
		"shadow_distance": _sun.directional_shadow_max_distance,
		"light_angular_distance": _sun.light_angular_distance,
		"taa": viewport.use_taa,
		"msaa": viewport.msaa_3d,
		"scaling_mode": viewport.scaling_3d_mode,
		"scaling_scale": viewport.scaling_3d_scale,
		"viewport_size": str(viewport.get_visible_rect().size),
		"ssao": _environment.ssao_enabled,
		"ssil": _environment.ssil_enabled,
		"ssr": _environment.ssr_enabled,
		"volumetric_fog": _environment.volumetric_fog_enabled,
		"graphics_config": GameConfig.get_graphics().duplicate(true),
	}


func _exit_tree() -> void:
	get_tree().paused = false


func _process(delta: float) -> void:
	if status_time > 0.0:
		status_time -= delta
		if status_time <= 0.0:
			_status_label.text = ""
	_underwater_overlay.visible = world.is_water_at(player.camera.global_position)
	_stats_time -= delta
	if _stats_time <= 0.0:
		_stats_time = STATS_INTERVAL
		_update_stats()


func _apply_config() -> void:
	var render_distance := GameConfig.get_render_distance()
	world.configure(GameConfig.world, render_distance)
	_apply_graphics()
	_update_camera_far(render_distance)


func _apply_graphics() -> void:
	var graphics := GameConfig.get_graphics()
	_environment.ssao_enabled = bool(graphics["ssao_ssil"])
	_environment.ssil_enabled = bool(graphics["ssao_ssil"])
	_environment.sdfgi_enabled = bool(graphics["sdfgi"])
	_environment.ssr_enabled = bool(graphics["ssr"])
	_environment.volumetric_fog_enabled = bool(graphics["volumetric_fog"])
	_environment.volumetric_fog_density = float(graphics["volumetric_fog_density"])
	_environment.volumetric_fog_length = float(graphics["volumetric_fog_length"])
	_environment.volumetric_fog_anisotropy = float(graphics["volumetric_fog_anisotropy"])
	_environment.fog_density = float(graphics["fog_density"])
	_day_night.base_fog_density = float(graphics["fog_density"])
	_environment.glow_intensity = float(graphics["glow_intensity"])
	_environment.tonemap_mode = int(graphics["tonemap"])
	_environment.tonemap_exposure = float(graphics["tonemap_exposure"])
	_environment.adjustment_enabled = true
	_environment.adjustment_saturation = float(graphics["saturation"])
	_environment.adjustment_contrast = float(graphics["contrast"])
	_day_night.base_saturation = float(graphics["saturation"])
	_day_night.base_contrast = float(graphics["contrast"])
	_sun.directional_shadow_max_distance = float(graphics["shadow_max_distance"])
	# Reserve the first cascade for nearby blocks instead of spreading it over
	# 10% of the full shadow range, which makes shadow texels visibly crawl.
	var near_split := minf(NEAR_SHADOW_DISTANCE / maxf(_sun.directional_shadow_max_distance, 1.0), 0.1)
	_sun.directional_shadow_split_1 = near_split
	_sun.directional_shadow_split_2 = maxf(near_split * 2.0, 0.1)
	_sun.directional_shadow_split_3 = maxf(_sun.directional_shadow_split_2 * 2.0, 0.3)
	_sun.shadow_opacity = float(graphics["shadow_opacity"])
	var soft_shadows := bool(graphics["soft_shadows"])
	# Keep a narrow spatial filter on hard sun shadows to smooth texel steps.
	# Preserve its world-space width as atlas resolution changes: the tested
	# half-width filter at 8192 needs width 1.0 at 16384. PCSS uses its own scale.
	var atlas_scale := float(ProjectSettings.get_setting("rendering/lights_and_shadows/directional_shadow/size")) / 8192.0
	_sun.shadow_blur = float(graphics["shadow_blur"]) * (1.0 if soft_shadows else 0.5 * atlas_scale)
	var shadow_quality: int = RenderingServer.SHADOW_QUALITY_SOFT_LOW if soft_shadows else RenderingServer.SHADOW_QUALITY_HARD
	var directional_quality: int = RenderingServer.SHADOW_QUALITY_SOFT_LOW if soft_shadows else RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM
	RenderingServer.directional_soft_shadow_filter_set_quality(directional_quality)
	RenderingServer.positional_soft_shadow_filter_set_quality(shadow_quality)
	_sun.light_angular_distance = 0.3 if soft_shadows else 0.0
	var viewport := get_viewport()
	if viewport:
		var fsr_scale := float(graphics["fsr_scale"])
		viewport.scaling_3d_scale = fsr_scale
		viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2 if fsr_scale < 1.0 else Viewport.SCALING_3D_MODE_BILINEAR
		viewport.use_taa = bool(graphics["taa"])
		viewport.anisotropic_filtering_level = Viewport.ANISOTROPY_16X
		viewport.msaa_3d = int(graphics["msaa"])


func _connect_player() -> void:
	player.block_broken.connect(_on_block_broken)
	player.block_placed.connect(_on_block_placed)
	player.status_requested.connect(set_status)
	player.slot_cycled.connect(_on_slot_cycled)
	player.slot_selected.connect(select_slot)
	player.pause_requested.connect(activate_pause)
	player.can_place_check = can_place_selected


func _build_pause_menu() -> void:
	_pause_menu = PauseMenuScene.instantiate() as PauseMenu
	add_child(_pause_menu)
	_pause_menu.setting_changed.connect(_on_setting_changed)
	_pause_menu.new_world_requested.connect(_on_new_world)
	_pause_menu.quit_requested.connect(_on_quit_game)


func _build_hotbar() -> void:
	var hotbar_width := HOTBAR.size() * SLOT_WIDTH + (HOTBAR.size() - 1) * SLOT_GAP + 18.0
	_hotbar.offset_left = -hotbar_width * 0.5
	_hotbar.offset_top = -104.0
	_hotbar.offset_right = hotbar_width * 0.5
	_hotbar.offset_bottom = -22.0
	_hotbar.add_theme_stylebox_override("panel", UITheme.panel_style(UITheme.PANEL, UITheme.BORDER, 1, 10))

	var row := HBoxContainer.new()
	row.position = Vector2(9.0, 9.0)
	row.size = Vector2(hotbar_width - 18.0, SLOT_HEIGHT)
	row.add_theme_constant_override("separation", int(SLOT_GAP))
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hotbar.add_child(row)

	for index in HOTBAR.size():
		var slot := PanelContainer.new()
		slot.custom_minimum_size = Vector2(SLOT_WIDTH, SLOT_HEIGHT)
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
		var style := UITheme.panel_style(
			Color(0.16, 0.3, 0.3, 0.96) if selected else Color(0.06, 0.11, 0.13, 0.92),
			UITheme.TEAL if selected else Color(0.45, 0.65, 0.64, 0.3),
			2 if selected else 1,
			6)
		style.content_margin_left = 6.0
		style.content_margin_right = 6.0
		style.content_margin_top = 6.0
		style.content_margin_bottom = 6.0
		slot_panels[index].add_theme_stylebox_override("panel", style)
		slot_labels[index].add_theme_color_override("font_color", Color.WHITE if selected else UITheme.INK)


func activate_pause() -> void:
	if _pause_menu:
		_pause_menu.open_menu()


func _on_inventory_opened() -> void:
	_inventory_overlay.show_inventory(inventory, world)
	_inventory_overlay.set_weather_state(_weather.is_raining())
	get_tree().paused = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _on_inventory_closed() -> void:
	get_tree().paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _on_inventory_time_selected(hours: float) -> void:
	_day_night.set_time(hours)
	set_status("Time set to %s" % _day_night.get_clock_text())


func _on_weather_toggled() -> void:
	_weather.toggle()
	_inventory_overlay.set_weather_state(_weather.is_raining())


func _on_weather_changed(state: int) -> void:
	set_status("Weather: %s" % ("Rain" if state == WeatherSystem.State.RAIN else "Sunny"))


func _on_setting_changed(key: String, value: Variant) -> void:
	match key:
		"render_distance":
			var render_distance := int(value)
			world.set_render_distance(render_distance)
			_update_camera_far(render_distance)
		"fov":
			player.set_fov(float(value))
		"graphics_preset":
			_apply_graphics()
		"graphics":
			_apply_graphics()


func _on_new_world() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://ui/main_menu.tscn")


func _on_quit_game() -> void:
	GameConfig.save_settings()
	get_tree().quit()


func _on_slot_cycled(direction: int) -> void:
	select_slot(wrapi(selected_slot + direction, 0, HOTBAR.size()))


func _on_block_broken(block_id: int) -> void:
	collect_block(block_id)
	set_status("Mined %s" % world.get_block_name(block_id))


func _on_block_placed(block_id: int) -> void:
	consume_selected_block()
	set_status("Placed %s" % world.get_block_name(block_id))


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
		var key_label := str(index + 1)
		if index == 9:
			key_label = "0"
		elif index > 9:
			key_label = ""
		slot_labels[index].text = "%s  %s\n   x%d" % [key_label, world.get_block_name(block_id), inventory.get(block_id, 0)]


func set_status(message: String) -> void:
	_status_label.text = message
	status_time = 3.5


func _update_camera_far(render_distance: int) -> void:
	if player.camera:
		player.camera.far = maxf(500.0, float(render_distance) * float(VoxelDefs.CHUNK_SIZE) * 1.6 + 160.0)


func _update_stats() -> void:
	if not player:
		return
	var coords := Vector3i(floori(player.global_position.x), floori(player.global_position.y), floori(player.global_position.z))
	_coords_label.text = "X %d   Y %d   Z %d\n%s" % [
		coords.x, coords.y, coords.z,
		world.get_biome_name(player.global_position),
	]
	_stats_label.text = "%d FPS\n%d chunks\n%s" % [
		Engine.get_frames_per_second(),
		world.get_loaded_chunk_count(),
		_day_night.get_clock_text(),
	]
