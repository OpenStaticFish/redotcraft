extends Node

const SETTINGS_PATH := "user://settings.cfg"

const DEFAULT_SETTINGS := {
	"render_distance": 10,
	"extreme_render_distance": false,
	"fov": 76.0,
	"mouse_sensitivity": 0.0022,
	"fullscreen": false,
	"graphics_preset": 1,
	"master_volume": 0.9,
	"sfx_volume": 1.0,
	"ambient_volume": 0.8,
	"vsync": 1,
	"fps_cap": 0,
	"dynamic_resolution": false,
	"dynamic_resolution_target": 60,
	"ui_scale": 1.0,
	"text_scale": 1.0,
}

# Interface scale. UI scale drives the window's canvas-item content scale, so
# the HUD and menus resize without touching the 3D render resolution; text
# scale is a font multiplier on top of the layout, independent of UI scale.
const UI_SCALE_VALUES := [0.75, 1.0, 1.25, 1.5, 2.0]
const UI_SCALE_NAMES := ["75%", "100%", "125%", "150%", "200%"]
const TEXT_SCALE_VALUES := [0.85, 1.0, 1.15, 1.3]
const TEXT_SCALE_NAMES := ["Small", "Default", "Large", "Larger"]

signal interface_scale_changed

# Frame pacing. VSync indexes mirror DisplayServer.VSyncMode exactly, and FPS
# cap values are real frame rates (`0` is unlimited), so the Display rows map
# option text to engine values through the parallel value tables.
const VSYNC_NAMES := ["Off", "On", "Adaptive", "Mailbox"]
const FPS_CAP_VALUES := [0, 30, 60, 90, 120, 144, 240]
const FPS_CAP_NAMES := ["Unlimited", "30 FPS", "60 FPS", "90 FPS", "120 FPS", "144 FPS", "240 FPS"]
const DYNAMIC_RESOLUTION_TARGET_VALUES := [30, 60, 90, 120, 144]
const DYNAMIC_RESOLUTION_TARGET_NAMES := ["30 FPS", "60 FPS", "90 FPS", "120 FPS", "144 FPS"]

const DYNAMIC_RESOLUTION_MIN_SCALE := 0.5
const DYNAMIC_RESOLUTION_STEP := 0.05
const DYNAMIC_RESOLUTION_DOWN_MARGIN := 1.05
const DYNAMIC_RESOLUTION_UP_MARGIN := 0.85

const PRESET_LOW := 0
const PRESET_MEDIUM := 1
const PRESET_HIGH := 2
const PRESET_NAMES := ["Low", "Medium", "High"]
const GRAPHICS_PRESETS := {
	PRESET_LOW: {
		"ssao_ssil": false,
		"sdfgi": false,
		"ssr": false,
		"volumetric_fog": false,
		"volumetric_fog_density": 0.0,
		"volumetric_fog_length": 96.0,
		"volumetric_fog_anisotropy": 0.2,
		"fog_density": 0.0006,
		"glow_intensity": 0.25,
		"tonemap": 3,
		"tonemap_exposure": 1.0,
		"saturation": 1.05,
		"contrast": 1.03,
		"shadow_max_distance": 120.0,
		"shadow_opacity": 0.9,
		"shadow_blur": 1.0,
		"soft_shadows": false,
		"taa": false,
		"fsr_scale": 0.66,
		"msaa": 0,
	},
	PRESET_MEDIUM: {
		"ssao_ssil": true,
		"sdfgi": false,
		"ssr": true,
		"volumetric_fog": true,
		"volumetric_fog_density": 0.006,
		"volumetric_fog_length": 128.0,
		"volumetric_fog_anisotropy": 0.2,
		"fog_density": 0.0009,
		"glow_intensity": 0.35,
		"tonemap": 3,
		"tonemap_exposure": 0.95,
		"saturation": 1.08,
		"contrast": 1.04,
		"shadow_max_distance": 200.0,
		"shadow_opacity": 0.9,
		"shadow_blur": 1.0,
		"soft_shadows": true,
		"taa": true,
		"fsr_scale": 0.77,
		"msaa": 1,
	},
	PRESET_HIGH: {
		"ssao_ssil": true,
		"sdfgi": false,
		"ssr": true,
		"volumetric_fog": true,
		"volumetric_fog_density": 0.01,
		"volumetric_fog_length": 160.0,
		"volumetric_fog_anisotropy": 0.25,
		"fog_density": 0.0012,
		"glow_intensity": 0.4,
		"tonemap": 3,
		"tonemap_exposure": 0.95,
		"saturation": 1.08,
		"contrast": 1.04,
		"shadow_max_distance": 320.0,
		"shadow_opacity": 0.95,
		"shadow_blur": 1.2,
		"soft_shadows": true,
		"taa": true,
		"fsr_scale": 0.9,
		"msaa": 1,
	},
}

