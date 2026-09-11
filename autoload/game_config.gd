extends Node

const SETTINGS_PATH := "user://settings.cfg"

const DEFAULT_SETTINGS := {
	"render_distance": 10,
	"fov": 76.0,
	"mouse_sensitivity": 0.0022,
	"fullscreen": false,
	"ambient_occlusion": true,
	"global_illumination": true,
}

const DEFAULT_WORLD := {
	"seed": 0,
	"world_type": 0,
	"terrain_scale": 1.0,
	"tree_density": 1.0,
}

var settings: Dictionary = DEFAULT_SETTINGS.duplicate()
var world: Dictionary = DEFAULT_WORLD.duplicate()


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
	if settings.has(key):
		settings[key] = value


func get_render_distance() -> int:
	return int(settings.get("render_distance", DEFAULT_SETTINGS["render_distance"]))


func get_fov() -> float:
	return float(settings.get("fov", DEFAULT_SETTINGS["fov"]))


func get_mouse_sensitivity() -> float:
	return float(settings.get("mouse_sensitivity", DEFAULT_SETTINGS["mouse_sensitivity"]))


func is_fullscreen() -> bool:
	return bool(settings.get("fullscreen", DEFAULT_SETTINGS["fullscreen"]))


func get_ambient_occlusion() -> bool:
	return bool(settings.get("ambient_occlusion", DEFAULT_SETTINGS["ambient_occlusion"]))


func get_global_illumination() -> bool:
	return bool(settings.get("global_illumination", DEFAULT_SETTINGS["global_illumination"]))


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
	if config.load(SETTINGS_PATH) == OK:
		for key in DEFAULT_SETTINGS.keys():
			settings[key] = config.get_value("settings", key, settings[key])
	apply_window_mode()


func save_settings() -> void:
	var config := ConfigFile.new()
	for key in settings.keys():
		config.set_value("settings", key, settings[key])
	config.save(SETTINGS_PATH)


func apply_window_mode() -> void:
	var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if is_fullscreen() else DisplayServer.WINDOW_MODE_WINDOWED
	DisplayServer.window_set_mode(mode)
