extends SceneTree

class TestWorld extends VoxelWorld:
	func use_flint_and_steel(_position: Vector3i, _normal: Vector3i) -> Dictionary:
		return {"ignited": 1}

var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	# Exercise Main ownership without starting streaming or touching world saves.
	var drops_script = load("res://game/item_drops.gd")
	if drops_script == null or not drops_script.can_instantiate():
		push_error("ItemDrops dependency failed to compile")
		quit(1)
		return
	var main = load("res://game/main.gd").new()
	main._game_mode = GameMode.SURVIVAL
	main.player = load("res://player/player.gd").new()
	main.player.game_mode = GameMode.SURVIVAL
	main.world = TestWorld.new()
	main.world._blocks = BlockRegistry.new()
	main._status_label = Label.new()
	root.add_child(main._status_label)
	main._restore_session_state({})
	_expect(main.inventory.count_item(1) == 0 and main._inventory_overflow.is_empty(), "new survival inventory is empty")
	main.inventory.add_item(1, 3)
	main._restore_session_state({"state_version": 2, "day_night": null, "weather": null})
	_expect(main.inventory.count_item(1) == 0, "missing survival inventory falls back to empty")
	# Null environment dependencies make accidental Survival handler access fail.
	main._on_inventory_time_selected(12.0)
	main._on_weather_toggled()
	var legacy: Dictionary = main._migrate_session_state({"state_version": 1,
		"inventory": [[2, 12000], [1000, 3]], "selected_slot": 99,
		"day_night": null, "weather": null})
	main._restore_session_state(legacy)
	_expect(main.inventory.count_item(2) + int(main._inventory_overflow.get(2, 0)) == 12000, "legacy counts survive capacity overflow without a 9999 cap")
	_expect(main.inventory.count_item(1000) + int(main._inventory_overflow.get(1000, 0)) == 3, "legacy tools retain all copies")
	_expect(main.selected_slot == 9, "restored selection is limited to ten slots")
	main.inventory.restore([])
	main.inventory.slots[15] = {"id": 2, "count": 12, "durability": 0}
	main.inventory.slots[9] = {"id": 3, "count": 7, "durability": 0}
	main._on_block_picked(2)
	_expect(main.inventory.slots[9].id == 2 and main.inventory.slots[15].id == 3, "pick swaps owned backpack stack into selected hotbar slot")
	var before: Array = main.inventory.persistent_state()
	main._on_block_picked(ItemRegistry.ITEM_IRON_PICKAXE)
	_expect(main.inventory.persistent_state() == before, "pick never grants an unowned item")
	main.inventory.slots[9] = {"id": ItemRegistry.ITEM_COOKED_MEAT, "count": 2, "durability": 0}
	main._on_item_used(ItemRegistry.ITEM_COOKED_MEAT, Vector3i.ZERO)
	_expect(main.inventory.slots[9].count == 2, "full hunger does not consume food")
	main.player.hunger = 10.0
	main._on_item_used(ItemRegistry.ITEM_COOKED_MEAT, Vector3i.ZERO)
	_expect(main.inventory.slots[9].count == 1 and main.player.hunger == 18.0, "successful eating consumes exactly one item")
	main._restore_session_state({"state_version": 2, "inventory": before,
		"day_night": null, "weather": null})
	_expect(main.inventory.persistent_state() == before, "v2 restores exact stack positions")
	main.inventory.slots[0] = {"id": ItemRegistry.ITEM_WOOD_PICKAXE, "count": 1, "durability": 1}
	main.inventory.slots[1] = {"id": ItemRegistry.ITEM_WOOD_PICKAXE, "count": 1, "durability": 59}
	main.select_slot(0)
	main.player._mining = true
	main.player.mining_progress = 0.9
	main.select_slot(1)
	_expect(not main.player._mining and main.player.mining_progress == 0.0, "switching identical tools cancels mining progress")
	main._drops = drops_script.new()
	main.add_child(main._drops)
	main._on_mined_block(Vector3i.ZERO, BlockRegistry.BLOCK_STONE, true)
	_expect(main.inventory.slots[1].durability == 58 and main._drops.persistent_state().size() == 1, "survival mining wears tool and drops harvested block")
	_expect(main._drops.persistent_state()[0].stack.id == BlockRegistry.BLOCK_COBBLESTONE, "mined stone becomes physical cobblestone")
	main._on_mined_block(Vector3i.ZERO, BlockRegistry.BLOCK_IRON_ORE, false)
	_expect(main._drops.persistent_state().size() == 1 and main.inventory.slots[1].durability == 57, "failed harvest wears tool but yields no drop")
	main._on_mined_block(Vector3i.ZERO, BlockRegistry.BLOCK_COAL_ORE, true)
	_expect(main._drops.persistent_state()[1].stack.id == ItemRegistry.ITEM_COAL, "coal ore yields physical coal")
	var food_before: Array = main.inventory.persistent_state()
	for index in main.inventory.slots.size():
		main.inventory.slots[index] = {"id": BlockRegistry.BLOCK_DIRT, "count": 64, "durability": 0}
	main.inventory.slots[1] = {"id": ItemRegistry.ITEM_MUSHROOM_STEW, "count": 1, "durability": 0}
	main.player.hunger = 10.0
	main._on_item_used(ItemRegistry.ITEM_MUSHROOM_STEW, Vector3i.ZERO)
	_expect(main.player.hunger == 16.0 and main.inventory.slots[1].id == ItemRegistry.ITEM_BOWL, "stew frees selected slot before returning bowl in full inventory")
	main.inventory.slots[1] = {"id": ItemRegistry.ITEM_MUSHROOM_STEW, "count": 2, "durability": 0}
	main.player.hunger = 10.0
	main._drops.restore([])
	var head := Node3D.new()
	head.name = "Head"
	var camera := Camera3D.new()
	camera.name = "Camera3D"
	head.add_child(camera)
	main.player.add_child(head)
	root.add_child(main.player)
	main._on_item_used(ItemRegistry.ITEM_MUSHROOM_STEW, Vector3i.ZERO)
	_expect(main.inventory.slots[1].count == 1 and main._drops.persistent_state().size() == 1
		and main._drops.persistent_state()[0].stack.id == ItemRegistry.ITEM_BOWL, "stacked stew drops overflow bowl without loss")
	root.remove_child(main.player)
	main.inventory.slots[1] = {"id": BlockRegistry.BLOCK_MELON, "count": 1, "durability": 0}
	main.player.hunger = 10.0
	main._on_item_used(BlockRegistry.BLOCK_MELON, Vector3i.ZERO)
	_expect(main.player.hunger == 10.0 and main.inventory.slots[1].count == 1, "melon cannot be directly eaten")
	main.inventory.restore(food_before)
	main._drops.restore([])
	main.inventory.slots[2] = {"id": 2, "count": 2, "durability": 0}
	main.select_slot(2)
	main.consume_selected_block()
	_expect(main.inventory.slots[2].count == 1, "survival placement consumes one block")
	main.inventory.slots[2] = {"id": ItemRegistry.ITEM_FLINT_AND_STEEL, "count": 1, "durability": 10}
	main._on_item_used(ItemRegistry.ITEM_FLINT_AND_STEEL, Vector3i.ZERO)
	_expect(main.inventory.slots[2].durability == 9, "survival ignition wears flint and steel")
	var chest_position := Vector3i(160, 60, 160)
	main.containers.ensure_chest(chest_position).add_item(2, 80)
	main._check_removed_containers()
	_expect(main.containers.get_inventory(chest_position) != null, "unloaded chunks do not destroy containers")
	main._drop_container_contents(chest_position)
	var drop_count := 0
	for drop in main._drops.persistent_state():
		drop_count += int(drop.stack.count)
	_expect(drop_count == 80 and main.containers.get_inventory(chest_position) == null, "broken containers transfer every stack to physical drops")
	main._drop_container_contents(chest_position)
	_expect(main._drops.persistent_state().size() == 2, "container removal cannot duplicate drops")
	var hud := Control.new()
	root.add_child(hud)
	var survival = load("res://game/survival_ui.gd").new()
	root.add_child(survival)
	survival.setup(hud, main.player)
	_expect(survival._vitals.visible, "survival vitals visible")
	survival.show_death("fall")
	_expect(survival._death.visible and survival._respawn.has_focus(), "death modal opens with respawn focus")
	survival.hide_death()
	_expect(not survival._death.visible, "respawn dismisses death modal")
	main._game_mode = GameMode.CREATIVE
	main.player.game_mode = GameMode.CREATIVE
	main._restore_session_state({})
	_expect(main.inventory.count_item(1) == 64, "creative retains starter palette")
	main.select_slot(0)
	main._on_block_picked(BlockRegistry.BLOCK_STONE)
	_expect(main.inventory.slots[0].id == BlockRegistry.BLOCK_STONE and main.inventory.slots[0].count == 64
		and main.player.selected_block == BlockRegistry.BLOCK_STONE, "creative pick grants selected full stack")
	main.consume_selected_block()
	_expect(main.inventory.slots[0].count == 64, "creative placement does not consume")
	main._on_block_picked(ItemRegistry.ITEM_WOOD_PICKAXE)
	before = main.inventory.persistent_state()
	var drops_before: Array = main._drops.persistent_state()
	main.containers.ensure_chest(chest_position).add_item(2, 80)
	main._on_mined_block(chest_position, BlockRegistry.BLOCK_CHEST, true)
	_expect(main.inventory.persistent_state() == before and main._drops.persistent_state() == drops_before
		and main.containers.get_inventory(chest_position) == null, "creative mining has no wear or block/container drops")
	main._on_block_picked(ItemRegistry.ITEM_FLINT_AND_STEEL)
	before = main.inventory.persistent_state()
	main._on_item_used(ItemRegistry.ITEM_FLINT_AND_STEEL, Vector3i.ZERO)
	_expect(main.inventory.persistent_state() == before, "creative ignition does not wear flint and steel")
	var config := root.get_node("GameConfig")
	var pending_mode: int = config.pending_game_mode
	config.pending_game_mode = GameMode.SURVIVAL
	main.consume_selected_block()
	_expect(main.inventory.persistent_state() == before and main.player.game_mode == GameMode.CREATIVE, "pending selection cannot change running gameplay mode")
	config.pending_game_mode = pending_mode
	main._restore_session_state({"state_version": 2, "inventory": before,
		"game_mode": GameMode.SURVIVAL, "day_night": null, "weather": null})
	_expect(main._game_mode == GameMode.CREATIVE and main.inventory.persistent_state() == before, "session cannot replace startup mode or reset saved inventory")
	survival._update_vitals()
	survival.show_death("ignored")
	_expect(not survival._vitals.visible and not survival._death.visible, "creative hides vitals and death modal")
	survival.free()
	hud.free()
	main._status_label.free()
	main.player.free()
	main.world.free()
	main.free()
	print("Gameplay integration verifier: %d failure(s)" % _failures)
	quit(1 if _failures else 0)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
