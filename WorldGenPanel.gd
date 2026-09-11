extends Control

const UI := preload("res://UITheme.gd")

signal create_world(config: Dictionary)
signal closed

const WORLD_TYPES := ["Normal", "Flat", "Amplified"]

var _seed_field: LineEdit
var _type_option: OptionButton
var _terrain_slider: HSlider
var _trees_slider: HSlider


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = UI.build()

	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.0, 0.02, 0.03, 0.62)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(580.0, 0.0)
	center.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)
	box.add_child(UI.heading("WORLD GEN", 30))
	box.add_child(UI.muted_label("Create a new world. Nothing is saved yet."))

	var seed_row := HBoxContainer.new()
	seed_row.add_theme_constant_override("separation", 12)
	box.add_child(seed_row)
	var seed_label := Label.new()
	seed_label.text = "Seed"
	seed_label.custom_minimum_size = Vector2(200.0, 0.0)
	seed_row.add_child(seed_label)
	_seed_field = LineEdit.new()
	_seed_field.text = str(GameConfig.world["seed"])
	_seed_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	seed_row.add_child(_seed_field)
	var reroll := Button.new()
	reroll.text = "Random"
	reroll.pressed.connect(func() -> void:
		_seed_field.text = str(randi() % 1000000000)
	)
	seed_row.add_child(reroll)

	var type_row := HBoxContainer.new()
	type_row.add_theme_constant_override("separation", 12)
	box.add_child(type_row)
	var type_label := Label.new()
	type_label.text = "World Type"
	type_label.custom_minimum_size = Vector2(200.0, 0.0)
	type_row.add_child(type_label)
	_type_option = OptionButton.new()
	for name in WORLD_TYPES:
		_type_option.add_item(name)
	_type_option.selected = clampi(int(GameConfig.world["world_type"]), 0, WORLD_TYPES.size() - 1)
	_type_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_type_option.item_selected.connect(_on_type_selected)
	type_row.add_child(_type_option)

	_terrain_slider = _make_slider_row(box, "Terrain Scale", 0.5, 2.0, 0.05, float(GameConfig.world["terrain_scale"]), "%d%%", 100.0)
	_trees_slider = _make_slider_row(box, "Tree Density", 0.0, 2.0, 0.05, float(GameConfig.world["tree_density"]), "%d%%", 100.0)

	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_END
	footer.add_theme_constant_override("separation", 10)
	box.add_child(footer)
	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(140.0, 0.0)
	back.pressed.connect(close_panel)
	footer.add_child(back)
	var create := Button.new()
	create.text = "Create World"
	create.custom_minimum_size = Vector2(210.0, 0.0)
	create.pressed.connect(_on_create)
	footer.add_child(create)

	_on_type_selected(_type_option.selected)
	visible = false


func open_panel() -> void:
	_seed_field.text = str(GameConfig.world["seed"])
	_type_option.selected = clampi(int(GameConfig.world["world_type"]), 0, WORLD_TYPES.size() - 1)
	_on_type_selected(_type_option.selected)
	visible = true
	_seed_field.grab_focus()


func close_panel() -> void:
	visible = false
	closed.emit()


func _make_slider_row(box: VBoxContainer, label_text: String, minimum: float, maximum: float, step: float, value: float, format: String, display_scale: float) -> HSlider:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	var name_label := Label.new()
	name_label.text = label_text
	name_label.custom_minimum_size = Vector2(200.0, 0.0)
	row.add_child(name_label)
	var slider := HSlider.new()
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = step
	slider.value = value
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size = Vector2(220.0, 0.0)
	row.add_child(slider)
	var value_label := Label.new()
	value_label.custom_minimum_size = Vector2(90.0, 0.0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.add_theme_color_override("font_color", UI.TEAL)
	value_label.text = format % roundi(slider.value * display_scale)
	row.add_child(value_label)
	slider.value_changed.connect(func(new_value: float) -> void:
		value_label.text = format % roundi(new_value * display_scale)
	)
	return slider


func _on_type_selected(index: int) -> void:
	var flat := index == 1
	(_terrain_slider.get_parent() as HBoxContainer).visible = not flat
	(_trees_slider.get_parent() as HBoxContainer).visible = not flat


func _on_create() -> void:
	var seed_text := _seed_field.text.strip_edges()
	var seed_value := 0
	if seed_text.is_valid_int():
		seed_value = int(seed_text)
	else:
		seed_value = randi() % 1000000000
	create_world.emit({
		"seed": seed_value,
		"world_type": _type_option.selected,
		"terrain_scale": snappedf(float(_terrain_slider.value), 0.05),
		"tree_density": snappedf(float(_trees_slider.value), 0.05),
	})