const DEFAULT_WORLD := {
	"seed": 0,
	"world_type": 0,
	"terrain_scale": 1.0,
	"tree_density": 1.0,
	"worldgen_version": 6,
	"macro_scale": 384.0,
	"biome_scale": 3072.0,
	"river_density": 1.0,
	"erosion_strength": 0.55,
	"regional_erosion": 0.5,
	"hydraulic_erosion": false,
	"cave_density": 1.0,
	"decoration_density": 1.0,
}

var settings: Dictionary = DEFAULT_SETTINGS.duplicate()
var world: Dictionary = DEFAULT_WORLD.duplicate()
var graphics: Dictionary = {}


func _ready() -> void:
	load_settings()
	randomize_world()


func randomize_world() -> void:
	world["seed"] = randi() % 1000000000


func reset_world_defaults() -> void:
	for key in DEFAULT_WORLD.keys():
		world[key] = DEFAULT_WORLD[key]
	randomize_world()


func apply_world(config: Dictionary) -> void:
	for key in DEFAULT_WORLD.keys():
		world[key] = config.get(key, DEFAULT_WORLD[key])


func get_setting(key: String) -> Variant:
	return settings.get(key, DEFAULT_SETTINGS.get(key))


func set_setting(key: String, value: Variant) -> void:
	if not settings.has(key):
		return
	settings[key] = value
	if key == "graphics_preset":
		reset_graphics_to_preset()
	elif key == "vsync" or key == "fps_cap":
		apply_frame_pacing()
	elif key == "ui_scale" or key == "text_scale":
		apply_ui_scale()


## Applies the interface scale. The window's canvas-item content scale resizes
## the HUD and menus while leaving the 3D render resolution and the FSR scale
## alone, and the engine oversamples fonts by the same factor so text stays
## crisp. Text scale rides on top of that through UITheme. Emits
## `interface_scale_changed` so the live screens rebuild their theme, font
## sizes, and scale-sensitive layout.
func apply_ui_scale() -> void:
	var window := get_window()
	if window != null:
		window.content_scale_factor = get_ui_scale()
	interface_scale_changed.emit()


## Applies the pacing settings that the engine can hold at all times. Dynamic
## resolution is a gameplay-side controller because it reads the live viewport.
func apply_frame_pacing() -> void:
	DisplayServer.window_set_vsync_mode(get_vsync_mode())
	Engine.max_fps = maxi(int(settings.get("fps_cap", DEFAULT_SETTINGS["fps_cap"])), 0)


func get_vsync_mode() -> int:
	return clampi(int(settings.get("vsync", DEFAULT_SETTINGS["vsync"])), 0, VSYNC_NAMES.size() - 1)


## Snaps a persisted value to the nearest entry in its option table so the
## Display row and the applied engine value cannot disagree.
static func nearest_option(value: Variant, values: Array) -> Variant:
	var best: Variant = values[0]
	var best_distance := INF
	for candidate in values:
		var distance := absf(float(candidate) - float(value))
		if distance < best_distance:
			best_distance = distance
			best = candidate
	return best


## Pure dynamic-resolution policy: frame time above the target band steps the
## 3D render scale down, and clearly-under-budget time steps it back up toward
## the configured maximum. The budget is the slower of the FPS target and any
## hard cap (FPS cap or vsync refresh), so a capped frame is not read as GPU
## load. Kept static so the stepping stays verifiable without a rendering run.
static func dynamic_resolution_scale(current: float, frame_time: float, target_period: float, max_scale: float, cap_period: float = 0.0) -> float:
	var ceiling := clampf(max_scale, DYNAMIC_RESOLUTION_MIN_SCALE, 1.0)
	var budget := maxf(target_period, cap_period)
	var scale := clampf(current, DYNAMIC_RESOLUTION_MIN_SCALE, ceiling)
	if frame_time > budget * DYNAMIC_RESOLUTION_DOWN_MARGIN:
		scale = maxf(scale - DYNAMIC_RESOLUTION_STEP, DYNAMIC_RESOLUTION_MIN_SCALE)
	elif frame_time < budget * DYNAMIC_RESOLUTION_UP_MARGIN:
		scale = minf(scale + DYNAMIC_RESOLUTION_STEP, ceiling)
	return clampf(scale, DYNAMIC_RESOLUTION_MIN_SCALE, ceiling)


