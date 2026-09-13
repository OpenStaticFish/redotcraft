class_name WorldGenPanel
extends Control

signal create_world(config: Dictionary)
signal closed

const WORLD_TYPES := ["Normal", "Flat", "Amplified"]

@onready var _seed_field: LineEdit = $Center/Panel/Box/SeedRow/SeedField
@onready var _type_option: OptionButton = $Center/Panel/Box/TypeRow/TypeOption
@onready var _reroll_button: Button = $Center/Panel/Box/SeedRow/RandomSeedButton
@onready var _rows_box: VBoxContainer = $Center/Panel/Box/RowsBox
@onready var _back_button: Button = $Center/Panel/Box/Footer/BackButton
@onready var _create_button: Button = $Center/Panel/Box/Footer/CreateButton

var _terrain_slider: HSlider
var _trees_slider: HSlider
var _macro_slider: HSlider
var _rivers_slider: HSlider
var _erosion_slider: HSlider
var _regional_erosion_slider: HSlider
var _hydraulic_toggle: CheckButton
var _caves_slider: HSlider
var _decoration_slider: HSlider


func _ready() -> void:
	theme = UITheme.build()
	for type_name in WORLD_TYPES:
		_type_option.add_item(type_name)
	_reroll_button.pressed.connect(func() -> void:
		_seed_field.text = str(randi() % 1000000000)
	)
	_type_option.item_selected.connect(_on_type_selected)
	_back_button.pressed.connect(close_panel)
	_create_button.pressed.connect(_on_create)
	_terrain_slider = UITheme.slider_row(
		_rows_box, "Terrain Scale", 0.5, 2.0, 0.05,
		GameConfig.get_terrain_scale(), "%d%%", 100.0)
	_trees_slider = UITheme.slider_row(
		_rows_box, "Tree Density", 0.0, 2.0, 0.05,
		GameConfig.get_tree_density(), "%d%%", 100.0)
	_macro_slider = UITheme.slider_row(
		_rows_box, "Landmass Scale", 192.0, 1024.0, 32.0,
		float(GameConfig.world.get("macro_scale", 384.0)), "%d blocks", 1.0)
	_rivers_slider = UITheme.slider_row(
		_rows_box, "River Density", 0.0, 2.0, 0.05,
		float(GameConfig.world.get("river_density", 1.0)), "%d%%", 100.0)
	_erosion_slider = UITheme.slider_row(
		_rows_box, "Slope Erosion", 0.0, 1.0, 0.05,
		float(GameConfig.world.get("erosion_strength", 0.55)), "%d%%", 100.0)
	_regional_erosion_slider = UITheme.slider_row(
		_rows_box, "Regional Erosion", 0.0, 1.0, 0.05,
		float(GameConfig.world.get("regional_erosion", 0.5)), "%d%%", 100.0)
	var hydraulic_row := HBoxContainer.new()
	hydraulic_row.add_theme_constant_override("separation", 12)
	_rows_box.add_child(hydraulic_row)
	var hydraulic_label := Label.new()
	hydraulic_label.custom_minimum_size = Vector2(200, 0)
	hydraulic_label.text = "Hydraulic Erosion"
	hydraulic_row.add_child(hydraulic_label)
	_hydraulic_toggle = CheckButton.new()
	_hydraulic_toggle.text = "High quality (slower)"
	_hydraulic_toggle.button_pressed = bool(GameConfig.world.get("hydraulic_erosion", false))
	hydraulic_row.add_child(_hydraulic_toggle)
	_caves_slider = UITheme.slider_row(
		_rows_box, "Cave Density", 0.0, 2.0, 0.05,
		float(GameConfig.world.get("cave_density", 1.0)), "%d%%", 100.0)
	_decoration_slider = UITheme.slider_row(
		_rows_box, "Ground Cover", 0.0, 2.0, 0.05,
		float(GameConfig.world.get("decoration_density", 1.0)), "%d%%", 100.0)
	_on_type_selected(_type_option.selected)


func open_panel() -> void:
	_seed_field.text = str(GameConfig.get_world_seed())
	_type_option.selected = clampi(GameConfig.get_world_type(), 0, WORLD_TYPES.size() - 1)
	_on_type_selected(_type_option.selected)
	visible = true
	_seed_field.grab_focus()


func close_panel() -> void:
	visible = false
	closed.emit()


func _on_type_selected(index: int) -> void:
	var flat := index == 1
	(_terrain_slider.get_parent() as Control).visible = not flat
	(_trees_slider.get_parent() as Control).visible = not flat
	(_macro_slider.get_parent() as Control).visible = not flat
	(_rivers_slider.get_parent() as Control).visible = not flat
	(_erosion_slider.get_parent() as Control).visible = not flat
	(_regional_erosion_slider.get_parent() as Control).visible = not flat
	(_hydraulic_toggle.get_parent() as Control).visible = not flat
	(_caves_slider.get_parent() as Control).visible = not flat
	(_decoration_slider.get_parent() as Control).visible = not flat


func _on_create() -> void:
	var seed_text := _seed_field.text.strip_edges()
	var seed_value := 0
	if seed_text.is_valid_int():
		seed_value = int(seed_text)
	elif not seed_text.is_empty():
		seed_value = seed_text.hash() & 0x7FFFFFFF
	else:
		seed_value = randi() % 1000000000
	create_world.emit({
		"seed": seed_value,
		"world_type": _type_option.selected,
		"terrain_scale": snappedf(_terrain_slider.value, 0.05),
		"tree_density": snappedf(_trees_slider.value, 0.05),
		"worldgen_version": WorldGenConfig.CURRENT_VERSION,
		"macro_scale": snappedf(_macro_slider.value, 32.0),
		"river_density": snappedf(_rivers_slider.value, 0.05),
		"erosion_strength": snappedf(_erosion_slider.value, 0.05),
		"regional_erosion": snappedf(_regional_erosion_slider.value, 0.05),
		"hydraulic_erosion": _hydraulic_toggle.button_pressed,
		"cave_density": snappedf(_caves_slider.value, 0.05),
		"decoration_density": snappedf(_decoration_slider.value, 0.05),
	})
