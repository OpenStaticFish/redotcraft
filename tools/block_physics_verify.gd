## Headless regression check for persisted gravity reactions.
## Run: redot --headless --path . res://tools/block_physics_verify.tscn
extends Node

var _failures := 0
var _storage_root := "user://block_physics_verify_%d" % Time.get_ticks_usec()


func _ready() -> void:
	_check_registry()
	_check_fall_and_support()
	_check_stacked_no_duplication_or_loss()
	_check_chunk_edge_and_unloaded_cells()
	_check_lod_safety()
	_check_persistence()
	if _failures == 0:
		print("BLOCK PHYSICS VERIFY: PASS")
	else:
		print("BLOCK PHYSICS VERIFY: FAIL (%d)" % _failures)
	get_tree().quit(1 if _failures > 0 else 0)


func _check_registry() -> void:
	var registry := BlockRegistry.new()
	_expect(registry.is_gravity_block(BlockRegistry.BLOCK_SAND), "sand is not a gravity block")
	_expect(registry.is_gravity_block(BlockRegistry.BLOCK_RED_SAND), "red sand is not a gravity block")
	_expect(registry.is_gravity_block(BlockRegistry.BLOCK_GRAVEL), "gravel is not a gravity block")
	_expect(not registry.is_gravity_block(BlockRegistry.BLOCK_STONE), "stone became a gravity block")


func _check_fall_and_support() -> void:
	var world := _make_world(4)
	var sand := Vector3i(4, 8, 4)
	_set_block(world._chunks[Vector2i.ZERO].data, sand, BlockRegistry.BLOCK_SAND)
	world._queue_gravity(sand)
	for step in 4:
		world._gravity_tick()
	_expect(world.get_block_world(Vector3i(4, 5, 4)) == BlockRegistry.BLOCK_SAND,
		"sand did not settle on its stone support")
	_expect(world.get_block_world(sand) == BlockRegistry.BLOCK_AIR,
		"falling sand left a duplicate at its source")
	_expect(world._edited_blocks.get(sand, -1) == BlockRegistry.BLOCK_AIR,
		"sand source air was not persisted")
	_expect(world._edited_blocks.get(Vector3i(4, 5, 4), -1) == BlockRegistry.BLOCK_SAND,
		"sand destination was not persisted")
	_expect(world._chunk_edit_version.get(Vector2i.ZERO, 0) == 3,
		"one gravity move should batch source and destination into one invalidation")
	world.free()

	world = _make_world(4)
	var gravel := Vector3i(7, 5, 7)
	_set_block(world._chunks[Vector2i.ZERO].data, gravel, BlockRegistry.BLOCK_GRAVEL)
	world._queue_gravity(gravel)
	world._gravity_tick()
	_expect(world.get_block_world(gravel) == BlockRegistry.BLOCK_GRAVEL,
		"gravel fell through a solid support")
	_expect(world._edited_blocks.is_empty(), "supported gravel created a persistent edit")
	world.free()


func _check_stacked_no_duplication_or_loss() -> void:
	var world := _make_world(4)
	var sand := Vector3i(5, 8, 5)
	var gravel := sand + Vector3i.UP
	_set_block(world._chunks[Vector2i.ZERO].data, sand, BlockRegistry.BLOCK_SAND)
	_set_block(world._chunks[Vector2i.ZERO].data, gravel, BlockRegistry.BLOCK_GRAVEL)
	# Only waking the lower block must eventually wake its upper neighbour.
	world._queue_gravity(sand)
	for step in 8:
		world._gravity_tick()
	_expect(world.get_block_world(Vector3i(5, 5, 5)) == BlockRegistry.BLOCK_SAND,
		"lower stacked sand settled at the wrong height")
	_expect(world.get_block_world(Vector3i(5, 6, 5)) == BlockRegistry.BLOCK_GRAVEL,
		"upper stacked gravel was not woken after support changed")
	_expect(_count_id_in_column(world, 5, 5, BlockRegistry.BLOCK_SAND) == 1,
		"stacked fall duplicated or lost sand")
	_expect(_count_id_in_column(world, 5, 5, BlockRegistry.BLOCK_GRAVEL) == 1,
		"stacked fall duplicated or lost gravel")
	world.free()


