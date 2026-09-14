class_name ItemRegistry
extends RefCounted

## Item IDs live outside the byte-sized block namespace. This keeps tools from
## ever entering chunk data while allowing the existing inventory dictionary
## and hotbar to carry blocks and items together.
const ITEM_FLINT_AND_STEEL := 1000

static var _icon_cache: Dictionary = {}


static func is_item(item_id: int) -> bool:
	return item_id == ITEM_FLINT_AND_STEEL


static func get_item_name(item_id: int) -> String:
	if item_id == ITEM_FLINT_AND_STEEL:
		return "FLINT AND STEEL"
	return "UNKNOWN ITEM"


static func make_icon(item_id: int, size: int = 48) -> Texture2D:
	if item_id != ITEM_FLINT_AND_STEEL:
		return null
	var key := "%d@%d" % [item_id, size]
	if _icon_cache.has(key):
		return _icon_cache[key]
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	var scale := float(size) / 48.0
	# A chunky, readable C-shaped steel striker with a warm flint spark.
	_fill_rect(image, Rect2i(roundi(8 * scale), roundi(8 * scale), roundi(9 * scale), roundi(30 * scale)), Color("#b9c5c9"))
	_fill_rect(image, Rect2i(roundi(14 * scale), roundi(30 * scale), roundi(22 * scale), roundi(8 * scale)), Color("#829096"))
	_fill_rect(image, Rect2i(roundi(14 * scale), roundi(8 * scale), roundi(18 * scale), roundi(7 * scale)), Color("#d9e0df"))
	_fill_rect(image, Rect2i(roundi(25 * scale), roundi(17 * scale), roundi(12 * scale), roundi(11 * scale)), Color("#273239"))
	_fill_rect(image, Rect2i(roundi(34 * scale), roundi(9 * scale), roundi(5 * scale), roundi(5 * scale)), Color("#ffb347"))
	_fill_rect(image, Rect2i(roundi(39 * scale), roundi(4 * scale), roundi(4 * scale), roundi(4 * scale)), Color("#ffe08a"))
	var texture := ImageTexture.create_from_image(image)
	_icon_cache[key] = texture
	return texture


static func _fill_rect(image: Image, rect: Rect2i, color: Color) -> void:
	image.fill_rect(rect.intersection(Rect2i(Vector2i.ZERO, image.get_size())), color)
