class_name Main
extends Node3D

const PauseMenuScene := preload("res://ui/pause_menu.tscn")
const ShadowCaptureScript := preload("res://game/shadow_capture.gd")
const WorldgenOverlayScene := preload("res://ui/worldgen_overlay.tscn")
const MinimapScene := preload("res://ui/minimap.tscn")
const MapOverlayScene := preload("res://ui/map_overlay.tscn")

const INITIAL_INVENTORY := {1: 64, 2: 64, 3: 64, 4: 64, 5: 32, 6: 32, 7: 32, 8: 32, 9: 16, 10: 32, 27: 32, BlockRegistry.BLOCK_TNT: 16, BlockRegistry.BLOCK_NUKE: 4, ItemRegistry.ITEM_FLINT_AND_STEEL: 1}
const STATS_INTERVAL := 0.25
const NEAR_SHADOW_DISTANCE := 6.0
const SLOT_WIDTH := 48.0
const SLOT_HEIGHT := 48.0
const SLOT_GAP := 5.0
const SLOT_MARGIN := 6.0
const SLOT_ICON := 30.0
const UNDERWATER_SAMPLE_INTERVAL := 0.15
const UNDERWATER_FADE_SECONDS := 0.35
const UNDERWATER_DEEP_COLOR := Color(0.02, 0.08, 0.16)
const CAVE_FADE_SECONDS := 0.65
const DYNAMIC_RESOLUTION_INTERVAL := 0.5
const DYNAMIC_RESOLUTION_SMOOTHING := 0.2
const SESSION_STATE_VERSION := 2
const AUTOSAVE_RETRY_SECONDS := 30.0

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
var slot_icons: Array[TextureRect] = []
var slot_key_labels: Array[Label] = []
var slot_count_labels: Array[Label] = []
var selected_slot := 0
var status_time := 6.0
var inventory := ItemInventory.new()
var containers := BlockContainers.new()
var _drops: ItemDrops
var _survival_ui: SurvivalUI
var _inventory_overflow: Dictionary = {}
var _container_check_time := 0.0
var _pause_menu: PauseMenu
var _stats_time := 0.0
var _underwater_amount := 0.0
var _underwater_depth := 0.0
var _underwater_tint := Color.WHITE
var _underwater_target := 0.0
var _underwater_sample_time := 0.0
var _cave_amount := 0.0
var _cave_target := 0.0
var _cave_depth := 0.0
var _cave_biome := BiomeCatalog.CAVE_BIOME_NONE
var _cave_tint := Color("#242936")
var _worldgen_overlay: WorldgenOverlay
var _photo_mode: PhotoMode
var _minimap: Minimap
var _map_overlay: MapOverlay
var _minimap_restore := false
var _selection_chip: Label
var _hotbar_slot_size := SLOT_WIDTH
var _hotbar_icon_size := SLOT_ICON
var _frame_time := 1.0 / 60.0
var _dynamic_resolution_timer := 0.0
var _dynamic_resolution_active := false
var _world_storage: WorldStorage
var _autosave_time := 0.0
var _storage_warning_shown := false
var _game_mode: int = GameMode.SURVIVAL


func _ready() -> void:
	var saved_state := _prepare_world_storage()
	player.game_mode = _game_mode
	UITheme.apply(_hud_root)
	_style_hud()
	_apply_config()
	world.set_edit_store(_world_storage)
	_build_hotbar()
	GameConfig.interface_scale_changed.connect(_apply_hud_text_layout)
	_build_crosshair()
	_build_pause_menu()
	_survival_ui = SurvivalUI.new()
	add_child(_survival_ui)
	_survival_ui.setup(_hud_root, player)
	_survival_ui.respawn_requested.connect(_on_respawn)
	_survival_ui.menu_requested.connect(_on_new_world)
	_connect_player()
	_inventory_overlay.opened.connect(_on_inventory_opened)
	_inventory_overlay.closed.connect(_on_inventory_closed)
	_inventory_overlay.time_selected.connect(_on_inventory_time_selected)
	var player_state: Variant = saved_state.get("player", {})
	var resumed := typeof(player_state) == TYPE_DICTIONARY \
		and player.restore_persistent_state(player_state)
	if resumed:
		world.setup_player(player, true)
		# Recover saves written after the player had already entered unloaded or
		# incomplete terrain. The synchronous ring above makes this validation
		# authoritative without relocating valid cave or airborne saves.
		if not world.is_player_volume_clear(player.global_position):
			var recovered_spawn := world.find_safe_spawn(player.global_position)
			player.global_position = recovered_spawn
			player.velocity = Vector3.ZERO
	else:
		var spawn := world.get_spawn_position()
		player.global_position = spawn
		player.spawn_position = spawn
		world.setup_player(player)
		spawn = world.find_safe_spawn(spawn)
		player.global_position = spawn
		player.spawn_position = spawn
	player.setup_world(world)
	_worldgen_overlay = WorldgenOverlayScene.instantiate() as WorldgenOverlay
	add_child(_worldgen_overlay)
	_worldgen_overlay.initialize(world, player)
	_worldgen_overlay.status_requested.connect(set_status)
	_minimap = MinimapScene.instantiate() as Minimap
	add_child(_minimap)
	_minimap.initialize(world, player)
	_minimap.status_requested.connect(set_status)
	_map_overlay = MapOverlayScene.instantiate() as MapOverlay
	add_child(_map_overlay)
	_map_overlay.initialize(world, player)
	_weather.setup(player.camera, _day_night)
	_weather.set_world(world)
	_weather.weather_changed.connect(_on_weather_changed)
	_weather.lightning.connect(_on_lightning)
	_weather.ambience_changed.connect(_on_weather_ambience)
	_inventory_overlay.weather_toggled.connect(_on_weather_toggled)
	_restore_session_state(saved_state)
	_drops = ItemDrops.new()
	add_child(_drops)
	_drops.setup(world, player, inventory)
	if saved_state.get("drops") is Array:
		_drops.restore(saved_state.drops)
	for item_id in _inventory_overflow:
		_drops.spawn_drop(player.global_position, {"id": int(item_id), "count": int(_inventory_overflow[item_id]), "durability": ItemRegistry.max_durability(int(item_id))})
	_inventory_overflow.clear()
	inventory.changed.connect(_update_inventory_display)
	_inventory_overlay.configure_inventory(inventory, world)
	_inventory_overlay.set_game_mode(_game_mode)
	_update_inventory_display()
	_show_control_hint()
	var shadow_capture := ShadowCaptureScript.new()
	shadow_capture.name = "ShadowCapture"
	shadow_capture.state_provider = _get_shadow_capture_state
	shadow_capture.status_requested.connect(set_status)
	add_child(shadow_capture)
	_photo_mode = PhotoMode.new()
	_photo_mode.name = "PhotoMode"
	_photo_mode.initialize(player.camera, _hud_root)
	_photo_mode.mouse_sensitivity_provider = GameConfig.get_mouse_sensitivity
	_photo_mode.status_requested.connect(set_status)
	_photo_mode.camera_mode_changed.connect(_on_photo_camera_changed)
	add_child(_photo_mode)
	if player.dead:
		_on_player_died("Saved expedition")


