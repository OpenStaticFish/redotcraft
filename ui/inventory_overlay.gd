class_name InventoryOverlay
extends CanvasLayer

signal opened
signal closed
signal time_selected(hours: float)
signal weather_toggled

const TIME_BUTTONS := [
	{"node": "MorningButton", "hours": 6.0},
	{"node": "DayButton", "hours": 12.0},
	{"node": "EveningButton", "hours": 18.0},
	{"node": "NightButton", "hours": 0.0},
]

@onready var _panel: PanelContainer = $Center/Panel
@onready var _heading: Label = $Center/Panel/Box/Heading
@onready var _time_row: HBoxContainer = $Center/Panel/Box/TimeRow
@onready var _weather_row: HBoxContainer = $Center/Panel/Box/WeatherRow
@onready var _grid: GridContainer = $Center/Panel/Box/Grid
@onready var _weather_button: Button = $Center/Panel/Box/WeatherRow/WeatherButton
@onready var _hint: Label = $Center/Panel/Box/Hint
@onready var _dim: ColorRect = $Dim

var _slot_width := 180.0


func _ready() -> void:
	_panel.theme = UITheme.build()
	_style_static()
	for entry in TIME_BUTTONS:
		var button := _time_row.get_node(entry["node"]) as Button
		button.pressed.connect(_on_time_button.bind(entry["hours"]))
	_weather_button.pressed.connect(_on_weather_button)


func _style_static() -> void:
	_dim.color = Color(UITheme.VOID.r, UITheme.VOID.g, UITheme.VOID.b, 0.62)
	_panel.add_theme_stylebox_override("panel", UITheme.modal_style())
	_heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_heading.add_theme_font_override("font", UITheme.font_display())
	_heading.add_theme_font_size_override("font_size", UITheme.SIZE_DISPLAY)
	_heading.add_theme_color_override("font_color", UITheme.INK)
	var box := _heading.get_parent() as VBoxContainer
	var eyebrow := UITheme.eyebrow("Supplies")
	box.add_child(eyebrow)
	box.move_child(eyebrow, 0)

	# Wrap the centered time row in a segmented strip and left-align it.
	var strip := PanelContainer.new()
	strip.add_theme_stylebox_override("panel", UITheme.panel_style(
		Color(UITheme.SURFACE_HI.r, UITheme.SURFACE_HI.g, UITheme.SURFACE_HI.b, 0.5), UITheme.LINE, 1, 8))
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var time_index := _time_row.get_index()
	_time_row.reparent(strip)
	box.add_child(strip)
	var time_eyebrow := UITheme.eyebrow("Set Time")
	box.add_child(time_eyebrow)
	box.move_child(time_eyebrow, time_index)
	box.move_child(strip, time_index + 1)
	_time_row.alignment = BoxContainer.ALIGNMENT_BEGIN
	_time_row.add_theme_constant_override("separation", 4)
	for entry in TIME_BUTTONS:
		var button := _time_row.get_node(entry["node"]) as Button
		UITheme.style_button_flat(button)
		button.custom_minimum_size = Vector2(108.0, 34.0)

	var weather_eyebrow := UITheme.eyebrow("Weather")
	box.add_child(weather_eyebrow)
	box.move_child(weather_eyebrow, _weather_row.get_index())
	_weather_row.alignment = BoxContainer.ALIGNMENT_BEGIN
	UITheme.style_button_ghost(_weather_button)
	_weather_button.custom_minimum_size = Vector2(240.0, 38.0)

	_grid.columns = 4
	_grid.add_theme_constant_override("h_separation", 8)
	_grid.add_theme_constant_override("v_separation", 8)
	_hint.add_theme_color_override("font_color", UITheme.MUTED)
	_hint.add_theme_font_size_override("font_size", 13)


func _unhandled_input(event: InputEvent) -> void:
	if visible:
		if event.is_action_pressed("inventory") or event.is_action_pressed("ui_cancel"):
			close_panel()
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed("inventory"):
		open_panel()
		get_viewport().set_input_as_handled()


func open_panel() -> void:
	_apply_responsive_layout()
	visible = true
	Motion.dim_in(_dim)
	Motion.pop_in(_panel)
	opened.emit()
	(_time_row.get_node("MorningButton") as Button).grab_focus()


func _apply_responsive_layout() -> void:
	var viewport_width := get_viewport().get_visible_rect().size.x
	if viewport_width < 680.0:
		_grid.columns = 2
		_slot_width = 160.0
	elif viewport_width < 940.0:
		_grid.columns = 3
		_slot_width = 180.0
	else:
		_grid.columns = 4
		_slot_width = 180.0
	_panel.custom_minimum_size.x = minf(780.0, viewport_width - 48.0)


func close_panel() -> void:
	visible = false
	closed.emit()


func show_inventory(inventory_data: Dictionary, world_ref: VoxelWorld) -> void:
	for child in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()
	var ids: Array = inventory_data.keys()
	ids.sort()
	if ids.is_empty():
		_grid.add_child(UITheme.muted_label("Nothing collected yet — mine some blocks.", 14))
		return
	var registry: BlockRegistry = world_ref.get_registry() if world_ref != null and world_ref.has_method("get_registry") else null
	for id in ids:
		_grid.add_child(_make_slot(int(id), int(inventory_data[id]), world_ref, registry))


func set_weather_state(raining: bool) -> void:
	_weather_button.text = "Weather · Rain" if raining else "Weather · Sunny"


func _make_slot(block_id: int, count: int, world_ref: VoxelWorld, registry: BlockRegistry) -> PanelContainer:
	var slot := PanelContainer.new()
	slot.custom_minimum_size = Vector2(_slot_width, 68.0)
	var style := UITheme.panel_style(
		Color(UITheme.SURFACE_HI.r, UITheme.SURFACE_HI.g, UITheme.SURFACE_HI.b, 0.42),
		UITheme.LINE, 1, 8)
	style.content_margin_left = 10.0
	style.content_margin_right = 10.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	slot.add_theme_stylebox_override("panel", style)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	slot.add_child(row)

	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(50.0, 50.0)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if registry != null:
		icon.texture = BlockIcon.make_icon(registry, block_id, 50)
	row.add_child(icon)

	var text := VBoxContainer.new()
	text.add_theme_constant_override("separation", 2)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text)
	var name_label := Label.new()
	name_label.text = world_ref.get_block_name(block_id).to_lower()
	name_label.add_theme_font_override("font", UITheme.font_semi())
	name_label.add_theme_font_size_override("font_size", 13)
	name_label.add_theme_color_override("font_color", UITheme.INK)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_child(name_label)
	var count_label := Label.new()
	count_label.text = "×%d" % count
	count_label.add_theme_font_override("font", UITheme.font_semi())
	count_label.add_theme_font_size_override("font_size", 14)
	count_label.add_theme_color_override("font_color", UITheme.CYAN)
	text.add_child(count_label)
	return slot


func _on_time_button(hours: float) -> void:
	time_selected.emit(hours)


func _on_weather_button() -> void:
	weather_toggled.emit()
