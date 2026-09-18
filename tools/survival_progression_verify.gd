## redot --headless --path . --script res://tools/survival_progression_verify.gd
## No starter supplies or injected recipe outputs: each species starts empty.
extends SceneTree

const B = preload("res://world/block_registry.gd")
const I = preload("res://game/item_registry.gd")
const TABLE := Vector3i(7, 1, 4)
const FURNACE := Vector3i(7, 1, 6)
const MINE := Vector3i(4, 2, 4)
const SPECIES := {
	"oak": B.BLOCK_LOG, "spruce": B.BLOCK_SPRUCE_LOG,
	"birch": B.BLOCK_BIRCH_LOG, "acacia": B.BLOCK_ACACIA_LOG,
	"jungle": B.BLOCK_JUNGLE_LOG, "mangrove": B.BLOCK_MANGROVE_LOG,
}

class FixtureWorld extends VoxelWorld:
	func _ready() -> void:
		_blocks = BlockRegistry.new()
	func _process(_delta: float) -> void:
		pass
	func make_block_mesh(_id: int) -> ArrayMesh:
		return ArrayMesh.new()

var failures := 0
var _species := ""
var _main: Node
var _world: FixtureWorld
var _ui: Node
var _chunk: VoxelWorld.Chunk


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	# Main/Player reference autoloads, so resolve them after SceneTree startup.
	for species: String in SPECIES:
		_species = species
		var previous_failures := failures
		_setup()
		_chain(int(SPECIES[species]))
		_teardown()
		print("  %s progression: %s" % [species, "PASS" if failures == previous_failures else "FAIL"])
		await process_frame
	await create_timer(0.6).timeout
	print("SURVIVAL PROGRESSION VERIFY: %s" % ("PASS" if failures == 0 else "FAIL (%d)" % failures))
	quit(0 if failures == 0 else 1)


func _setup() -> void:
	_world = FixtureWorld.new()
	root.add_child(_world)
	_chunk = VoxelWorld.Chunk.new()
	_chunk.data.resize(VoxelDefs.CHUNK_AREA * VoxelDefs.WORLD_HEIGHT)
	_chunk.shape = CollisionShape3D.new()
	_chunk.shape.shape = BoxShape3D.new()
	_world.add_child(_chunk.shape)
	_world._chunks[Vector2i.ZERO] = _chunk
	for x in 16:
		for z in 16:
			_set_block(Vector3i(x, 0, z), B.BLOCK_STONE)
	_main = load("res://game/main.gd").new()
	_main._game_mode = GameMode.SURVIVAL
	_main.world = _world
	_main.player = load("res://player/player.gd").new()
	_main.player.game_mode = GameMode.SURVIVAL
	var head := Node3D.new()
	head.name = "Head"
	head.position.y = 1.65
	var camera := Camera3D.new()
	camera.name = "Camera3D"
	head.add_child(camera)
	_main.player.add_child(head)
	root.add_child(_main.player)
	_main.player.set_physics_process(false)
	_main.player.position = Vector3(4.5, 1.2, 4.5)
	_main.player.world = _world
	_main._status_label = Label.new()
	root.add_child(_main._status_label)
	_main._restore_session_state({})
	_main._drops = load("res://game/item_drops.gd").new()
	root.add_child(_main._drops)
	_main._drops.setup(_world, _main.player, _main.inventory)
	_main._drops.set_physics_process(false)
	_ui = load("res://ui/inventory_overlay.tscn").instantiate()
	root.add_child(_ui)
	_ui.configure_inventory(_main.inventory, null)
	_ui.set_game_mode(GameMode.SURVIVAL)
	_main._inventory_overlay = _ui
	_main._connect_player()
	_expect(_main.inventory.slots.all(func(slot: Dictionary) -> bool: return slot.is_empty()), "empty Survival startup")


