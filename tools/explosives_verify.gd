## Headless regression check for explosive items, activation, and batched carving.
extends Node

var _used_item := -1
var _used_position := Vector3i.ZERO


func _ready() -> void:
	var failed := false
	var world := VoxelWorld.new()
	world._blocks = BlockRegistry.new()
	var chunk := VoxelWorld.Chunk.new()
	chunk.data.resize(VoxelDefs.CHUNK_AREA * VoxelDefs.WORLD_HEIGHT)
	world._chunks[Vector2i.ZERO] = chunk
	for direction in VoxelDefs.DIRS_8:
		var neighbor := VoxelWorld.Chunk.new()
		neighbor.data.resize(VoxelDefs.CHUNK_AREA * VoxelDefs.WORLD_HEIGHT)
		world._chunks[direction] = neighbor
	for y in range(1, 21):
		for z in VoxelDefs.CHUNK_SIZE:
			for x in VoxelDefs.CHUNK_SIZE:
				_set_block(chunk.data, Vector3i(x, y, z), BlockRegistry.BLOCK_STONE)
	var center := Vector3i(8, 10, 8)
	_set_block(chunk.data, center, BlockRegistry.BLOCK_TNT)
	_set_block(chunk.data, center + Vector3i(0, 0, 2), BlockRegistry.BLOCK_BEDROCK)
	var result := world.trigger_explosive(center)
	failed = _expect(result.get("radius", 0) == VoxelWorld.TNT_BLAST_RADIUS,
		"TNT used the wrong blast radius") or failed
	failed = _expect(int(result.get("removed", 0)) > 1,
		"TNT did not carve terrain") or failed
	failed = _expect(world.get_block_world(center) == BlockRegistry.BLOCK_AIR,
		"TNT block survived its own blast") or failed
	failed = _expect(world.get_block_world(center + Vector3i(0, 0, 2)) == BlockRegistry.BLOCK_BEDROCK,
		"blast removed an unbreakable block") or failed
	failed = _expect(world.get_block_world(center + Vector3i(6, 0, 0)) == BlockRegistry.BLOCK_STONE,
		"blast removed a block outside its sphere") or failed
	failed = _expect(world._edited_blocks.get(center, -1) == BlockRegistry.BLOCK_AIR,
		"blast was not recorded as a persistent edit") or failed
	failed = _expect(world._chunk_edit_version.get(Vector2i.ZERO, 0) == 1,
		"blast invalidated its changed chunk more than once") or failed
	for direction in VoxelDefs.DIRS_8:
		failed = _expect(world._gen_queued.has(direction),
			"blast did not invalidate sampled light neighbor %s" % direction) or failed

	# Multiple fluid writes in one cellular tick must bump/requeue each touched
	# chunk only once; otherwise the full 3x3 light ring multiplies water churn.
	world._gen_queue.clear()
	world._gen_queued.clear()
	world._dirty.clear()
	var water_source := Vector3i(2, 18, 2)
	var water_target := water_source + Vector3i(1, 0, 0)
	_set_block(chunk.data, water_source, BlockRegistry.BLOCK_WATER)
	_set_block(chunk.data, water_target, BlockRegistry.BLOCK_AIR)
	world._queue_water(water_target)
	world._water_tick()
	failed = _expect(world._blocks.is_water_id(world.get_block_world(water_target)),
		"water tick did not place flowing water") or failed
	failed = _expect(world._chunk_edit_version.get(Vector2i.ZERO, 0) == 2,
		"water tick invalidated one changed chunk more than once") or failed

	_set_block(chunk.data, center, BlockRegistry.BLOCK_NUKE)
	var nuke_result := world.trigger_explosive(center)
	failed = _expect(nuke_result.get("radius", 0) == VoxelWorld.NUKE_BLAST_RADIUS,
		"nuke used the wrong blast radius") or failed
	failed = _expect(world.trigger_explosive(center).is_empty(),
		"air was treated as an explosive") or failed

	failed = _expect(ItemRegistry.is_item(ItemRegistry.ITEM_FLINT_AND_STEEL),
		"flint and steel is not registered as an item") or failed
	failed = _expect(not world._blocks.is_valid_id(ItemRegistry.ITEM_FLINT_AND_STEEL),
		"flint and steel leaked into the block ID namespace") or failed
	failed = _expect(not world.place_block(center, ItemRegistry.ITEM_FLINT_AND_STEEL),
		"flint and steel could be placed into chunk data") or failed
	var player := Player.new()
	player.world = world
	player.has_target = true
	player.target_block = center
	player.set_selected_block(ItemRegistry.ITEM_FLINT_AND_STEEL)
	player.item_used.connect(_on_item_used)
	player._place_target()
	failed = _expect(_used_item == ItemRegistry.ITEM_FLINT_AND_STEEL and _used_position == center,
		"right-click did not route the trigger item through item_used") or failed

	player.free()
	world.free()
	if not failed:
		print("EXPLOSIVES VERIFY: PASS")
	get_tree().quit(1 if failed else 0)


func _on_item_used(item_id: int, position: Vector3i) -> void:
	_used_item = item_id
	_used_position = position


func _set_block(data: PackedByteArray, position: Vector3i, block_id: int) -> void:
	var index := position.x + position.z * VoxelDefs.DATA_STRIDE_Z + position.y * VoxelDefs.DATA_STRIDE_Y
	data[index] = block_id


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return false
	push_error("explosives_verify: %s" % message)
	return true