func _get_shadow_capture_state() -> Dictionary:
	var viewport := get_viewport()
	var view := _active_camera()
	if view == null:
		view = player.camera
	return {
		"engine": Engine.get_version_info(),
		"world": GameConfig.world.duplicate(true),
		"edited_blocks": world.get("_edited_blocks").duplicate(),
		"paused": get_tree().paused,
		"camera_transform": str(view.global_transform),
		"camera_fov": view.fov,
		"camera_far": view.far,
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
		"hud_visible": _hud_root.visible,
		"photo_camera": _photo_mode != null and _photo_mode.is_camera_active(),
		"worldgen_stats": world.get_worldgen_stats(),
		"worldgen_overlay": {
			"overlay_visible": _worldgen_overlay != null and _worldgen_overlay.visible,
			"map_mode": _worldgen_overlay.get_mode() if _worldgen_overlay != null else "",
		},
		"minimap": {
			"visible": _minimap != null and _minimap.visible,
			"mode": _minimap.get_mode() if _minimap != null else "",
			"pending": _minimap.is_pending() if _minimap != null else false,
		},
		"map_overlay": {
			"visible": _map_overlay != null and _map_overlay.visible,
			"mode": _map_overlay.get_mode() if _map_overlay != null else "",
			"pending": _map_overlay.is_pending() if _map_overlay != null else false,
		},
	}


func _exit_tree() -> void:
	_flush_world_save()
	get_tree().paused = false


func _unhandled_input(event: InputEvent) -> void:
	# Photo mode owns its keys and promises a clean view; leave the minimap,
	# debug overlay, and modal map for after the camera is dismissed.
	if _photo_mode != null and _photo_mode.is_camera_active():
		return
	if event.is_action_pressed("debug_worldgen"):
		get_viewport().set_input_as_handled()
		if _worldgen_overlay != null:
			_worldgen_overlay.toggle()
	elif event.is_action_pressed("debug_worldgen_mode"):
		get_viewport().set_input_as_handled()
		if _worldgen_overlay != null:
			_worldgen_overlay.cycle_mode()
	elif event.is_action_pressed("minimap"):
		get_viewport().set_input_as_handled()
		if _minimap != null:
			_minimap.toggle()
	elif event.is_action_pressed("minimap_mode"):
		get_viewport().set_input_as_handled()
		if _minimap != null:
			_minimap.cycle_mode()
	elif event.is_action_pressed("map_overlay"):
		get_viewport().set_input_as_handled()
		if _map_overlay != null:
			_map_overlay.open()


func _process(delta: float) -> void:
	if not get_tree().paused:
		containers.tick(delta)
		_container_check_time -= delta
		if _container_check_time <= 0.0:
			_container_check_time = 0.5
			_check_removed_containers()
		_autosave_time += delta
		var autosave_interval := GameConfig.get_autosave_interval()
		if autosave_interval > 0.0 and _autosave_time >= autosave_interval:
			if _flush_world_save():
				_autosave_time = 0.0
			else:
				_autosave_time = maxf(autosave_interval - minf(AUTOSAVE_RETRY_SECONDS, autosave_interval), 0.0)
	if status_time > 0.0:
		status_time -= delta
		if status_time <= 0.0:
			_status_label.text = ""
	_update_underwater(delta)
	_update_frame_pacing(delta)
	_stats_time -= delta
	if _stats_time <= 0.0:
		_stats_time = STATS_INTERVAL
		_update_stats()


