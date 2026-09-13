class_name WorldGenPanel
extends Control

signal create_world(config: Dictionary)
signal closed

const WORLD_TYPES := ["Normal", "Flat", "Amplified"]

@onready var _panel: PanelContainer = $Center/Panel
@onready var _heading: Label = $Center/Panel/Box/Heading
@onready var _hint: Label = $Center/Panel/Box/Hint
@onready var _seed_field: LineEdit = $Center/Panel/Box/SeedRow/SeedField
@onready var _type_option: OptionButton = $Center/Panel/Box/TypeRow/TypeOption
@onready var _reroll_button: Button = $Center/Panel/Box/SeedRow/RandomSeedButton
@onready var _rows_box: VBoxContainer = $Center/Panel/Box/RowsBox
@onready var _back_button: Button = $Center/Panel/Box/Footer/BackButton
@onready var _create_button: Button = $Center/Panel/Box/Footer/CreateButton
@onready var _dim: ColorRect = $Dim

var _terrain_slider: HSlider
var _trees_slider: HSlider
var _macro_slider: HSlider
var _biome_slider: HSlider
var _rivers_slider: HSlider
var _erosion_slider: HSlider
var _regional_erosion_slider: HSlider
var _hydraulic_toggle: CheckButton
var _caves_slider: HSlider
var _decoration_slider: HSlider


func _ready() -> void:
	theme = UITheme.build()
	_style_static()
	for type_name in WORLD_TYPES:
		_type_option.add_item(type_name)
	_reroll_button.pressed.connect(func() -> void:
		_seed_field.text = str(randi() % 1000000000)
	)
	_type_option.item_selected.connect(_on_type_selected)
	_back_button.pressed.connect(close_panel)
	_create_button.pressed.connect(_on_create)
	_seed_field.text_submitted.connect(func(_text: String) -> void: _on_create())
	_wrap_rows_in_scroll()

	var terrain := _section("TERRAIN")
	_terrain_slider = UITheme.slider_row(
		terrain, "Terrain Scale", 0.5, 2.0, 0.05,
		GameConfig.get_terrain_scale(), "%d%%", 100.0)
	_macro_slider = UITheme.slider_row(
		terrain, "Landmass Scale", 192.0, 1024.0, 32.0,
		float(GameConfig.world.get("macro_scale", 384.0)), "%d blocks", 1.0)
	_biome_slider = UITheme.slider_row(
		terrain, "Biome Scale", 384.0, 2048.0, 64.0,
		float(GameConfig.world.get("biome_scale", 896.0)), "%d blocks", 1.0)

	var water := _section("WATER & EROSION")
	_rivers_slider = UITheme.slider_row(
		water, "River Density", 0.0, 2.0, 0.05,
		float(GameConfig.world.get("river_density", 1.0)), "%d%%", 100.0)
	_erosion_slider = UITheme.slider_row(
		water, "Slope Erosion", 0.0, 1.0, 0.05,
		float(GameConfig.world.get("erosion_strength", 0.55)), "%d%%", 100.0)
	_regional_erosion_slider = UITheme.slider_row(
		water, "Regional Erosion", 0.0, 1.0, 0.05,
		float(GameConfig.world.get("regional_erosion", 0.5)), "%d%%", 100.0)
	_hydraulic_toggle = _inline_toggle(
		water, "Hydraulic Erosion", "High quality (slower)",
		bool(GameConfig.world.get("hydraulic_erosion", false)))

	var features := _section("FEATURES")
	_trees_slider = UITheme.slider_row(
		features, "Tree Density", 0.0, 2.0, 0.05,
		GameConfig.get_tree_density(), "%d%%", 100.0)
	_caves_slider = UITheme.slider_row(
		features, "Cave Density", 0.0, 2.0, 0.05,
		float(GameConfig.world.get("cave_density", 1.0)), "%d%%", 100.0)
	_decoration_slider = UITheme.slider_row(
		features, "Ground Cover", 0.0, 2.0, 0.05,
		float(GameConfig.world.get("decoration_density", 1.0)), "%d%%", 100.0)
	_on_type_selected(_type_option.selected)


func _wrap_rows_in_scroll() -> void:
	var box := _rows_box.get_parent() as VBoxContainer
	var rows_index := _rows_box.get_index()
	var scroll := ScrollContainer.new()
	scroll.name = "WorldOptionsScroll"
	scroll.custom_minimum_size = Vector2(0, 390)
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	box.move_child(scroll, rows_index)
	_rows_box.reparent(scroll)
	_rows_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL


