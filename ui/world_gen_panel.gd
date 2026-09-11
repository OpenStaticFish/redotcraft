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
	})