## Grades the overlay, fog, caustics, and audio from the submerged state. The
## world query is throttled; the blend itself is smoothed per frame so
## surfacing does not pop.
func _update_underwater(delta: float) -> void:
	_underwater_sample_time -= delta
	if _underwater_sample_time <= 0.0:
		_underwater_sample_time = UNDERWATER_SAMPLE_INTERVAL
		var view := _active_camera()
		if view == null:
			return
		var ambience := world.get_water_ambience(view.global_position)
		_underwater_target = 1.0 if bool(ambience["submerged"]) else 0.0
		_underwater_depth = clampf(float(ambience["depth"]) / DayNightCycle.UNDERWATER_MAX_DEPTH, 0.0, 1.0)
		if _underwater_target > 0.0:
			_underwater_tint = ambience["tint"] as Color
		var cave := world.get_cave_ambience(view.global_position)
		_cave_target = 1.0 if bool(cave["active"]) and _underwater_target <= 0.0 else 0.0
		_cave_depth = float(cave["depth"])
		if _cave_target > 0.0:
			_cave_biome = int(cave["biome"])
			_cave_tint = cave["tint"] as Color
	_underwater_amount = move_toward(_underwater_amount, _underwater_target, delta / UNDERWATER_FADE_SECONDS)
	_cave_amount = move_toward(_cave_amount, _cave_target, delta / CAVE_FADE_SECONDS)
	_day_night.set_underwater(_underwater_amount, _underwater_depth, _underwater_tint)
	_day_night.set_cave_ambience(_cave_amount, _cave_depth, _cave_biome, _cave_tint)
	_underwater_overlay.visible = _underwater_amount > 0.001
	if _underwater_overlay.visible:
		var tinted := _underwater_tint.lerp(UNDERWATER_DEEP_COLOR, _underwater_depth * 0.75)
		_underwater_overlay.color = Color(tinted.r, tinted.g, tinted.b,
			lerpf(0.06, 0.42, _underwater_depth) * _underwater_amount)
	AudioManager.set_underwater(_underwater_amount > 0.5)


## Dynamic resolution holds the target frame rate by trading 3D render scale
## for frame time. The stepping policy is pure and lives in GameConfig; this
## only smooths frame time and applies a step on an interval so FSR2 is not
## asked to recreate its context every frame. Capped frame times (FPS cap or
## vsync refresh) are treated as the budget, not as GPU load.
func _update_frame_pacing(delta: float) -> void:
	if not bool(GameConfig.get_setting("dynamic_resolution")):
		_dynamic_resolution_active = false
		return
	if not _dynamic_resolution_active:
		_dynamic_resolution_active = true
		_frame_time = delta
		_dynamic_resolution_timer = DYNAMIC_RESOLUTION_INTERVAL
		return
	_frame_time = lerpf(_frame_time, delta, 1.0 - exp(-delta / DYNAMIC_RESOLUTION_SMOOTHING))
	_dynamic_resolution_timer -= delta
	if _dynamic_resolution_timer > 0.0:
		return
	_dynamic_resolution_timer = DYNAMIC_RESOLUTION_INTERVAL
	var viewport := get_viewport()
	if viewport == null:
		return
	var target_fps := maxf(float(GameConfig.get_setting("dynamic_resolution_target")), 1.0)
	var cap_period := 0.0
	var cap := maxi(int(GameConfig.get_setting("fps_cap")), 0)
	if cap > 0:
		cap_period = 1.0 / float(cap)
	if GameConfig.get_vsync_mode() != DisplayServer.VSYNC_DISABLED:
		var refresh := DisplayServer.screen_get_refresh_rate()
		if refresh < 1.0:
			refresh = 60.0
		cap_period = maxf(cap_period, 1.0 / refresh)
	var max_scale := clampf(float(GameConfig.get_graphics().get("fsr_scale", 1.0)), GameConfig.DYNAMIC_RESOLUTION_MIN_SCALE, 1.0)
	var scale := GameConfig.dynamic_resolution_scale(
		viewport.scaling_3d_scale, _frame_time, 1.0 / target_fps, max_scale, cap_period)
	# A sub-native scale needs the FSR2 path; at native keep the plain bilinear
	# mode so TAA/FSR2 state matches what _apply_graphics() configured.
	var mode := Viewport.SCALING_3D_MODE_FSR2 if scale < 1.0 else Viewport.SCALING_3D_MODE_BILINEAR
	if viewport.scaling_3d_mode != mode:
		viewport.scaling_3d_mode = mode
	viewport.scaling_3d_scale = scale


func _apply_config() -> void:
	var render_distance := GameConfig.get_render_distance()
	world.configure(GameConfig.world, render_distance, GameConfig.get_lod_mode())
	_apply_graphics()
	_update_camera_far(render_distance)


func _prepare_world_storage() -> Dictionary:
	_game_mode = GameConfig.get_game_mode()
	_world_storage = WorldStorage.new()
	var metadata: Dictionary = {}
	if GameConfig.has_active_world():
		metadata = _world_storage.open_world(GameConfig.active_world_id)
	if metadata.is_empty():
		metadata = _world_storage.create_world(GameConfig.world, {}, "", true, _game_mode)
	if metadata.is_empty():
		push_warning("World storage is unavailable; continuing without persistence")
		_world_storage = null
		GameConfig.clear_active_world()
		return {}
	GameConfig.activate_world(metadata)
	_game_mode = GameConfig.get_game_mode()
	return _migrate_session_state(metadata.get("state", {}))


