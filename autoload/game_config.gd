extends Node

const SETTINGS_PATH := "user://settings.cfg"

const DEFAULT_SETTINGS := {
	"render_distance": 10,
	"fov": 76.0,
	"mouse_sensitivity": 0.0022,
	"fullscreen": false,
	"graphics_preset": 1,
}

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
		"fsr_scale": 0.9,
		"msaa": 1,
	},
}

const DEFAULT_WORLD := {
	"seed": 0,
	"world_type": 0,
	"terrain_scale": 1.0,
	"tree_density": 1.0,
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


func get_fov() -> float:
	return float(settings.get("fov", DEFAULT_SETTINGS["fov"]))


func get_mouse_sensitivity() -> float:
	return float(settings.get("mouse_sensitivity", DEFAULT_SETTINGS["mouse_sensitivity"]))


func is_fullscreen() -> bool:
	return bool(settings.get("fullscreen", DEFAULT_SETTINGS["fullscreen"]))


func get_graphics_preset() -> int:
	return clampi(int(settings.get("graphics_preset", DEFAULT_SETTINGS["graphics_preset"])), 0, PRESET_NAMES.size() - 1)


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
	apply_window_mode()


func save_settings() -> void:
	var config := ConfigFile.new()
	for key in settings.keys():
		config.set_value("settings", key, settings[key])
	config.set_value("graphics", "values", graphics)
	config.save(SETTINGS_PATH)


func apply_window_mode() -> void:
	var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if is_fullscreen() else DisplayServer.WINDOW_MODE_WINDOWED
	DisplayServer.window_set_mode(mode)