func _chain(log_id: int) -> void:
	# Six logs: four -> 16 planks (table 4, sticks 4, pick 3, fuel 2,
	# bowls 3); two -> charcoal (one torch batch, one furnace fuel).
	# Eleven ordinary stone -> three cobble for pick plus eight for furnace.
	_mine(log_id, 6)
	_ui.open_panel()
	_craft("planks_" + _species, 4)
	_craft("sticks", 2)
	_craft("crafting_table")
	var before: Array = _main.inventory.persistent_state()
	_expect(CraftingRecipes.max_craftable(_main.inventory, "wood_pickaxe", false) == 0, "table guard maximum")
	_expect(CraftingRecipes.blocking_reason(_main.inventory, "wood_pickaxe", false).contains("table"), "table guard explanation")
	_ui._craft("wood_pickaxe")
	_expect(_main.inventory.persistent_state() == before, "inventory UI cannot craft table-only pick despite owning materials")
	_place_station(B.BLOCK_CRAFTING_TABLE, TABLE)
	_open(TABLE)
	_expect(_ui._at_table, "placed table opened via Player/Main")
	_craft("wood_pickaxe")
	_select(I.ITEM_WOOD_PICKAXE)
	_mine(B.BLOCK_IRON_ORE, 1, false)
	_expect(_main.inventory.count_item(B.BLOCK_IRON_ORE) == 0, "wood pick cannot harvest iron")
	_mine(B.BLOCK_STONE, 11)
	_expect(_main.inventory.count_item(B.BLOCK_STONE) == 0 and _main.inventory.count_item(B.BLOCK_COBBLESTONE) == 11, "ordinary stone actually yields cobble")
	_expect(_durability(I.ITEM_WOOD_PICKAXE) == I.max_durability(I.ITEM_WOOD_PICKAXE) - 12, "Main wears wood pick for successful and failed harvests")
	_ui.open_panel()
	before = _main.inventory.persistent_state()
	_ui._craft("stone_pickaxe")
	_ui._craft_max("furnace")
	_expect(not _ui._at_table and _main.inventory.persistent_state() == before, "closing table revokes access for single and max crafting")
	_open(TABLE)
	_craft("stone_pickaxe")
	_craft("furnace")
	_place_station(B.BLOCK_FURNACE, FURNACE)
	_open(FURNACE)
	_expect(not _ui._at_table, "furnace is not a crafting table")
	var furnace: ItemInventory = _main.containers.get_inventory(FURNACE)
	_move(_main.inventory, _find(_main.inventory, log_id), furnace, BlockContainers.INPUT, 2)
	_move(_main.inventory, _find(_main.inventory, B.BLOCK_PLANKS), furnace, BlockContainers.FUEL, 2)
	_ui.close_panel()
	_main.containers.tick(5.0)
	_expect(furnace.slots[2].is_empty() and _main.containers.get_furnace(FURNACE).progress == 5.0, "charcoal needs actual smelting time")
	_reload_midway()
	furnace = _main.containers.get_inventory(FURNACE)
	_main.containers.tick(15.0)
	_expect(furnace.count_item(I.ITEM_CHARCOAL) == 2 and furnace.slots[0].is_empty() and furnace.slots[1].is_empty(), "reload resumes both log smelts without granting fuel")
	_take_output(I.ITEM_CHARCOAL, 2)
	_ui.open_panel()
	_craft("charcoal_torches")
	_expect(_main.inventory.count_item(B.BLOCK_TORCH) == 4, "renewable charcoal torches")
	_select(I.ITEM_STONE_PICKAXE)
	_mine(B.BLOCK_GOLD_ORE, 1, false)
	_mine(B.BLOCK_IRON_ORE, 3)
	_expect(_durability(I.ITEM_STONE_PICKAXE) == I.max_durability(I.ITEM_STONE_PICKAXE) - 4, "stone pick wear and iron gate")
	_smelt(B.BLOCK_IRON_ORE, I.ITEM_IRON_INGOT, 3, I.ITEM_CHARCOAL)
	_open(TABLE)
	_craft("iron_pickaxe")
	_select(I.ITEM_IRON_PICKAXE)
	_mine(B.BLOCK_GOLD_ORE)
	_smelt(B.BLOCK_GOLD_ORE, I.ITEM_GOLD_INGOT)
	_expect(_durability(I.ITEM_IRON_PICKAXE) == I.max_durability(I.ITEM_IRON_PICKAXE) - 1, "iron pick harvests gold with real wear")
	_expect(_main.inventory.count_item(I.ITEM_STICK) == 1 and _main.inventory.count_item(B.BLOCK_COBBLESTONE) == 0, "derived chain resource totals")
	_food()
	_legacy_smoke()