func _migrate_session_state(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return {}
	var state: Dictionary = value.duplicate(true)
	var version := int(state.get("state_version", 0))
	if version > SESSION_STATE_VERSION:
		push_warning("Save uses unsupported session state version %d" % version)
		return {}
	# Keep the source version until inventory restoration has migrated its rows.
	return state


func _restore_session_state(state: Dictionary) -> void:
	_inventory_overflow.clear()
	if state.is_empty():
		_inventory_overflow = inventory.migrate_counts(INITIAL_INVENTORY if _game_mode == GameMode.CREATIVE else {})
		return
	var saved_inventory: Variant = state.get("inventory", null)
	if saved_inventory is Array:
		if int(state.get("state_version", 0)) >= 2:
			inventory.restore(saved_inventory)
		else:
			var counts := {}
			for entry in saved_inventory:
				if entry is Array and entry.size() == 2:
					var item_id := int(entry[0])
					counts[item_id] = int(counts.get(item_id, 0)) + maxi(int(entry[1]), 0)
			_inventory_overflow = inventory.migrate_counts(counts)
	else:
		_inventory_overflow = inventory.migrate_counts(INITIAL_INVENTORY if _game_mode == GameMode.CREATIVE else {})
	if state.get("containers") is Dictionary:
		containers.restore(state.containers)
	selected_slot = clampi(int(state.get("selected_slot", 0)), 0, ItemInventory.HOTBAR_SIZE - 1)
	var day_state: Variant = state.get("day_night", {})
	if typeof(day_state) == TYPE_DICTIONARY:
		_day_night.restore_persistent_state(day_state)
	var weather_state: Variant = state.get("weather", {})
	if typeof(weather_state) == TYPE_DICTIONARY:
		_weather.restore_persistent_state(weather_state)
		_day_night.set_time(_day_night.time_hours)
		_on_weather_changed(_weather.state)


func _build_persistent_state() -> Dictionary:
	_check_removed_containers()
	return {
		"state_version": SESSION_STATE_VERSION,
		"player": player.persistent_state(),
		"inventory": inventory.persistent_state(),
		"containers": containers.persistent_state(),
		"drops": _drops.persistent_state() if is_instance_valid(_drops) else [],
		"selected_slot": selected_slot,
		"day_night": _day_night.persistent_state(),
		"weather": _weather.persistent_state(),
	}


func _flush_world_save() -> bool:
	if _world_storage == null or player == null:
		return false
	var save_error := world.flush_edit_store()
	if save_error == OK:
		save_error = _world_storage.flush(_build_persistent_state())
	if save_error == OK:
		GameConfig.active_world_metadata = _world_storage.metadata.duplicate(true)
		if not _storage_warning_shown and _world_storage.unreadable_region_count() > 0:
			_storage_warning_shown = true
			set_status("A damaged world region is read-only; edits there cannot be saved")
		return true
	else:
		push_warning("World save failed with error %d" % save_error)
		set_status("Save failed - progress remains in memory")
		return false


func _apply_graphics() -> void:
	var graphics := GameConfig.get_graphics()
	_environment.ssao_enabled = bool(graphics["ssao_ssil"])
	_environment.ssil_enabled = bool(graphics["ssao_ssil"])
	_environment.sdfgi_enabled = bool(graphics["sdfgi"])
	_environment.ssr_enabled = bool(graphics["ssr"])
	_environment.volumetric_fog_enabled = bool(graphics["volumetric_fog"])
	# DayNightCycle owns the per-time-of-day modulation of this density.
	_day_night.base_volumetric_fog_density = float(graphics["volumetric_fog_density"])
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
	# Overlap the cascades slightly; without blending the split boundaries show
	# as hard diagonal lines that follow the camera.
	_sun.directional_shadow_blend_splits = true
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
	# Leaf shadow proxy: solid canopy shadows are aliasing-free but lose the
	# dappled leaf look, so it is a player choice.
	var registry := world.get_registry()
	if registry != null and registry.material is ShaderMaterial:
		(registry.material as ShaderMaterial).set_shader_parameter(
			"solid_leaf_shadows", 1.0 if bool(graphics["solid_leaf_shadows"]) else 0.0)
	var viewport := get_viewport()
	if viewport:
		var fsr_scale := float(graphics["fsr_scale"])
		viewport.scaling_3d_scale = fsr_scale
		viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2 if fsr_scale < 1.0 else Viewport.SCALING_3D_MODE_BILINEAR
		viewport.use_taa = bool(graphics["taa"])
		viewport.anisotropic_filtering_level = Viewport.ANISOTROPY_16X
		viewport.msaa_3d = int(graphics["msaa"])


func _connect_player() -> void:
	player.mined_block.connect(_on_mined_block)
	player.block_picked.connect(_on_block_picked)
	player.block_interacted.connect(_on_block_interacted)
	player.died.connect(_on_player_died)
	player.block_placed.connect(_on_block_placed)
	player.item_used.connect(_on_item_used)
	player.status_requested.connect(set_status)
	player.slot_cycled.connect(_on_slot_cycled)
	player.slot_selected.connect(select_slot)
	player.pause_requested.connect(activate_pause)
	player.can_place_check = can_place_selected
	player.interact_check = func(position: Vector3i) -> bool:
		var block_id := world.get_block_world(position)
		return block_id in [BlockRegistry.BLOCK_CRAFTING_TABLE, BlockRegistry.BLOCK_CHEST, BlockRegistry.BLOCK_FURNACE] \
			or BlockRegistry.is_door(block_id) or BlockRegistry.is_bed(block_id)


func _build_pause_menu() -> void:
	_pause_menu = PauseMenuScene.instantiate() as PauseMenu
	add_child(_pause_menu)
	_pause_menu.setting_changed.connect(_on_setting_changed)
	_pause_menu.settings_closed.connect(_show_control_hint)
	_pause_menu.new_world_requested.connect(_on_new_world)
	_pause_menu.quit_requested.connect(_on_quit_game)


func _style_hud() -> void:
	# Instrument chips: coords read out position, stats read out telemetry.
	var chip := UITheme.chip_style()
	_coords_label.add_theme_font_override("font", UITheme.font_semi())
	UITheme.apply_font_size(_coords_label, 12)
	_coords_label.add_theme_color_override("font_color", UITheme.INK)
	var coords_panel := _coords_label.get_parent() as PanelContainer
	coords_panel.add_theme_stylebox_override("panel", chip)
	_stats_label.add_theme_font_override("font", UITheme.font_semi())
	UITheme.apply_font_size(_stats_label, 12)
	_stats_label.add_theme_color_override("font_color", UITheme.MUTED)
	var stats_panel := _stats_label.get_parent() as PanelContainer
	stats_panel.add_theme_stylebox_override("panel", chip.duplicate())

	# Selection chip floats above the hotbar; status toast above that.
	_selection_chip = Label.new()
	_selection_chip.name = "SelectionChip"
	_selection_chip.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_selection_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_selection_chip.add_theme_font_override("font", UITheme.font_semi())
	UITheme.apply_font_size(_selection_chip, 13)
	_selection_chip.add_theme_color_override("font_color", UITheme.EMBER_HI)
	_selection_chip.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.75))
	_selection_chip.add_theme_constant_override("shadow_offset_x", 1)
	_selection_chip.add_theme_constant_override("shadow_offset_y", 1)
	_selection_chip.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_hud_root.add_child(_selection_chip)
	_selection_chip.offset_left = -160.0
	_selection_chip.offset_right = 160.0
	_selection_chip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	_status_label.add_theme_font_override("font", UITheme.font_semi())
	UITheme.apply_font_size(_status_label, 14)
	_status_label.add_theme_color_override("font_color", UITheme.INK_DIM)


