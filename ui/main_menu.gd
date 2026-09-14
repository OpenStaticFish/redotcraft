class_name MainMenu
extends Control

## Title screen. The .tscn only provides the skeleton (background, column,
## buttons, footer); everything visual is composed here so the scene file
## stays untouched: dusk gradient, drifting voxel clouds, a stepped skyline
## silhouette, and the wordmark treatment.

const SKY_STOPS := [
	[0.00, Color("#121a22")],
	[0.40, Color("#1d2a33")],
	[0.62, Color("#31404a")],
	[0.76, Color("#4a4438")],
	[0.85, Color("#8a6238")],
	[0.90, Color("#b5824a")],
	[0.94, Color("#241d15")],
	[1.00, Color("#0a0d10")],
]
const CLOUD_TINT := Color("#d9e2e8")
const SKYLINE_COLOR := Color("#0a0e12")
const SKYLINE_RIM := Color("#1c2833")
const SKYLINE_SEED := 7
const SKYLINE_COLUMN := 26.0
const DRIFT_WRAP_MARGIN := 320.0

@onready var _play_panel: PlayPanel = $PlayPanel
@onready var _settings_menu: SettingsMenu = $SettingsMenu
@onready var _world_gen_panel: WorldGenPanel = $WorldGenPanel
@onready var _background: TextureRect = $Background
@onready var _title: Label = $Center/Column/Title
@onready var _subtitle: Label = $Center/Column/Subtitle
@onready var _footer: Label = $Footer

var _clouds: Array[Control] = []
var _cloud_speeds: Array[float] = []
var _panel_focus_return: Control


func _ready() -> void:
	theme = UITheme.build()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_restyle_background()
	var mode := OS.get_environment("RC_UI_TEST")
	if mode != "nobg" and mode != "sky" and mode != "vignette":
		_build_clouds()
	if mode != "nobg" and mode != "clouds" and mode != "vignette":
		_build_skyline()
	_restyle_wordmark()
	_restyle_buttons()
	_restyle_footer()
	$Center/Column/PlayButton.pressed.connect(_on_play)
	$Center/Column/SettingsButton.pressed.connect(_on_settings)
	$Center/Column/QuitButton.pressed.connect(_on_quit)
	_play_panel.closed.connect(_on_panel_closed)
	_play_panel.advanced_requested.connect(_on_play_advanced)
	_play_panel.create_requested.connect(_on_create_world)
	_settings_menu.closed.connect(_on_panel_closed)
	_world_gen_panel.closed.connect(_on_world_gen_closed)
	$Center/Column/PlayButton.grab_focus()


func _process(delta: float) -> void:
	var width := size.x
	for index in _clouds.size():
		var cloud := _clouds[index]
		cloud.position.x += _cloud_speeds[index] * delta
		if cloud.position.x > width + DRIFT_WRAP_MARGIN:
			cloud.position.x = -DRIFT_WRAP_MARGIN


func _restyle_background() -> void:
	var gradient := Gradient.new()
	for index in SKY_STOPS.size():
		gradient.add_point(SKY_STOPS[index][0], SKY_STOPS[index][1])
	var texture := _background.texture as GradientTexture2D
	if texture != null:
		texture.gradient = gradient
	var vignette := TextureRect.new()
	vignette.name = "Vignette"
	vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vignette.texture = _make_vignette_texture(256)
	vignette.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	vignette.stretch_mode = TextureRect.STRETCH_SCALE
	var mode := OS.get_environment("RC_UI_TEST")
	if mode == "nobg" or mode == "clouds" or mode == "sky":
		return
	add_child(vignette)
	move_child(vignette, _background.get_index() + 1)


## Radial alpha ramp baked pixel-by-pixel; GradientTexture2D's transparent
## stops rendered opaque on some drivers, so the vignette is a real RGBA image.
static func _make_vignette_texture(res: int) -> ImageTexture:
	var image := Image.create(res, res, false, Image.FORMAT_RGBA8)
	var center := Vector2(res, res) * 0.5
	var inner := res * 0.42
	var outer := res * 0.74
	var edge := Color(UITheme.VOID.r, UITheme.VOID.g, UITheme.VOID.b, 0.0)
	for y in res:
		for x in res:
			var distance := Vector2(x + 0.5, y + 0.5).distance_to(center)
			var weight := clampf((distance - inner) / maxf(outer - inner, 1.0), 0.0, 1.0)
			edge.a = weight * 0.5
			image.set_pixel(x, y, edge)
	return ImageTexture.create_from_image(image)


func _build_clouds() -> void:
	# Replace the flat placeholder rects with layered voxel-cloud clusters.
	for name_suffix in range(1, 6):
		var placeholder := get_node_or_null("Cloud%d" % name_suffix)
		if placeholder != null:
			placeholder.queue_free()
	var random := RandomNumberGenerator.new()
	random.seed = 3
	for index in range(8):
		var depth := float(index) / 7.0
		var cloud := Control.new()
		cloud.name = "VoxelCloud%d" % index
		cloud.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var base_y := lerpf(28.0, 210.0, random.randf())
		cloud.position = Vector2(random.randf_range(-240.0, 1480.0), base_y)
		var puffs := random.randi_range(3, 6)
		for puff in puffs:
			var rect := ColorRect.new()
			var extent := Vector2(random.randi_range(2, 6), random.randi_range(1, 2)) * 14.0
			rect.size = extent
			rect.position = Vector2(puff * random.randf_range(10.0, 16.0), random.randf_range(-8.0, 8.0))
			rect.color = Color(CLOUD_TINT.r, CLOUD_TINT.g, CLOUD_TINT.b, random.randf_range(0.045, 0.11) * (1.0 - depth * 0.4))
			rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
			cloud.add_child(rect)
		_clouds.append(cloud)
		_cloud_speeds.append(lerpf(5.0, 16.0, random.randf()))
		add_child(cloud)
		move_child(cloud, _background.get_index() + 1)


