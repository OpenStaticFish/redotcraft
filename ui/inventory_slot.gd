class_name InventorySlot
extends Button

## Dragging never takes ownership of items. Only a validated drop mutates data.
var inventory: ItemInventory
var slot_index := 0
var overlay: InventoryOverlay
var caption := ""
var _icon: TextureRect
var _count: Label
var _caption: Label
var _item_id := -1
var selected := false:
	set(value):
		selected = value
		queue_redraw()


func _ready() -> void:
	custom_minimum_size = Vector2(64, 72)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.style_button_flat(self)
	add_theme_stylebox_override("normal", UITheme.panel_style(UITheme.SURFACE_LOW, UITheme.LINE, 1, 6))
	_icon = TextureRect.new()
	_icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_icon.offset_left = 10
	_icon.offset_right = -10
	_icon.offset_top = 14
	_icon.offset_bottom = -14
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_icon)
	_count = UITheme.value_label()
	add_child(_count)
	_count.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_count.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_count.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_count.offset_left = -40
	_count.offset_right = -6
	_count.offset_top = -24
	_count.offset_bottom = -4
	_count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_caption = UITheme.muted_label(caption, 11)
	_caption.position = Vector2(5, 2)
	_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_caption)
	pressed.connect(func() -> void: overlay.activate_slot(self))
	refresh()


func refresh() -> void:
	if not is_node_ready():
		return
	var stack: Dictionary = inventory.slots[slot_index]
	var item_id := int(stack.get("id", -1))
	if item_id != _item_id:
		_item_id = item_id
		_icon.texture = overlay.item_icon(item_id) if item_id >= 0 else null
	_count.text = str(stack.get("count", 0)) if not stack.is_empty() else ""
	tooltip_text = caption + (" - " if not caption.is_empty() else "")
	tooltip_text += "%s x%d" % [overlay.item_name(item_id), int(stack.get("count", 0))] if item_id >= 0 else "Empty"
	if item_id >= 0 and ItemRegistry.max_durability(item_id) > 0:
		tooltip_text += "\nDurability: %d" % int(stack["durability"])
	button_pressed = false
	queue_redraw()


func _draw() -> void:
	if selected:
		draw_style_box(get_theme_stylebox("focus"), Rect2(Vector2.ZERO, size))


func _get_drag_data(_at_position: Vector2) -> Variant:
	var data := overlay.drag_data(self, Input.is_key_pressed(KEY_SHIFT))
	if data.is_empty():
		return null
	var preview := Label.new()
	preview.text = "%s x%d" % [overlay.item_name(int(data["stack"]["id"])), int(data["amount"])]
	UITheme.apply(preview)
	set_drag_preview(preview)
	return data


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return overlay.can_drop(self, data)


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	overlay.drop_stack(self, data)
