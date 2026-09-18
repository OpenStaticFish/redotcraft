class_name CraftingRecipes
extends RefCounted

## Shapeless counts; table-only recipes require the caller's nearby-table check.
## Each definition has id, ingredients (item ID -> count), output, count, table, category.
const B = preload("res://world/block_registry.gd")
const I = preload("res://game/item_registry.gd")
const RECIPES := [
	{"id": "planks_oak", "ingredients": {B.BLOCK_LOG: 1}, "output": B.BLOCK_PLANKS, "count": 4, "table": false, "category": "Basics"},
	{"id": "planks_spruce", "ingredients": {B.BLOCK_SPRUCE_LOG: 1}, "output": B.BLOCK_PLANKS, "count": 4, "table": false, "category": "Basics"},
	{"id": "planks_birch", "ingredients": {B.BLOCK_BIRCH_LOG: 1}, "output": B.BLOCK_PLANKS, "count": 4, "table": false, "category": "Basics"},
	{"id": "planks_acacia", "ingredients": {B.BLOCK_ACACIA_LOG: 1}, "output": B.BLOCK_PLANKS, "count": 4, "table": false, "category": "Basics"},
	{"id": "planks_jungle", "ingredients": {B.BLOCK_JUNGLE_LOG: 1}, "output": B.BLOCK_PLANKS, "count": 4, "table": false, "category": "Basics"},
	{"id": "planks_mangrove", "ingredients": {B.BLOCK_MANGROVE_LOG: 1}, "output": B.BLOCK_PLANKS, "count": 4, "table": false, "category": "Basics"},
	{"id": "sticks", "ingredients": {B.BLOCK_PLANKS: 2}, "output": I.ITEM_STICK, "count": 4, "table": false, "category": "Basics"},
	{"id": "bamboo_sticks", "ingredients": {B.BLOCK_BAMBOO: 2}, "output": I.ITEM_STICK, "count": 1, "table": false, "category": "Basics"},
	{"id": "crafting_table", "ingredients": {B.BLOCK_PLANKS: 4}, "output": B.BLOCK_CRAFTING_TABLE, "count": 1, "table": false, "category": "Basics"},
	{"id": "chest", "ingredients": {B.BLOCK_PLANKS: 8}, "output": B.BLOCK_CHEST, "count": 1, "table": true, "category": "Storage"},
	{"id": "furnace", "ingredients": {B.BLOCK_COBBLESTONE: 8}, "output": B.BLOCK_FURNACE, "count": 1, "table": true, "category": "Basics"},
	{"id": "wood_pickaxe", "ingredients": {B.BLOCK_PLANKS: 3, I.ITEM_STICK: 2}, "output": I.ITEM_WOOD_PICKAXE, "count": 1, "table": true, "category": "Tools"},
	{"id": "wood_axe", "ingredients": {B.BLOCK_PLANKS: 3, I.ITEM_STICK: 2}, "output": I.ITEM_WOOD_AXE, "count": 1, "table": true, "category": "Tools"},
	{"id": "wood_shovel", "ingredients": {B.BLOCK_PLANKS: 1, I.ITEM_STICK: 2}, "output": I.ITEM_WOOD_SHOVEL, "count": 1, "table": true, "category": "Tools"},
	{"id": "stone_pickaxe", "ingredients": {B.BLOCK_COBBLESTONE: 3, I.ITEM_STICK: 2}, "output": I.ITEM_STONE_PICKAXE, "count": 1, "table": true, "category": "Tools"},
	{"id": "stone_axe", "ingredients": {B.BLOCK_COBBLESTONE: 3, I.ITEM_STICK: 2}, "output": I.ITEM_STONE_AXE, "count": 1, "table": true, "category": "Tools"},
	{"id": "stone_shovel", "ingredients": {B.BLOCK_COBBLESTONE: 1, I.ITEM_STICK: 2}, "output": I.ITEM_STONE_SHOVEL, "count": 1, "table": true, "category": "Tools"},
	{"id": "iron_pickaxe", "ingredients": {I.ITEM_IRON_INGOT: 3, I.ITEM_STICK: 2}, "output": I.ITEM_IRON_PICKAXE, "count": 1, "table": true, "category": "Tools"},
	{"id": "iron_axe", "ingredients": {I.ITEM_IRON_INGOT: 3, I.ITEM_STICK: 2}, "output": I.ITEM_IRON_AXE, "count": 1, "table": true, "category": "Tools"},
	{"id": "iron_shovel", "ingredients": {I.ITEM_IRON_INGOT: 1, I.ITEM_STICK: 2}, "output": I.ITEM_IRON_SHOVEL, "count": 1, "table": true, "category": "Tools"},
	{"id": "torches", "ingredients": {I.ITEM_COAL: 1, I.ITEM_STICK: 1}, "output": B.BLOCK_TORCH, "count": 4, "table": false, "category": "Lighting"},
	{"id": "charcoal_torches", "ingredients": {I.ITEM_CHARCOAL: 1, I.ITEM_STICK: 1}, "output": B.BLOCK_TORCH, "count": 4, "table": false, "category": "Lighting"},
	{"id": "flint", "ingredients": {B.BLOCK_GRAVEL: 1}, "output": I.ITEM_FLINT, "count": 1, "table": false, "category": "Basics", "description": "Knap gravel into flint."},
	{"id": "flint_and_steel", "ingredients": {I.ITEM_FLINT: 1, I.ITEM_IRON_INGOT: 1}, "output": I.ITEM_FLINT_AND_STEEL, "count": 1, "table": true, "category": "Tools"},
	{"id": "bowls", "ingredients": {B.BLOCK_PLANKS: 3}, "output": I.ITEM_BOWL, "count": 4, "table": false, "category": "Food"},
	{"id": "mushroom_stew", "ingredients": {I.ITEM_BOWL: 1, B.BLOCK_BROWN_MUSHROOM: 1, B.BLOCK_RED_MUSHROOM: 1}, "output": I.ITEM_MUSHROOM_STEW, "count": 1, "table": false, "category": "Food"},
	{"id": "melon_slices", "ingredients": {B.BLOCK_MELON: 1}, "output": I.ITEM_MELON_SLICE, "count": 4, "table": false, "category": "Food"},
	{"id": "melon", "ingredients": {I.ITEM_MELON_SLICE: 4}, "output": B.BLOCK_MELON, "count": 1, "table": false, "category": "Building"},
	{"id": "deepstone_cobblestone", "ingredients": {B.BLOCK_DEEPSTONE: 1}, "output": B.BLOCK_COBBLESTONE, "count": 1, "table": false, "category": "Building"},
]