func _build_skyline() -> void:
	# Stepped silhouette along the bottom edge — a voxel horizon.
	var random := RandomNumberGenerator.new()
	random.seed = SKYLINE_SEED
	var skyline := Control.new()
	skyline.name = "Skyline"
	skyline.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	skyline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(skyline)
	move_child(skyline, _background.get_index() + 1)
	var height := 0.0
	var count := int(ceil(1480.0 / SKYLINE_COLUMN))
	for index in count:
		height = clampf(height + random.randf_range(-26.0, 30.0), 42.0, 150.0)
		var column := ColorRect.new()
		column.color = SKYLINE_COLOR
		column.size = Vector2(SKYLINE_COLUMN + 1.0, height)
		column.position = Vector2(SKYLINE_COLUMN * float(index), -height)
		column.mouse_filter = Control.MOUSE_FILTER_IGNORE
		skyline.add_child(column)
		if random.randf() < 0.35:
			var rim := ColorRect.new()
			rim.color = Color(SKYLINE_RIM.r, SKYLINE_RIM.g, SKYLINE_RIM.b, 0.9)
			rim.size = Vector2(SKYLINE_COLUMN * 0.6, 3.0)
			rim.position = Vector2(SKYLINE_COLUMN * float(index), -height)
			rim.mouse_filter = Control.MOUSE_FILTER_IGNORE
			skyline.add_child(rim)


func _restyle_wordmark() -> void:
	var column := _title.get_parent() as VBoxContainer
	var wordmark := FontVariation.new()
	wordmark.base_font = UITheme.font_wordmark()
	wordmark.spacing_glyph = 4
	_title.add_theme_font_override("font", wordmark)
	_title.add_theme_font_size_override("font_size", 52)
	_title.add_theme_color_override("font_color", UITheme.INK)
	_title.add_theme_color_override("font_shadow_color", Color(0.01, 0.03, 0.05, 0.8))
	_title.add_theme_constant_override("shadow_offset_x", 3)
	_title.add_theme_constant_override("shadow_offset_y", 4)

	var underline_wrapper := CenterContainer.new()
	var underline := ColorRect.new()
	underline.color = UITheme.EMBER
	underline.custom_minimum_size = Vector2(210.0, 3.0)
	underline_wrapper.add_child(underline)
	column.add_child(underline_wrapper)
	column.move_child(underline_wrapper, _title.get_index() + 1)

	_subtitle.add_theme_font_override("font", UITheme.font_eyebrow())
	_subtitle.add_theme_font_size_override("font_size", 13)
	_subtitle.add_theme_color_override("font_color", UITheme.MUTED)

	Motion.pop_in(_title, 0.3)


func _restyle_buttons() -> void:
	var column := _title.get_parent()
	UITheme.style_button_primary(column.get_node("PlayButton"))
	UITheme.style_button_ghost(column.get_node("SettingsButton"))
	UITheme.style_button_ghost(column.get_node("QuitButton"))
	Motion.stagger_in([
		column.get_node("PlayButton"),
		column.get_node("SettingsButton"),
		column.get_node("QuitButton"),
	])


func _restyle_footer() -> void:
	_footer.add_theme_color_override("font_color", UITheme.FAINT)
	_footer.add_theme_font_size_override("font_size", 13)
	_footer.text = "WASD move · SPACE jump · double-tap SPACE fly · E inventory · F1 HUD · F2 screenshot · P photo camera · M map · ] minimap · F3 worldgen map · ESC pause"


func _on_panel_closed() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if _panel_focus_return != null and is_instance_valid(_panel_focus_return):
		_panel_focus_return.grab_focus()


func _on_play() -> void:
	_panel_focus_return = $Center/Column/PlayButton
	_play_panel.open_panel()


func _on_settings() -> void:
	_panel_focus_return = $Center/Column/SettingsButton
	_settings_menu.open_panel()


func _on_play_advanced() -> void:
	_world_gen_panel.open_panel()


func _on_world_gen_closed() -> void:
	# The advanced screen is only reachable from the play screen, which stays
	# open underneath, so focus returns to the button that opened it.
	if _play_panel.visible:
		_play_panel.focus_advanced()


func _on_create_world(seed: int, world_type: int) -> void:
	var config := _world_gen_panel.build_config()
	config["seed"] = seed
	config["world_type"] = world_type
	GameConfig.apply_world(config)
	_start_game()


func _start_game() -> void:
	get_tree().change_scene_to_file("res://game/main.tscn")


func _on_quit() -> void:
	GameConfig.save_settings()
	get_tree().quit()
