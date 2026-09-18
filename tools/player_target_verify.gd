## Headless regression check for collision-independent voxel targeting.
extends Node


func _ready() -> void:
	var failed := false
	var world := VoxelWorld.new()
	var chunk := VoxelWorld.Chunk.new()
	chunk.data.resize(VoxelDefs.CHUNK_AREA * VoxelDefs.WORLD_HEIGHT)
	chunk.shape = CollisionShape3D.new()
	chunk.shape.shape = BoxShape3D.new()
	world.add_child(chunk.shape)
	world._chunks[Vector2i.ZERO] = chunk
	var east := VoxelWorld.Chunk.new()
	# A committed visible chunk can temporarily lack collision while an approach
	# rebuild catches up. It is loaded and must not become an invisible wall.
	east.shape = CollisionShape3D.new()
	world._chunks[Vector2i(1, 0)] = east
	var far_collisionless := VoxelWorld.Chunk.new()
	far_collisionless.shape = CollisionShape3D.new()
	world._chunks[Vector2i(5, 5)] = far_collisionless
	world._stream_center = Vector2i.ZERO
	world._ensure_near_collision()
	if world._mesh_queue.is_empty() or world._mesh_queue[0] != Vector2i(1, 0):
		push_error("player_target_verify: nearby collision remesh was not prioritized")
		failed = true
	world._mesh_queue.clear()
	world._mesh_queued.clear()
	world._dirty.clear()
	var distant_mesh_job := VoxelWorld.PendingJob.new()
	distant_mesh_job.kind = "mesh"
	distant_mesh_job.want_collision = false
	world._pending[Vector2i(1, 0)] = distant_mesh_job
	world._ensure_near_collision()
	if not world._dirty.has(Vector2i(1, 0)):
		push_error("player_target_verify: in-flight visual mesh was not upgraded for nearby collision")
		failed = true
	world._pending.erase(Vector2i(1, 0))
	world._dirty.clear()
	var far_result := ChunkMesher.MeshResult.new()
	far_result.build_collision = false
	var near_result := ChunkMesher.MeshResult.new()
	near_result.build_collision = true
	world._commit_queue = [
		VoxelWorld.CommitItem.new(Vector2i(10, 0), far_result, 0, 0, false),
		VoxelWorld.CommitItem.new(Vector2i(1, 0), near_result, 0, 0, false),
	]
	if world._next_commit_index() != 1:
		push_error("player_target_verify: near collision commit was not prioritized")
		failed = true
	world._commit_queue.clear()
	world._touch_chunk(Vector2i.ZERO, Vector3i(15, 3, 8),
		BlockRegistry.BLOCK_STONE, BlockRegistry.BLOCK_AIR)
	if world._mesh_queue.is_empty() or world._mesh_queue[0] != Vector2i.ZERO:
		push_error("player_target_verify: edited owner was queued behind neighbor lighting work")
		failed = true
	world._mesh_queue.clear()
	world._mesh_queued.clear()
	world._dirty.clear()
	_set_block(chunk.data, Vector3i(2, 3, 1), BlockRegistry.BLOCK_WATER)
	_set_block(chunk.data, Vector3i(2, 3, 2), BlockRegistry.BLOCK_TALL_GRASS)
	_set_block(chunk.data, Vector3i(2, 3, 3), BlockRegistry.BLOCK_STONE)
	var player := Player.new()
	player.world = world
	player.position = Vector3(12.5, 70.0, -8.25)
	var detached_state := player.persistent_state()
	if detached_state.get("position", []) != [12.5, 70.0, -8.25]:
		push_error("player_target_verify: detached persistence did not use local position")
		failed = true
	var blocked_fraction := world.loaded_motion_fraction(
		Vector3(8.0, 70.0, 8.0), Vector3(40.0, 70.0, 8.0))
	var blocked_x := 8.0 + 32.0 * blocked_fraction
	if blocked_fraction <= 0.0 or blocked_fraction >= 1.0 or floori(blocked_x / 16.0) != 1:
		push_error("player_target_verify: stream boundary did not stop before an unloaded chunk")
		failed = true
	if world.loaded_motion_fraction(Vector3(2.0, 70.0, 2.0), Vector3(24.0, 70.0, 2.0)) != 1.0:
		push_error("player_target_verify: stream boundary blocked motion through loaded chunks")
		failed = true
	var flight_player := Player.new()
	flight_player.game_mode = GameMode.CREATIVE
	var flight_shape := CollisionShape3D.new()
	flight_shape.shape = CapsuleShape3D.new()
	flight_player.add_child(flight_shape)
	var flight_head := Node3D.new()
	flight_head.name = "Head"
	flight_player.add_child(flight_head)
	var flight_camera := Camera3D.new()
	flight_camera.name = "Camera3D"
	flight_head.add_child(flight_camera)
	flight_player._highlight = MeshInstance3D.new()
	flight_player.add_child(flight_player._highlight)
	add_child(flight_player)
	flight_player.set_physics_process(false)
	flight_player.world = world
	if not flight_player.restore_persistent_state({
		"position": [15.75, 210.0, 8.0],
		"spawn": [15.75, 205.0, 8.0],
		"flying": true,
	}) or not is_equal_approx(flight_player.global_position.y, 210.0) \
			or not is_equal_approx(flight_player.spawn_position.y, 205.0):
		push_error("player_target_verify: legitimate above-ceiling flight state was rejected")
		failed = true
	flight_player.flying = true
	flight_player.global_position = Vector3(15.75, 70.0, 8.0)
	flight_player.velocity = Vector3(10.0, -10.0, 0.0)
	flight_player._physics_process(0.1)
	if not is_zero_approx(flight_player.velocity.y) \
			or not is_equal_approx(flight_player.global_position.y, 70.0):
		push_error("player_target_verify: flight descended while entering collision-pending terrain")
		failed = true
	flight_player.global_position = Vector3(16.25, 70.0, 8.0)
	var waiting_position := flight_player.global_position
	flight_player.velocity = Vector3(1.0, -20.0, 0.0)
	flight_player._physics_process(0.1)
	if not flight_player.global_position.is_equal_approx(waiting_position) \
			or not flight_player.velocity.is_zero_approx():
		push_error("player_target_verify: flying player moved before current chunk collision was ready")
		failed = true
	var flight_status := [""]
	flight_player.status_requested.connect(func(message: String) -> void: flight_status[0] = message)
	flight_player._last_jump_time = Time.get_ticks_msec() / 1000.0
	flight_player._handle_double_tap_jump()
	if flight_player.flying or flight_status[0] != "Flying disabled":
		push_error("player_target_verify: collision loading prevented flight from being disabled safely")
		failed = true
	var result := player._voxel_raycast(Vector3(2.5, 3.5, 0.5), Vector3.FORWARD * -1.0, 6.0)
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
	flight_player.free()
	player.free()
	east.shape.free()
	far_collisionless.shape.free()
	world.free()
	if not failed:
		print("PLAYER TARGET VERIFY: PASS")
	get_tree().quit(1 if failed else 0)


func _set_block(data: PackedByteArray, position: Vector3i, block_id: int) -> void:
	var index := position.x + position.z * VoxelDefs.DATA_STRIDE_Z + position.y * VoxelDefs.DATA_STRIDE_Y
	data[index] = block_id