func _style_static() -> void:
	_dim.color = Color(UITheme.VOID.r, UITheme.VOID.g, UITheme.VOID.b, 0.68)
	_panel.add_theme_stylebox_override("panel", UITheme.modal_style())
	_heading.text = "Create World"
	_heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_heading.add_theme_font_override("font", UITheme.font_display())
	_heading.add_theme_font_size_override("font_size", UITheme.SIZE_DISPLAY)
	_heading.add_theme_color_override("font_color", UITheme.INK)
	var box := _heading.get_parent() as VBoxContainer
	var eyebrow := UITheme.eyebrow("World Gen")
	box.add_child(eyebrow)
	box.move_child(eyebrow, 0)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_hint.add_theme_color_override("font_color", UITheme.MUTED)
	_hint.text = "Nothing is saved yet — every world starts fresh."
	UITheme.style_button_ghost(_reroll_button)
	UITheme.style_button_ghost(_back_button)
	UITheme.style_button_primary(_create_button)
	_style_seed_row()
	_style_type_row()


func _style_seed_row() -> void:
	var row := _seed_field.get_parent() as HBoxContainer
	var label := row.get_node("SeedLabel") as Label
	label.custom_minimum_size = Vector2(160.0, 0.0)
	label.add_theme_font_override("font", UITheme.font_semi())
	_reroll_button.text = "Random"


func _style_type_row() -> void:
	var row := _type_option.get_parent() as HBoxContainer
	var label := row.get_node("TypeLabel") as Label
	label.custom_minimum_size = Vector2(160.0, 0.0)
	label.add_theme_font_override("font", UITheme.font_semi())


func _section(title: String) -> VBoxContainer:
	if not _rows_box.get_children().is_empty():
		var spacer := Control.new()
		spacer.custom_minimum_size = Vector2(0, 6)
		_rows_box.add_child(spacer)
		_rows_box.add_child(UITheme.divider())
		var after := Control.new()
		after.custom_minimum_size = Vector2(0, 6)
		_rows_box.add_child(after)
	var wrap := VBoxContainer.new()
	wrap.add_theme_constant_override("separation", 8)
	wrap.add_child(UITheme.eyebrow(title))
	_rows_box.add_child(wrap)
	var group := VBoxContainer.new()
	group.add_theme_constant_override("separation", 9)
	wrap.add_child(group)
	return group


func _inline_toggle(box: VBoxContainer, label_text: String, toggle_text: String, pressed: bool) -> CheckButton:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	box.add_child(row)
	var label := Label.new()
	label.custom_minimum_size = Vector2(160.0, 0.0)
	label.text = label_text
	label.add_theme_font_override("font", UITheme.font_semi())
	row.add_child(label)
	var toggle := CheckButton.new()
	toggle.text = toggle_text
	toggle.button_pressed = pressed
	row.add_child(toggle)
	return toggle


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close_panel()
		get_viewport().set_input_as_handled()


func open_panel() -> void:
	_panel.custom_minimum_size.x = minf(620.0, get_viewport().get_visible_rect().size.x - 48.0)
	_seed_field.text = str(GameConfig.get_world_seed())
	_type_option.selected = clampi(GameConfig.get_world_type(), 0, WORLD_TYPES.size() - 1)
	_on_type_selected(_type_option.selected)
	visible = true
	Motion.dim_in(_dim)
	Motion.pop_in(_panel)
	_seed_field.grab_focus()


func close_panel() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


func _on_type_selected(index: int) -> void:
	# Flat worlds have no terrain knobs — every tunable lives in RowsBox.
	_rows_box.visible = index != 1


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
		"biome_scale": snappedf(_biome_slider.value, 64.0),
		"river_density": snappedf(_rivers_slider.value, 0.05),
		"erosion_strength": snappedf(_erosion_slider.value, 0.05),
		"regional_erosion": snappedf(_regional_erosion_slider.value, 0.05),
		"hydraulic_erosion": _hydraulic_toggle.button_pressed,
		"cave_density": snappedf(_caves_slider.value, 0.05),
		"decoration_density": snappedf(_decoration_slider.value, 0.05),
	})