## Keeps the HUD's fixed-pixel boxes in step with the text-size setting: the
## hotbar count labels, the selection chip, and the status toast. Called after
## the HUD is built and on every live interface-scale change.
func _apply_hud_text_layout() -> void:
	var scale := UITheme.text_scale()
	var count_height := 13.0 * scale
	for label in slot_count_labels:
		label.position = Vector2(0, _hotbar_slot_size - 10.0 - count_height)
		label.size = Vector2(_hotbar_slot_size - 10.0, count_height)
	if _selection_chip != null:
		_selection_chip.offset_top = -92.0 - 18.0 * scale
		_selection_chip.offset_bottom = -92.0
	if _status_label != null:
		_status_label.offset_top = -112.0 - 22.0 * scale
		_status_label.offset_bottom = -112.0


func _build_crosshair() -> void:
	# Replace the text "+" with hairline ticks and a dot, each with a dark
	# backing rect so it stays readable against sky and caves alike.
	var old := _hud_root.get_node_or_null("Crosshair") as Label
	if old != null:
		old.visible = false
	var reticle := Control.new()
	reticle.name = "CrosshairReticle"
	reticle.set_anchors_preset(Control.PRESET_CENTER)
	reticle.custom_minimum_size = Vector2(34.0, 34.0)
	reticle.size = Vector2(34.0, 34.0)
	reticle.position = Vector2(-17.0, -17.0)
	reticle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ink := Color(0.95, 0.92, 0.83, 0.92)
	var backing := Color(0.0, 0.0, 0.0, 0.5)
	for spec in [
		[Vector2(16, 3), Vector2(2, 8)],
		[Vector2(16, 23), Vector2(2, 8)],
		[Vector2(3, 16), Vector2(8, 2)],
		[Vector2(23, 16), Vector2(8, 2)],
	]:
		var tick_pos: Vector2 = spec[0]
		var tick_size: Vector2 = spec[1]
		var shadow := ColorRect.new()
		shadow.color = backing
		shadow.position = tick_pos + Vector2(1, 1)
		shadow.size = tick_size
		shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		reticle.add_child(shadow)
		var rect := ColorRect.new()
		rect.color = ink
		rect.position = tick_pos
		rect.size = tick_size
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		reticle.add_child(rect)
	var dot_shadow := ColorRect.new()
	dot_shadow.color = backing
	dot_shadow.position = Vector2(17, 17)
	dot_shadow.size = Vector2(2, 2)
	dot_shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	reticle.add_child(dot_shadow)
	var dot := ColorRect.new()
	dot.color = ink
	dot.position = Vector2(16, 16)
	dot.size = Vector2(2, 2)
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	reticle.add_child(dot)
	_hud_root.add_child(reticle)


