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
	var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if settings["fullscreen"] else DisplayServer.WINDOW_MODE_WINDOWED
	DisplayServer.window_set_mode(mode)
