class_name PlayPanel
extends Control

## World setup screen: pick a type and seed (or import one), then create. The
## detailed terrain/hydrology knobs live behind Advanced in WorldGenPanel.

signal closed
signal advanced_requested
signal create_requested(seed: int, world_type: int)

const WORLD_TYPES := ["Normal", "Flat", "Amplified"]

@onready var _panel: PanelContainer = $Center/Panel
@onready var _heading: Label = $Center/Panel/Box/Heading
@onready var _type_option: OptionButton = $Center/Panel/Box/TypeRow/TypeOption
@onready var _seed_field: LineEdit = $Center/Panel/Box/SeedRow/SeedField
@onready var _import_button: Button = $Center/Panel/Box/SeedRow/ImportButton
@onready var _random_button: Button = $Center/Panel/Box/SeedRow/RandomSeedButton
@onready var _advanced_button: Button = $Center/Panel/Box/Footer/AdvancedButton
@onready var _back_button: Button = $Center/Panel/Box/Footer/BackButton
@onready var _create_button: Button = $Center/Panel/Box/Footer/CreateButton
@onready var _dim: ColorRect = $Dim


func _ready() -> void:
	UITheme.apply(self)
	_style_static()
	for type_name in WORLD_TYPES:
		_type_option.add_item(type_name)
	_random_button.pressed.connect(func() -> void:
		_seed_field.text = str(randi() % 1000000000)
	)
	_import_button.pressed.connect(_on_import)
	_advanced_button.pressed.connect(func() -> void: advanced_requested.emit())
	_back_button.pressed.connect(close_panel)
	_create_button.pressed.connect(_on_create)
	_seed_field.text_submitted.connect(func(_text: String) -> void: _on_create())


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close_panel()
		get_viewport().set_input_as_handled()


func open_panel() -> void:
	_panel.custom_minimum_size.x = minf(560.0, get_viewport().get_visible_rect().size.x - 48.0)
	_seed_field.text = str(GameConfig.get_world_seed())
	_type_option.selected = clampi(GameConfig.get_world_type(), 0, WORLD_TYPES.size() - 1)
	visible = true
	Motion.dim_in(_dim)
	Motion.pop_in(_panel)
	_seed_field.grab_focus()


func close_panel() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


func focus_advanced() -> void:
	if visible:
		_advanced_button.grab_focus()


func _style_static() -> void:
	_dim.color = Color(UITheme.VOID.r, UITheme.VOID.g, UITheme.VOID.b, 0.68)
	_panel.add_theme_stylebox_override("panel", UITheme.modal_style())
	_heading.text = "Create World"
	_heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	UITheme.style_heading(_heading)
	var box := _heading.get_parent() as VBoxContainer
	var eyebrow := UITheme.eyebrow("Play")
	box.add_child(eyebrow)
	box.move_child(eyebrow, 0)
	_style_row_label($Center/Panel/Box/TypeRow/TypeLabel as Label, "World Type")
	_style_row_label($Center/Panel/Box/SeedRow/SeedLabel as Label, "Seed")
	_import_button.tooltip_text = "Paste a seed from the clipboard"
	UITheme.style_button_ghost(_import_button)
	UITheme.style_button_ghost(_random_button)
	UITheme.style_button_ghost(_advanced_button)
	UITheme.style_button_ghost(_back_button)
	UITheme.style_button_primary(_create_button)


func _style_row_label(label: Label, text: String) -> void:
	label.text = text
	label.custom_minimum_size = Vector2(160.0, 0.0)
	label.add_theme_font_override("font", UITheme.font_semi())


func _on_import() -> void:
	var text := DisplayServer.clipboard_get().strip_edges()
	if not text.is_empty():
		_seed_field.text = text
		_seed_field.caret_column = text.length()


func _on_create() -> void:
	var seed_text := _seed_field.text.strip_edges()
	var seed_value := 0
	if seed_text.is_valid_int():
		seed_value = int(seed_text)
	elif not seed_text.is_empty():
		seed_value = seed_text.hash() & 0x7FFFFFFF
	else:
		seed_value = randi() % 1000000000
	create_requested.emit(seed_value, _type_option.selected)