func _build_hotbar() -> void:
	var slot_count := ItemInventory.HOTBAR_SIZE
	var available_width := get_viewport().get_visible_rect().size.x - 24.0
	_hotbar_slot_size = minf(SLOT_WIDTH, floorf(
		(available_width - SLOT_MARGIN * 2.0 - (slot_count - 1) * SLOT_GAP) / slot_count))
	_hotbar_icon_size = minf(SLOT_ICON, _hotbar_slot_size - 22.0)
	var hotbar_width := slot_count * _hotbar_slot_size + (slot_count - 1) * SLOT_GAP + SLOT_MARGIN * 2.0
	_hotbar.offset_left = -hotbar_width * 0.5
	_hotbar.offset_top = -76.0
	_hotbar.offset_right = hotbar_width * 0.5
	_hotbar.offset_bottom = -10.0
	var empty := StyleBoxEmpty.new()
	_hotbar.add_theme_stylebox_override("panel", empty)

	var row := HBoxContainer.new()
	row.name = "Slots"
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_left = SLOT_MARGIN
	row.offset_right = -SLOT_MARGIN
	row.offset_top = SLOT_MARGIN
	row.offset_bottom = -SLOT_MARGIN
	row.add_theme_constant_override("separation", int(SLOT_GAP))
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hotbar.add_child(row)

	for index in slot_count:
		var slot := PanelContainer.new()
		slot.custom_minimum_size = Vector2(_hotbar_slot_size, minf(SLOT_HEIGHT, _hotbar_slot_size))
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.clip_contents = false
		row.add_child(slot)
		slot_panels.append(slot)

		var overlay := Control.new()
		overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(overlay)

		var icon := TextureRect.new()
		icon.name = "Icon"
		var content := _hotbar_slot_size - 10.0
		icon.custom_minimum_size = Vector2(_hotbar_icon_size, _hotbar_icon_size)
		icon.size = Vector2(_hotbar_icon_size, _hotbar_icon_size)
		icon.position = Vector2((content - _hotbar_icon_size) * 0.5, (content - _hotbar_icon_size) * 0.5)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		overlay.add_child(icon)
		slot_icons.append(icon)

		var key_label := Label.new()
		key_label.text = _slot_key_hint(index)
		key_label.position = Vector2(1, 0)
		key_label.add_theme_font_override("font", UITheme.font_semi())
		UITheme.apply_font_size(key_label, 9)
		key_label.add_theme_color_override("font_color", UITheme.FAINT)
		key_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		overlay.add_child(key_label)
		slot_key_labels.append(key_label)

		var count_label := Label.new()
		count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		count_label.add_theme_font_override("font", UITheme.font_semi())
		UITheme.apply_font_size(count_label, 11)
		count_label.add_theme_color_override("font_color", UITheme.INK_DIM)
		count_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
		count_label.add_theme_constant_override("shadow_offset_x", 1)
		count_label.add_theme_constant_override("shadow_offset_y", 1)
		count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		overlay.add_child(count_label)
		slot_count_labels.append(count_label)

	_update_slot_styles()
	_apply_hud_text_layout()


func _slot_key_hint(index: int) -> String:
	if index < 9:
		return str(index + 1)
	if index == 9:
		return "0"
	return ""


func _update_slot_styles() -> void:
	for index in slot_panels.size():
		var selected := index == selected_slot
		var style := UITheme.panel_style(
			Color(0.128, 0.176, 0.208, 0.95) if selected else Color(UITheme.SURFACE.r, UITheme.SURFACE.g, UITheme.SURFACE.b, 0.9),
			UITheme.EMBER if selected else UITheme.LINE,
			2 if selected else 1,
			10)
		style.content_margin_left = 6.0
		style.content_margin_right = 6.0
		style.content_margin_top = 6.0
		style.content_margin_bottom = 6.0
		slot_panels[index].add_theme_stylebox_override("panel", style)
		slot_count_labels[index].add_theme_color_override("font_color",
			UITheme.EMBER_HI if selected else UITheme.INK_DIM)
		slot_key_labels[index].add_theme_color_override("font_color",
			UITheme.CYAN if selected else UITheme.FAINT)


func activate_pause() -> void:
	if player.dead:
		return
	if _map_overlay != null and _map_overlay.visible:
		_map_overlay.close()
		return
	if _pause_menu:
		_pause_menu.open_menu()


func _on_inventory_opened() -> void:
	if player.dead or _pause_menu.visible or (_photo_mode != null and _photo_mode.is_camera_active()):
		_inventory_overlay.close_panel()
		return
	player.cancel_mining()
	if _map_overlay != null and _map_overlay.visible:
		_map_overlay.close()
	_inventory_overlay.set_weather_state(_weather.is_raining())
	get_tree().paused = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _on_inventory_closed() -> void:
	if player.dead or _pause_menu.visible:
		get_tree().paused = true
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		return
	get_tree().paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _on_inventory_time_selected(hours: float) -> void:
	if _game_mode != GameMode.CREATIVE:
		return
	_day_night.set_time(hours)
	set_status("Time set to %s" % _day_night.get_clock_text())


func _on_weather_toggled() -> void:
	if _game_mode != GameMode.CREATIVE:
		return
	_weather.toggle()
	_inventory_overlay.set_weather_state(_weather.is_raining())


func _on_weather_changed(_state: int) -> void:
	_refresh_weather_status()
	# Cold biomes hear the wind bed rather than rain, even while precipitating.
	AudioManager.set_rain(_weather.is_raining() and not _weather.is_snowing())


## Labels the current weather from the biome-aware precipitation identity, so a
## cold biome reports "Snow" rather than the raw rain toggle.
func _refresh_weather_status() -> void:
	var label := "Sunny"
	match _weather.get_precipitation():
		WeatherSystem.Precipitation.RAIN:
			label = "Rain"
		WeatherSystem.Precipitation.SNOW:
			label = "Snow"
	set_status("Weather: %s" % label)


## Lightning flash plus a thunder clap. Lightning is muted in cold biomes by
## WeatherSystem, so this only fires for rain storms.
func _on_lightning(strength: float) -> void:
	_day_night.trigger_lightning(strength)
	AudioManager.play_thunder(strength)


## The camera entered/left a cold or wetland biome; keep the wind bed in step
## and swap the rain bed for wind (or back) if it is currently precipitating.
func _on_weather_ambience(cold: bool, _wetland: bool) -> void:
	AudioManager.set_wind(cold)
	AudioManager.set_rain(_weather.is_raining() and not cold)
	# Crossing into/out of a cold biome only changes the label while raining.
	if _weather.is_raining():
		_refresh_weather_status()