func _mine(id: int, count: int = 1, harvest: bool = true) -> void:
	_ui.close_panel()
	for index in count:
		# Only natural raw blocks enter the fixture, never inventory or drops.
		_set_block(MINE, id)
		var before: Array = _main.inventory.persistent_state()
		var tool: int = _main.player.selected_block
		_expect(B.can_harvest(id, tool) == harvest, "harvest gate for %d using %d" % [id, tool])
		_main.player.has_target = true
		_main.player.target_block = MINE
		_main.player._break_target()
		var seconds: float = B.break_seconds(id, tool)
		_main.player._tick_mining(seconds * 0.25)
		_expect(_world.get_block_world(MINE) == id, "mining cannot complete before its duration")
		_main.player._tick_mining(seconds + 0.1)
		_expect(_world.get_block_world(MINE) == B.BLOCK_AIR, "timed Player mining removed fixture block")
		var drops: Array = _main._drops.persistent_state()
		_expect(drops.size() == (1 if harvest else 0), "Main spawns only harvestable drops, never failed-harvest tool drops")
		if harvest and drops.size() == 1:
			var expected_id := B.BLOCK_COBBLESTONE if id == B.BLOCK_STONE else (I.ITEM_COAL if id == B.BLOCK_COAL_ORE else id)
			_expect(drops[0].stack.id == expected_id and drops[0].stack.count == 1, "physical drop mapping")
			var old_count: int = _main.inventory.count_item(expected_id)
			var previous_count := 0
			for stack: Dictionary in before:
				if stack.get("id", 0) == expected_id:
					previous_count += int(stack.count)
			_expect(old_count == previous_count, "Main never directly credits mining inventory")
			_pickup()
			_expect(_main.inventory.count_item(expected_id) == old_count + 1, "physical pickup credits exactly one harvested item")
		else:
			for slot in before.size():
				if slot != _main.selected_slot:
					_expect(_main.inventory.slots[slot] == before[slot], "failed harvest cannot grant inventory items")


func _pickup() -> void:
	# Keep deterministic motion, but retain the real delay, collision, magnet,
	# capacity and ownership-transfer path instead of crediting inventory.
	for drop in _main._drops._drops:
		drop.velocity = Vector3.ZERO
	for tick in 50:
		_main._drops._physics_process(0.05)
	_expect(_main._drops.persistent_state().is_empty(), "all physical drops collected")


func _craft(id: String, batches: int = 1) -> void:
	var recipe := CraftingRecipes.get_recipe(id)
	var before: int = _main.inventory.count_item(recipe.output)
	var ingredients := {}
	for ingredient in recipe.ingredients:
		ingredients[ingredient] = _main.inventory.count_item(ingredient)
	_expect(CraftingRecipes.max_craftable(_main.inventory, id, _ui._at_table) >= batches, "affordable recipe " + id)
	_ui._craft(id, batches)
	_expect(_main.inventory.count_item(recipe.output) == before + int(recipe.count) * batches, "UI craft output " + id)
	for ingredient in recipe.ingredients:
		_expect(_main.inventory.count_item(ingredient) == int(ingredients[ingredient]) - int(recipe.ingredients[ingredient]) * batches, "UI consumes exact ingredients for " + id)


func _select(id: int) -> void:
	var index := _find(_main.inventory, id)
	_expect(index >= 0, "select earned item %d" % id)
	if index < 0:
		return
	if index >= ItemInventory.HOTBAR_SIZE:
		_main.inventory.move_stack(index, 0)
		index = 0
	_main.select_slot(index)


func _place_station(id: int, position: Vector3i) -> void:
	_ui.close_panel()
	_select(id)
	var before: int = _main.inventory.count_item(id)
	_main.player.has_target = true
	_main.player.target_block = position + Vector3i.DOWN
	_main.player.target_normal = Vector3i.UP
	_main.player._place_target()
	_expect(_world.get_block_world(position) == id and _main.inventory.count_item(id) == before - 1, "Player places earned station and Main consumes it")