func reset_graphics_to_preset() -> void:
	graphics = GRAPHICS_PRESETS[get_graphics_preset()].duplicate()


func set_graphics_value(key: String, value: Variant) -> void:
	if graphics.has(key):
		graphics[key] = value


func is_graphics_custom() -> bool:
	var preset: Dictionary = GRAPHICS_PRESETS[get_graphics_preset()]
	for key in preset.keys():
		if graphics.get(key) != preset[key]:
			return true
	return false


func get_render_distance() -> int:
	return int(settings.get("render_distance", DEFAULT_SETTINGS["render_distance"]))


func get_ui_scale() -> float:
	return clampf(float(settings.get("ui_scale", DEFAULT_SETTINGS["ui_scale"])),
		UI_SCALE_VALUES[0], UI_SCALE_VALUES[UI_SCALE_VALUES.size() - 1])


func get_text_scale() -> float:
	return clampf(float(settings.get("text_scale", DEFAULT_SETTINGS["text_scale"])),
		TEXT_SCALE_VALUES[0], TEXT_SCALE_VALUES[TEXT_SCALE_VALUES.size() - 1])


func get_fov() -> float:
	return float(settings.get("fov", DEFAULT_SETTINGS["fov"]))


func get_mouse_sensitivity() -> float:
	return float(settings.get("mouse_sensitivity", DEFAULT_SETTINGS["mouse_sensitivity"]))


func is_fullscreen() -> bool:
	return bool(settings.get("fullscreen", DEFAULT_SETTINGS["fullscreen"]))


func get_graphics_preset() -> int:
	return clampi(int(settings.get("graphics_preset", DEFAULT_SETTINGS["graphics_preset"])), 0, PRESET_NAMES.size() - 1)


func get_audio_volume(key: String) -> float:
	return clampf(float(settings.get(key, 1.0)), 0.0, 1.0)


func get_graphics() -> Dictionary:
	return graphics


func get_world_seed() -> int:
	return int(world.get("seed", DEFAULT_WORLD["seed"]))


func get_world_type() -> int:
	return int(world.get("world_type", DEFAULT_WORLD["world_type"]))


func get_terrain_scale() -> float:
	return float(world.get("terrain_scale", DEFAULT_WORLD["terrain_scale"]))


func get_tree_density() -> float:
	return float(world.get("tree_density", DEFAULT_WORLD["tree_density"]))


func load_settings() -> void:
	var config := ConfigFile.new()
	reset_graphics_to_preset()
	if config.load(SETTINGS_PATH) == OK:
		for key in DEFAULT_SETTINGS.keys():
			settings[key] = config.get_value("settings", key, settings[key])
		reset_graphics_to_preset()
		var saved: Dictionary = config.get_value("graphics", "values", {})
		for key in saved.keys():
			if graphics.has(key):
				graphics[key] = saved[key]
	settings["fps_cap"] = nearest_option(settings.get("fps_cap", DEFAULT_SETTINGS["fps_cap"]), FPS_CAP_VALUES)
	settings["dynamic_resolution_target"] = nearest_option(settings.get("dynamic_resolution_target", DEFAULT_SETTINGS["dynamic_resolution_target"]), DYNAMIC_RESOLUTION_TARGET_VALUES)
	settings["ui_scale"] = nearest_option(settings.get("ui_scale", DEFAULT_SETTINGS["ui_scale"]), UI_SCALE_VALUES)
	settings["text_scale"] = nearest_option(settings.get("text_scale", DEFAULT_SETTINGS["text_scale"]), TEXT_SCALE_VALUES)
	apply_window_mode()
	apply_frame_pacing()
	apply_ui_scale()


func save_settings() -> void:
	var config := ConfigFile.new()
	for key in settings.keys():
		config.set_value("settings", key, settings[key])
	config.set_value("graphics", "values", graphics)
	config.save(SETTINGS_PATH)


func apply_window_mode() -> void:
	var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if is_fullscreen() else DisplayServer.WINDOW_MODE_WINDOWED
	DisplayServer.window_set_mode(mode)