func _on_photo_camera_changed(active: bool, camera: Camera3D) -> void:
	# Streaming, weather, and player control all follow the active render camera.
	# Entry can stream the camera's surroundings asynchronously, but returning
	# to the player must commit its ring before physics unfreezes.
	world.setup_player(camera if active else player, not active)
	player.set_photo_mode(active)
	_weather.set_camera(camera if active else player.camera)
	if active:
		# The minimap and the nonmodal F3 map would sit over the composition;
		# hide them and close the overlay, restoring the minimap's own toggle
		# state afterwards.
		_minimap_restore = _minimap != null and _minimap.visible
		if _minimap != null:
			_minimap.visible = false
		if _worldgen_overlay != null and _worldgen_overlay.visible:
			_worldgen_overlay.visible = false
	elif _minimap != null:
		_minimap.visible = _minimap_restore


func _active_camera() -> Camera3D:
	if _photo_mode != null and _photo_mode.is_camera_active():
		return _photo_mode.get_camera()
	return player.camera


func _on_setting_changed(key: String, value: Variant) -> void:
	match key:
		"render_distance":
			var render_distance := int(value)
			world.set_render_distance(render_distance)
			_update_camera_far(render_distance)
		"lod_mode":
			world.set_lod_mode(int(value))
		"fov":
			player.set_fov(float(value))
		"graphics_preset":
			_apply_graphics()
		"graphics":
			_apply_graphics()
		"dynamic_resolution":
			_apply_graphics()


func _on_new_world() -> void:
	_flush_world_save()
	GameConfig.clear_active_world()
	get_tree().paused = false
	get_tree().change_scene_to_file("res://ui/main_menu.tscn")


func _on_quit_game() -> void:
	_flush_world_save()
	GameConfig.save_settings()
	get_tree().quit()


func _on_slot_cycled(direction: int) -> void:
	select_slot(wrapi(selected_slot + direction, 0, ItemInventory.HOTBAR_SIZE))


func _on_mined_block(position: Vector3i, block_id: int, harvest: bool) -> void:
	if _game_mode == GameMode.SURVIVAL:
		inventory.wear_tool(selected_slot)
	_drop_container_contents(position)
	if harvest and _game_mode == GameMode.SURVIVAL:
		var drop := ItemRegistry.harvest_drop(block_id)
		if not drop.is_empty():
			_drops.spawn_drop(Vector3(position) + Vector3.ONE * 0.5, drop)
	set_status("Mined %s" % world.get_block_name(block_id))


func _on_block_placed(block_id: int) -> void:
	consume_selected_block()
	set_status("Placed %s" % world.get_block_name(block_id))


func _on_block_picked(block_id: int) -> void:
	if not ItemRegistry.is_valid(block_id):
		return
	if _game_mode == GameMode.CREATIVE:
		inventory.slots[selected_slot] = {"id": block_id, "count": ItemRegistry.stack_limit(block_id),
			"durability": ItemRegistry.max_durability(block_id)}
		inventory.changed.emit()
		_update_inventory_display()
		return
	for index in inventory.slots.size():
		if int(inventory.slots[index].get("id", 0)) != block_id:
			continue
		if index < ItemInventory.HOTBAR_SIZE:
			select_slot(index)
		else:
			inventory.move_stack(index, selected_slot)
		return
	set_status("You do not own %s" % _item_name(block_id))


func _on_block_interacted(position: Vector3i) -> void:
	if player.dead:
		return
	var block_id := world.get_block_world(position)
	if BlockRegistry.is_door(block_id):
		if world.toggle_door(position):
			set_status("Door opened" if BlockRegistry.door_open(world.get_block_world(position)) else "Door closed")
		return
	if BlockRegistry.is_bed(block_id):
		_attempt_sleep(position)
		return
	_inventory_overlay.open_station(position, block_id, containers)


func _attempt_sleep(bed_position: Vector3i) -> void:
	if not _day_night.is_night():
		set_status("You can only sleep at night")
		return
	if _weather.is_raining():
		set_status("You cannot sleep while it is raining")
		return
	if world.is_threatened(player.global_position):
		set_status("You cannot sleep while threatened")
		return
	var requested_spawn := Vector3(bed_position) + Vector3(0.5, 2.0, 0.5)
	var safe_spawn := world.find_safe_spawn(requested_spawn)
	if safe_spawn.is_equal_approx(requested_spawn):
		set_status("No safe respawn point near this bed")
		return
	player.spawn_position = safe_spawn
	_day_night.skip_to_morning()
	set_status("Slept until morning · respawn point set")
	_flush_world_save()


func _drop_container_contents(position: Vector3i) -> void:
	if _game_mode == GameMode.CREATIVE:
		containers.remove(position)
		return
	if not is_instance_valid(_drops):
		return
	for stack in containers.remove(position):
		if not stack.is_empty():
			_drops.spawn_drop(Vector3(position) + Vector3.ONE * 0.5, stack)


func _check_removed_containers() -> void:
	if world == null or not is_instance_valid(_drops):
		return
	for position: Vector3i in containers.containers.keys():
		# get_block_world returns air for unloaded/LOD chunks, not actual absence.
		if not world.is_full_chunk_resident_at(position):
			continue
		if world.get_block_world(position) != int(containers.containers[position].block_id):
			_drop_container_contents(position)


func _on_player_died(cause: String) -> void:
	if _photo_mode != null and _photo_mode.is_camera_active():
		_photo_mode.set_free_camera(false)
	if _inventory_overlay.visible:
		_inventory_overlay.close_panel()
	if _map_overlay != null and _map_overlay.visible:
		_map_overlay.close()
	if _pause_menu.visible:
		_pause_menu.close_menu()
	_survival_ui.show_death(cause)
	get_tree().paused = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _on_respawn() -> void:
	player.respawn()
	_survival_ui.hide_death()
	get_tree().paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	_update_inventory_display()
	_flush_world_save()


