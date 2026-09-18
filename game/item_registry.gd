class_name ItemRegistry
extends RefCounted

## Item IDs live outside the byte-sized block namespace. This keeps tools from
## ever entering chunk data while allowing the existing inventory dictionary
## and hotbar to carry blocks and items together.
const ITEM_FLINT_AND_STEEL := 1000
const ITEM_WOOD_PICKAXE := 1001
const ITEM_WOOD_AXE := 1002
const ITEM_WOOD_SHOVEL := 1003
const ITEM_STONE_PICKAXE := 1004
const ITEM_STONE_AXE := 1005
const ITEM_STONE_SHOVEL := 1006
const ITEM_IRON_PICKAXE := 1007
const ITEM_IRON_AXE := 1008
const ITEM_IRON_SHOVEL := 1009
const ITEM_STICK := 1010
const ITEM_COAL := 1011
const ITEM_IRON_INGOT := 1012
const ITEM_RAW_MEAT := 1013
const ITEM_COOKED_MEAT := 1014
const ITEM_DRIED_KELP := 1015
const ITEM_GOLD_INGOT := 1016
const ITEM_CHARCOAL := 1017
const ITEM_BOWL := 1018
const ITEM_MUSHROOM_STEW := 1019
const ITEM_MELON_SLICE := 1020
const ITEM_FLINT := 1021

const ITEM_NAMES := [
	"FLINT AND STEEL", "WOOD PICKAXE", "WOOD AXE", "WOOD SHOVEL",
	"STONE PICKAXE", "STONE AXE", "STONE SHOVEL",
	"IRON PICKAXE", "IRON AXE", "IRON SHOVEL", "STICK", "COAL",
	"IRON INGOT", "RAW MEAT", "COOKED MEAT", "DRIED KELP", "GOLD INGOT",
	"CHARCOAL", "BOWL", "MUSHROOM STEW", "MELON SLICE", "FLINT",
]

static var _icon_cache: Dictionary = {}


static func is_item(item_id: int) -> bool:
	return item_id >= ITEM_FLINT_AND_STEEL and item_id <= ITEM_FLINT


static func is_valid(item_id: int) -> bool:
	return is_item(item_id) or BlockRegistry.is_inventory_block(item_id)


static func tool_kind(item_id: int) -> String:
	if item_id < ITEM_WOOD_PICKAXE or item_id > ITEM_IRON_SHOVEL:
		return ""
	return ["pickaxe", "axe", "shovel"][(item_id - ITEM_WOOD_PICKAXE) % 3]


static func tool_tier(item_id: int) -> int:
	if tool_kind(item_id).is_empty():
		return 0
	return 1 + (item_id - ITEM_WOOD_PICKAXE) / 3


static func max_durability(item_id: int) -> int:
	if item_id == ITEM_FLINT_AND_STEEL:
		return 64
	return [0, 59, 131, 250][tool_tier(item_id)]


static func stack_limit(item_id: int) -> int:
	if not is_valid(item_id):
		return 0
	return 1 if max_durability(item_id) > 0 else 64


static func food_value(item_id: int) -> float:
	match item_id:
		ITEM_RAW_MEAT:
			return 3.0
		ITEM_COOKED_MEAT:
			return 8.0
		ITEM_DRIED_KELP:
			return 1.0
		ITEM_MUSHROOM_STEW:
			return 6.0
		ITEM_MELON_SLICE:
			return 2.0
	return 0.0


static func fuel_seconds(item_id: int) -> float:
	match item_id:
		ITEM_COAL, ITEM_CHARCOAL:
			return 80.0
		ITEM_STICK:
			return 5.0
		ITEM_WOOD_PICKAXE, ITEM_WOOD_AXE, ITEM_WOOD_SHOVEL, BlockRegistry.BLOCK_PLANKS:
			return 15.0
		BlockRegistry.BLOCK_LOG, BlockRegistry.BLOCK_SPRUCE_LOG, BlockRegistry.BLOCK_BIRCH_LOG, BlockRegistry.BLOCK_ACACIA_LOG, BlockRegistry.BLOCK_JUNGLE_LOG, BlockRegistry.BLOCK_MANGROVE_LOG:
			return 15.0
	return 0.0


static func harvest_drop(block_id: int) -> Dictionary:
	match block_id:
		BlockRegistry.BLOCK_FIRE:
			return {}
		BlockRegistry.BLOCK_STONE:
			return {"id": BlockRegistry.BLOCK_COBBLESTONE, "count": 1}
		BlockRegistry.BLOCK_COAL_ORE:
			return {"id": ITEM_COAL, "count": 1}
	return {"id": BlockRegistry.canonical_id(block_id), "count": 1}


static func get_item_name(item_id: int) -> String:
	if is_item(item_id):
		return ITEM_NAMES[item_id - ITEM_FLINT_AND_STEEL]
	return "UNKNOWN ITEM"


static func make_icon(item_id: int, size: int = 48) -> Texture2D:
	if not is_item(item_id):
		return null
	var key := "%d@%d" % [item_id, size]
	if _icon_cache.has(key):
		return _icon_cache[key]
	if item_id != ITEM_FLINT_AND_STEEL:
		var glyph := Image.create(16, 16, false, Image.FORMAT_RGBA8)
		glyph.fill(Color.TRANSPARENT)
		var kind := tool_kind(item_id)
		var color := Color("b9c5c9")
		if not kind.is_empty() or item_id == ITEM_STICK:
			glyph.fill_rect(Rect2i(7, 3, 2, 11), Color("906139"))
			if not kind.is_empty():
				color = [Color("906139"), Color("899096"), color][tool_tier(item_id) - 1]
				var tool_head := Rect2i(3, 2, 10, 3)
				if kind == "axe":
					tool_head = Rect2i(3, 2, 6, 6)
				elif kind == "shovel":
					tool_head = Rect2i(5, 2, 6, 5)
				glyph.fill_rect(tool_head, color)
		else:
			match item_id:
				ITEM_COAL, ITEM_CHARCOAL: color = Color("343b42")
				ITEM_BOWL: color = Color("906139")
				ITEM_MUSHROOM_STEW: color = Color("bc8151")
				ITEM_MELON_SLICE: color = Color("dc615c")
				ITEM_FLINT: color = Color("59646e")
				ITEM_GOLD_INGOT: color = Color("e9bb45")
				ITEM_RAW_MEAT: color = Color("cd6464")
				ITEM_COOKED_MEAT: color = Color("985b39")
				ITEM_DRIED_KELP: color = Color("4c7144")
			glyph.fill_rect(Rect2i(3, 5, 10, 7), color.darkened(0.3))
			glyph.fill_rect(Rect2i(4, 4, 8, 6), color)
		glyph.resize(size, size, Image.INTERPOLATE_NEAREST)
		_icon_cache[key] = ImageTexture.create_from_image(glyph)
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