func _open(position: Vector3i) -> void:
	_main.player.has_target = true
	_main.player.target_block = position
	_main.player._place_target()
	_expect(_ui.visible and _ui._station_kind == _world.get_block_world(position), "Player/Main station interaction")


func _move(source: ItemInventory, from: int, target: ItemInventory, to: int, count: int) -> void:
	_expect(from >= 0 and to >= 0, "transfer source and destination exist")
	if from < 0 or to < 0:
		return
	var stack: Dictionary = source.slots[from].duplicate()
	_expect(int(stack.get("count", 0)) >= count and target.slots[to].is_empty(), "transfer owns enough items and destination is empty")
	if int(stack.get("count", 0)) < count or not target.slots[to].is_empty():
		return
	if target == _main.containers.get_inventory(FURNACE):
		_expect(_main.containers.can_insert(FURNACE, to, int(stack.id)), "furnace insertion gate")
	if not source.remove_at(from, count):
		return
	stack.count = count
	target.slots[to] = stack
	target.changed.emit()


func _take_output(id: int, count: int) -> void:
	_open(FURNACE)
	var furnace: ItemInventory = _main.containers.get_inventory(FURNACE)
	_expect(furnace.count_item(id) == count, "furnace output quantity %d" % id)
	var empty := _find(_main.inventory, 0)
	if empty >= 0:
		var drag: Dictionary = _ui.drag_data(_ui._slots[42])
		_expect(_ui.drop_stack(_ui._slots[empty], drag), "UI extracts actual furnace output")
	_expect(furnace.slots[2].is_empty(), "output transferred, not copied")
	_ui.close_panel()


func _smelt(input: int, output: int, count: int = 1, fuel: int = 0) -> void:
	var furnace: ItemInventory = _main.containers.get_inventory(FURNACE)
	_move(_main.inventory, _find(_main.inventory, input), furnace, 0, count)
	if fuel != 0:
		_move(_main.inventory, _find(_main.inventory, fuel), furnace, 1, 1)
	_main.containers.tick(CraftingRecipes.SMELT_SECONDS * count)
	_take_output(output, count)


func _reload_midway() -> void:
	_ui.close_panel()
	var state := {"state_version": 2, "inventory": _main.inventory.persistent_state(),
		"containers": _main.containers.persistent_state(), "selected_slot": _main.selected_slot,
		"day_night": null, "weather": null}
	var serialized: Dictionary = JSON.parse_string(JSON.stringify(state))
	_main.inventory = ItemInventory.new()
	_main.containers = BlockContainers.new()
	_main._restore_session_state(_main._migrate_session_state(serialized))
	_main._drops.setup(_world, _main.player, _main.inventory)
	_ui.configure_inventory(_main.inventory, null)
	_expect(_main.inventory.persistent_state() == state.inventory, "Main reload preserves earned items and worn tools")
	_expect(_main.containers.persistent_state() == state.containers, "Main reload preserves furnace slots, progress and fuel")
	_main.select_slot(_main.selected_slot)