func _check_chunk_edge_and_unloaded_cells() -> void:
	# Vertical motion at x=15 remains valid even when the adjacent x=16 chunk is
	# not loaded. It must only edit its owner chunk.
	var world := _make_world(4, false)
	var edge_sand := Vector3i(VoxelDefs.CHUNK_SIZE - 1, 7, 3)
	_set_block(world._chunks[Vector2i.ZERO].data, edge_sand, BlockRegistry.BLOCK_SAND)
	world._queue_gravity(edge_sand)
	for step in 3:
		world._gravity_tick()
	_expect(world.get_block_world(Vector3i(VoxelDefs.CHUNK_SIZE - 1, 5, 3)) == BlockRegistry.BLOCK_SAND,
		"sand at a chunk edge did not fall inside its loaded owner")
	_expect(world._edits_by_chunk.size() == 1 and world._edits_by_chunk.has(Vector2i.ZERO),
		"edge fall wrote an edit into an unloaded neighbor")
	world._queue_gravity(Vector3i(VoxelDefs.CHUNK_SIZE, 7, 3))
	world._gravity_tick()
	_expect(world._gravity_queue.is_empty() and world._gravity_queued.is_empty(),
		"unloaded gravity candidate was retained or generated a phantom block")
	_expect(not world._edited_blocks.has(Vector3i(VoxelDefs.CHUNK_SIZE, 7, 3)),
		"unloaded gravity candidate recorded an edit")
	world.free()


func _check_lod_safety() -> void:
	var world := _make_world(4, false)
	var chunk: VoxelWorld.Chunk = world._chunks[Vector2i.ZERO]
	var sand := Vector3i(4, 7, 4)
	_set_block(chunk.data, sand, BlockRegistry.BLOCK_SAND)
	chunk.lod = true
	world._queue_gravity(sand)
	world._gravity_tick()
	_expect(chunk.data[_data_index(sand)] == BlockRegistry.BLOCK_SAND,
		"gravity mutated compact LOD chunk data")
	_expect(world._edited_blocks.is_empty(), "gravity persisted a mutation for LOD data")
	world.free()


func _check_persistence() -> void:
	var storage := WorldStorage.new(_storage_root)
	_expect(not storage.create_world({}, {}, "gravity-world", false).is_empty(),
		"could not create gravity persistence fixture")
	var world := _make_world(4)
	world.set_edit_store(storage)
	var sand := Vector3i(3, 7, 3)
	_set_block(world._chunks[Vector2i.ZERO].data, sand, BlockRegistry.BLOCK_SAND)
	world._queue_gravity(sand)
	for step in 3:
		world._gravity_tick()
	_expect(world.flush_edit_store() == OK, "could not flush gravity edits")
	var reopened := WorldStorage.new(_storage_root)
	_expect(not reopened.open_world("gravity-world").is_empty(), "could not reopen gravity fixture")
	var edits := reopened.load_chunk_edits(Vector2i.ZERO)
	_expect(edits.get(sand, -1) == BlockRegistry.BLOCK_AIR,
		"saved gravity source did not replay as air")
	_expect(edits.get(Vector3i(3, 5, 3), -1) == BlockRegistry.BLOCK_SAND,
		"saved gravity destination did not replay as sand")
	_expect(_count_id_in_column(world, 3, 3, BlockRegistry.BLOCK_SAND) == 1,
		"persisted fall duplicated or lost sand before save")
	world.free()


func _make_world(floor_y: int, add_neighbors := true) -> VoxelWorld:
	var world := VoxelWorld.new()
	world._blocks = BlockRegistry.new()
	world._chunks[Vector2i.ZERO] = _make_chunk()
	if add_neighbors:
		for direction in VoxelDefs.DIRS_8:
			world._chunks[direction] = _make_chunk()
	var chunk: VoxelWorld.Chunk = world._chunks[Vector2i.ZERO]
	for z in VoxelDefs.CHUNK_SIZE:
		for x in VoxelDefs.CHUNK_SIZE:
			_set_block(chunk.data, Vector3i(x, floor_y, z), BlockRegistry.BLOCK_STONE)
	return world


func _make_chunk() -> VoxelWorld.Chunk:
	var chunk := VoxelWorld.Chunk.new()
	chunk.data.resize(VoxelDefs.CHUNK_AREA * VoxelDefs.WORLD_HEIGHT)
	return chunk


func _count_id_in_column(world: VoxelWorld, x: int, z: int, block_id: int) -> int:
	var count := 0
	for y in VoxelDefs.WORLD_HEIGHT:
		if world.get_block_world(Vector3i(x, y, z)) == block_id:
			count += 1
	return count


func _data_index(position: Vector3i) -> int:
	return position.x + position.z * VoxelDefs.DATA_STRIDE_Z + position.y * VoxelDefs.DATA_STRIDE_Y


func _set_block(data: PackedByteArray, position: Vector3i, block_id: int) -> void:
	data[_data_index(position)] = block_id


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("block_physics_verify: %s" % message)