## Input ID -> output ID. One input and ten seconds produce one output.
const SMELTING := {
	B.BLOCK_IRON_ORE: I.ITEM_IRON_INGOT, B.BLOCK_GOLD_ORE: I.ITEM_GOLD_INGOT,
	B.BLOCK_COAL_ORE: I.ITEM_COAL, B.BLOCK_COBBLESTONE: B.BLOCK_STONE,
	B.BLOCK_LOG: I.ITEM_CHARCOAL, B.BLOCK_SPRUCE_LOG: I.ITEM_CHARCOAL,
	B.BLOCK_BIRCH_LOG: I.ITEM_CHARCOAL, B.BLOCK_ACACIA_LOG: I.ITEM_CHARCOAL,
	B.BLOCK_JUNGLE_LOG: I.ITEM_CHARCOAL, B.BLOCK_MANGROVE_LOG: I.ITEM_CHARCOAL,
	B.BLOCK_SAND: B.BLOCK_GLASS, B.BLOCK_RED_SAND: B.BLOCK_GLASS,
	B.BLOCK_CLAY: B.BLOCK_TERRACOTTA, B.BLOCK_KELP: I.ITEM_DRIED_KELP,
	I.ITEM_RAW_MEAT: I.ITEM_COOKED_MEAT,
}
const SMELT_SECONDS := 10.0


static func get_recipe(recipe_id: String) -> Dictionary:
	for recipe in RECIPES:
		if recipe.id == recipe_id:
			return recipe
	return {}


static func craft(inventory: ItemInventory, recipe_id: String, at_table: bool, batches: int = 1) -> bool:
	var trial := _craft_trial(inventory, get_recipe(recipe_id), at_table, batches)
	if trial == null:
		return false
	inventory.restore(trial.persistent_state())
	return true


static func _craft_trial(inventory: ItemInventory, recipe: Dictionary, at_table: bool, batches: int) -> ItemInventory:
	if recipe.is_empty() or batches <= 0 or (recipe.table and not at_table):
		return null
	for id in recipe.ingredients:
		# Divide before multiplying to reject oversized requests without overflow.
		if batches > inventory.count_item(id) / int(recipe.ingredients[id]):
			return null
	var trial := ItemInventory.new(inventory.slots.size())
	trial.restore(inventory.persistent_state())
	for id in recipe.ingredients:
		var remaining: int = int(recipe.ingredients[id]) * batches
		for index in trial.slots.size():
			if trial.slots[index].get("id", 0) != id or remaining == 0:
				continue
			var amount := mini(remaining, int(trial.slots[index].count))
			trial.remove_at(index, amount)
			remaining -= amount
	if trial.add_item(recipe.output, int(recipe.count) * batches) != 0:
		return null
	return trial


static func max_craftable(inventory: ItemInventory, recipe_id: String, at_table: bool) -> int:
	var recipe := get_recipe(recipe_id)
	if recipe.is_empty() or (recipe.table and not at_table):
		return 0
	var limit := 64
	for id in recipe.ingredients:
		limit = mini(limit, inventory.count_item(id) / int(recipe.ingredients[id]))
	# Capacity is not monotonic: a larger batch may empty an ingredient slot.
	for batches in range(limit, 0, -1):
		if _craft_trial(inventory, recipe, at_table, batches) != null:
			return batches
	return 0


static func blocking_reason(inventory: ItemInventory, recipe_id: String, at_table: bool) -> String:
	var recipe := get_recipe(recipe_id)
	if recipe.is_empty():
		return "Unknown recipe"
	if recipe.table and not at_table:
		return "Requires a crafting table"
	var missing: PackedStringArray = []
	for id in recipe.ingredients:
		var needed: int = int(recipe.ingredients[id]) - inventory.count_item(id)
		if needed > 0:
			var label: String = I.get_item_name(id) if I.is_item(id) else B.BLOCK_DEFS[id][1]
			missing.append("%d %s" % [needed, label.to_lower()])
	if not missing.is_empty():
		return "Missing: " + ", ".join(missing)
	if _craft_trial(inventory, recipe, at_table, 1) == null:
		return "Inventory full: make room for the output"
	return ""