func _food() -> void:
	# Select a non-tool earned stack so gathering food does not hide pick wear.
	_select(I.ITEM_STICK)
	_mine(B.BLOCK_MELON)
	_select(B.BLOCK_MELON)
	_main.player.hunger = 10.0
	_main._on_item_used(B.BLOCK_MELON, Vector3i.ZERO)
	_expect(_main.player.hunger == 10.0 and _main.inventory.count_item(B.BLOCK_MELON) == 1, "whole melon is not food")
	_ui.open_panel()
	_craft("melon_slices")
	_select(I.ITEM_MELON_SLICE)
	_main.player.hunger = 20.0
	_main.player.has_target = false
	_main.player._place_target()
	_expect(_main.inventory.count_item(I.ITEM_MELON_SLICE) == 4, "full hunger does not consume earned food")
	_eat()
	_expect(_main.player.hunger == 12.0 and _main.inventory.count_item(I.ITEM_MELON_SLICE) == 3, "crafted melon slices feed player")
	_mine(B.BLOCK_KELP)
	_smelt(B.BLOCK_KELP, I.ITEM_DRIED_KELP)
	_select(I.ITEM_DRIED_KELP)
	_eat()
	_expect(_main.player.hunger == 11.0 and _main.inventory.count_item(I.ITEM_DRIED_KELP) == 0, "harvested kelp smelts into edible food")
	_select(I.ITEM_STICK)
	_mine(B.BLOCK_BROWN_MUSHROOM, 2)
	_mine(B.BLOCK_RED_MUSHROOM, 2)
	_ui.open_panel()
	_craft("bowls")
	_craft("mushroom_stew", 2)
	_expect(_main.inventory.count_item(B.BLOCK_PLANKS) == 0, "six-log budget fully accounted for")
	_ui.close_panel()
	_mine(B.BLOCK_DIRT, 40)
	# Stash only earned goods, then spread harvested dirt across the backpack.
	# This creates a genuinely full inventory without injecting filler stacks.
	var stash := ItemInventory.new()
	for index in _main.inventory.slots.size():
		var stack: Dictionary = _main.inventory.slots[index]
		if not stack.is_empty() and stack.id not in [I.ITEM_MUSHROOM_STEW, B.BLOCK_DIRT]:
			_move(_main.inventory, index, stash, _find(stash, 0), int(stack.count))
	_select(I.ITEM_MUSHROOM_STEW)
	var dirt_slot := _find(_main.inventory, B.BLOCK_DIRT)
	for index in _main.inventory.slots.size():
		if _main.inventory.slots[index].is_empty():
			_move(_main.inventory, dirt_slot, _main.inventory, index, 1)
	_expect(_find(_main.inventory, 0) == -1, "food test inventory is full")
	_eat()
	_expect(_main.player.hunger == 16.0 and _main.inventory.count_item(I.ITEM_MUSHROOM_STEW) == 1, "stacked stew consumes one serving")
	var drops: Array = _main._drops.persistent_state()
	_expect(drops.size() == 1 and drops[0].stack.id == I.ITEM_BOWL and drops[0].stack.count == 1, "full inventory returns overflow bowl as physical drop")
	_eat()
	_expect(_main.player.hunger == 16.0 and _main.inventory.slots[_main.selected_slot].get("id") == I.ITEM_BOWL, "last stew returns bowl in newly freed slot")
	_pickup()
	_expect(_main.inventory.count_item(I.ITEM_BOWL) == 2 and stash.count_item(I.ITEM_BOWL) == 2, "all four crafted bowls conserved after eating and pickup")


func _eat() -> void:
	_main.player.hunger = 10.0
	_main.player.has_target = false
	_main.player._place_target()


func _legacy_smoke() -> void:
	# Separate migration smoke, never a source of goods for the survival chain.
	var legacy: Node = load("res://game/main.gd").new()
	legacy._game_mode = GameMode.SURVIVAL
	legacy._restore_session_state(legacy._migrate_session_state({"state_version": 1,
		"inventory": [[B.BLOCK_LOG, 2], [I.ITEM_WOOD_PICKAXE, 1]],
		"day_night": null, "weather": null}))
	_expect(legacy.inventory.count_item(B.BLOCK_LOG) == 2 and legacy.inventory.count_item(I.ITEM_WOOD_PICKAXE) == 1, "legacy count save still migrates")
	_expect(CraftingRecipes.craft(legacy.inventory, "planks_oak", false), "legacy three-argument crafting still works")
	legacy.free()


func _find(inventory: ItemInventory, id: int) -> int:
	for index in inventory.slots.size():
		if int(inventory.slots[index].get("id", 0)) == id:
			return index
	return -1


func _durability(id: int) -> int:
	var index := _find(_main.inventory, id)
	return int(_main.inventory.slots[index].get("durability", 0)) if index >= 0 else 0


func _set_block(position: Vector3i, id: int) -> void:
	_chunk.data[position.x + position.z * VoxelDefs.DATA_STRIDE_Z + position.y * VoxelDefs.DATA_STRIDE_Y] = id


func _teardown() -> void:
	_ui.free()
	_main._drops.free()
	_main._status_label.free()
	_main.player.free()
	_world.free()
	_main.free()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("survival_progression_verify [%s]: %s" % [_species, message])
