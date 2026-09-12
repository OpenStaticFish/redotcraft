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
@onready var _time_row: HBoxContainer = $Center/Panel/Box/TimeRow
@onready var _grid: GridContainer = $Center/Panel/Box/Grid
@onready var _weather_button: Button = $Center/Panel/Box/WeatherRow/WeatherButton


func _ready() -> void:
	_panel.theme = UITheme.build()
	for entry in TIME_BUTTONS:
		var button := _time_row.get_node(entry["node"]) as Button
		button.pressed.connect(_on_time_button.bind(entry["hours"]))
	_weather_button.pressed.connect(_on_weather_button)


func _unhandled_input(event: InputEvent) -> void:
	if visible:
		if event.is_action_pressed("inventory") or event.is_action_pressed("ui_cancel"):
			close_panel()
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed("inventory"):
		open_panel()
		get_viewport().set_input_as_handled()


func open_panel() -> void:
	visible = true
	opened.emit()


func close_panel() -> void:
	visible = false
	closed.emit()


func show_inventory(inventory_data: Dictionary, world_ref: VoxelWorld) -> void:
	for child in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()
	var ids: Array = inventory_data.keys()
	ids.sort()
	for id in ids:
		var slot := PanelContainer.new()
		slot.custom_minimum_size = Vector2(120.0, 64.0)
		_grid.add_child(slot)
		var label := Label.new()
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 14)
		label.text = "%s\nx%d" % [world_ref.get_block_name(int(id)), int(inventory_data[id])]
		slot.add_child(label)


func set_weather_state(raining: bool) -> void:
	_weather_button.text = "Weather: Rain" if raining else "Weather: Sunny"


func _on_time_button(hours: float) -> void:
	time_selected.emit(hours)


func _on_weather_button() -> void:
	weather_toggled.emit()
