## Headless regression check for collision-independent voxel targeting.
extends Node


func _ready() -> void:
	var world := VoxelWorld.new()
	var chunk := VoxelWorld.Chunk.new()
	chunk.data.resize(VoxelDefs.CHUNK_AREA * VoxelDefs.WORLD_HEIGHT)
	world._chunks[Vector2i.ZERO] = chunk
	_set_block(chunk.data, Vector3i(2, 3, 1), BlockRegistry.BLOCK_WATER)
	_set_block(chunk.data, Vector3i(2, 3, 2), BlockRegistry.BLOCK_TALL_GRASS)
	_set_block(chunk.data, Vector3i(2, 3, 3), BlockRegistry.BLOCK_STONE)
	var player := Player.new()
	player.world = world
	var result := player._voxel_raycast(Vector3(2.5, 3.5, 0.5), Vector3.FORWARD * -1.0, 6.0)
	var failed := false
	if result.get("block", Vector3i.ZERO) != Vector3i(2, 3, 2):
		push_error("player_target_verify: ray did not skip water and select the cross plant")
		failed = true
	if result.get("normal", Vector3i.ZERO) != Vector3i(0, 0, -1):
		push_error("player_target_verify: selected plant returned the wrong entered face")
		failed = true
	var registry := BlockRegistry.new()
	if not registry.is_breakable(BlockRegistry.BLOCK_TALL_GRASS):
		push_error("player_target_verify: selected cross plant is not breakable")
		failed = true
	registry = null
	player.free()
	world.free()
	if not failed:
		print("PLAYER TARGET VERIFY: PASS")
	get_tree().quit(1 if failed else 0)


func _set_block(data: PackedByteArray, position: Vector3i, block_id: int) -> void:
	var index := position.x + position.z * VoxelDefs.DATA_STRIDE_Z + position.y * VoxelDefs.DATA_STRIDE_Y
	data[index] = block_id