func _on_item_used(item_id: int, block_position: Vector3i) -> void:
	if player.dead or not can_place_selected() or int(inventory.slots[selected_slot].get("id", 0)) != item_id:
		return
	var food := ItemRegistry.food_value(item_id)
	if food > 0.0:
		if player.eat(food):
			inventory.remove_at(selected_slot)
			if item_id == ItemRegistry.ITEM_MUSHROOM_STEW:
				var overflow := inventory.add_item(ItemRegistry.ITEM_BOWL)
				if overflow > 0:
					_drops.spawn_drop(player.global_position, {"id": ItemRegistry.ITEM_BOWL, "count": overflow})
		return
	if item_id != ItemRegistry.ITEM_FLINT_AND_STEEL:
		return
	var result := world.use_flint_and_steel(block_position, player.target_normal)
	if result.is_empty():
		set_status("Flint and steel needs a solid face to light")
		return
	if result.has("blocked"):
		set_status("Too wet to light" if result["blocked"] == "wet" else "Already burning")
		return
	if _game_mode == GameMode.SURVIVAL:
		inventory.wear_tool(selected_slot)
	_check_removed_containers()
	if int(result.get("ignited", 0)) > 0:
		AudioManager.play_block_place(BlockRegistry.BLOCK_FIRE, Vector3(block_position) + Vector3(0.5, 0.5, 0.5))
		set_status("Lit fire")
		return
	AudioManager.play_block_break(BlockRegistry.BLOCK_TNT, Vector3(block_position) + Vector3(0.5, 0.5, 0.5))
	set_status("Detonated %s · carved %d blocks" % [result["name"], result["removed"]])


func select_slot(index: int) -> void:
	if selected_slot != clampi(index, 0, ItemInventory.HOTBAR_SIZE - 1) and player != null:
		player.cancel_mining()
	selected_slot = clampi(index, 0, ItemInventory.HOTBAR_SIZE - 1)
	_update_slot_styles()
	if selected_slot < slot_panels.size():
		Motion.pulse(slot_panels[selected_slot])
	_update_inventory_display()


func can_place_selected() -> bool:
	return int(inventory.slots[selected_slot].get("count", 0)) > 0


func consume_selected_block() -> void:
	if _game_mode == GameMode.SURVIVAL:
		inventory.remove_at(selected_slot)


func _update_inventory_display() -> void:
	var registry := world.get_registry()
	for index in slot_icons.size():
		var stack := inventory.slots[index]
		var item_id := int(stack.get("id", 0))
		if item_id == 0:
			slot_icons[index].texture = null
		elif ItemRegistry.is_item(item_id):
			slot_icons[index].texture = ItemRegistry.make_icon(item_id, int(_hotbar_icon_size))
		elif registry != null:
			slot_icons[index].texture = BlockIcon.make_icon(registry, item_id, int(_hotbar_icon_size))
		slot_count_labels[index].text = str(stack.get("count", ""))
		if ItemRegistry.max_durability(item_id) > 0:
			slot_count_labels[index].text = "%d/%d" % [int(stack.get("durability", 0)), ItemRegistry.max_durability(item_id)]
	var selected := inventory.slots[selected_slot]
	var selected_id := int(selected.get("id", 0))
	player.set_selected_block(selected_id)
	if _selection_chip != null:
		_selection_chip.text = "%s · ×%d" % [
			_item_name(selected_id).to_lower(), selected.get("count", 0)]


func _item_name(item_id: int) -> String:
	if item_id == 0:
		return "Empty hand"
	if ItemRegistry.is_item(item_id):
		return ItemRegistry.get_item_name(item_id)
	return world.get_block_name(item_id)


func set_status(message: String) -> void:
	_status_label.text = message
	status_time = 3.5
	Motion.fade_in(_status_label)


## Startup/rebind toast for the core controls; called again when the pause
## menu's Settings close so a mid-game remap is reflected.
func _show_control_hint() -> void:
	var jump_hint := "double-tap %s to fly" if _game_mode == GameMode.CREATIVE else "%s jump"
	set_status("%s move   %s   %s inventory   %s map   %s minimap   ESC pause" % [
		GameConfig.input_move_hint(),
		jump_hint % GameConfig.input_key("jump"),
		GameConfig.input_key("inventory"),
		GameConfig.input_key("map_overlay"),
		GameConfig.input_key("minimap"),
	])


func _update_camera_far(render_distance: int) -> void:
	if player.camera:
		player.camera.far = maxf(500.0, float(render_distance) * float(VoxelDefs.CHUNK_SIZE) * 1.6 + 160.0)


func _update_stats() -> void:
	if not player:
		return
	var view := _active_camera()
	var camera_position := view.global_position if view != null else player.global_position
	var coords := Vector3i(floori(camera_position.x), floori(camera_position.y), floori(camera_position.z))
	var location_name := world.get_biome_name(camera_position)
	if _cave_amount > 0.35 and BiomeCatalog.is_cave_biome(_cave_biome):
		location_name = BiomeCatalog.cave_display_name(_cave_biome)
	_coords_label.text = "X %d   Y %d   Z %d\n%s" % [
		coords.x, coords.y, coords.z,
		location_name,
	]
	_stats_label.text = "%d FPS\n%d chunks\n%s" % [
		Engine.get_frames_per_second(),
		world.get_loaded_chunk_count(),
		_day_night.get_clock_text(),
	]
