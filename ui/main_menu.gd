class_name MainMenu
extends Control

@onready var _settings_panel: SettingsPanel = $SettingsPanel
@onready var _world_gen_panel: WorldGenPanel = $WorldGenPanel


func _ready() -> void:
	theme = UITheme.build()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	$Center/Column/PlayButton.pressed.connect(_on_play)
	$Center/Column/WorldGenButton.pressed.connect(_on_world_gen)
	$Center/Column/SettingsButton.pressed.connect(_on_settings)
	$Center/Column/QuitButton.pressed.connect(_on_quit)
	_settings_panel.closed.connect(_on_panel_closed)
	_world_gen_panel.closed.connect(_on_panel_closed)
	_world_gen_panel.create_world.connect(_on_create_world)


func _on_panel_closed() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _on_play() -> void:
	GameConfig.reset_world_defaults()
	_start_game()


func _on_world_gen() -> void:
	_world_gen_panel.open_panel()


func _on_settings() -> void:
	_settings_panel.open_panel()


func _on_create_world(config: Dictionary) -> void:
	GameConfig.apply_world(config)
	_start_game()


func _start_game() -> void:
	get_tree().change_scene_to_file("res://game/main.tscn")


func _on_quit() -> void:
	GameConfig.save_settings()
	get_tree().quit()
