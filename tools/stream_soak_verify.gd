## Bounded streaming/edit soak test for CI. It crosses many non-overlapping
## low-distance stream centers, persists one sparse edit per center, and proves
## that unloaded disk-backed lifecycle state is released before a reload.
## Run:
##   redot --headless --path . --script res://tools/stream_soak_verify.gd
extends SceneTree

const RENDER_DISTANCE := 1
const STEP_CHUNKS := 4
const WAIT_TICK := 0.1
const MAX_WAIT_TICKS := 30
const FAST_TRAVEL_STEPS := 16
const FAST_TRAVEL_WAIT := 0.02
const CONFIG := {
	"seed": 24681357,
	"world_type": 1,
	"tree_density": 0.0,
	"decoration_density": 0.0,
}
## Deliberately project-local: this verifier must not touch user:// during CI.
const STORAGE_ROOT := "res://tools/.stream_soak_verify_data"
const WORLD_ID := "stream-soak"

var _failures := PackedStringArray()


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_cleanup_storage_root()
	var storage := WorldStorage.new(STORAGE_ROOT)
	_expect(not storage.create_world(CONFIG, {}, WORLD_ID).is_empty(), "could not create soak storage")
	var world := VoxelWorld.new()
	root.add_child(world)
	world.set_edit_store(storage)
	world.configure(CONFIG, RENDER_DISTANCE)
	var player := Node3D.new()
	root.add_child(player)
	var centers := _centers()
	player.global_position = _center_position(centers[0])
	world.setup_player(player)
	await _verify_fast_traversal(world, player)
	var expected_edits: Dictionary = {}
	var max_lifecycle := 0

	for index in range(centers.size()):
		var center: Vector2i = centers[index]
		player.global_position = _center_position(center)
		await _wait_settled(world, center, "center %s" % center)
		max_lifecycle = maxi(max_lifecycle, _assert_bounded_state(world, center, max_lifecycle))
		var edit := _place_persistent_edit(world, center)
		if not edit.is_empty():
			expected_edits[center] = edit
		# Let the edit submit its rebuild, then immediately move on. Any worker
		# still live is discarded or stale-checked at the next stream center.
		await create_timer(0.01).timeout

	_expect(not expected_edits.is_empty(), "no persistent edits could be placed")
	var final_center: Vector2i = centers[centers.size() - 1]
	await _wait_settled(world, final_center, "final edit")
	max_lifecycle = maxi(max_lifecycle, _assert_bounded_state(world, final_center, max_lifecycle))
	_expect(world.flush_edit_store() == OK, "could not flush staged persistent edits")

	var first_center: Vector2i = centers[0]
	_expect(not world._chunks.has(first_center), "first center was not unloaded after traversal")
	_expect(not world._edits_by_chunk.has(first_center), "unloaded disk-backed edit bucket was retained")
	_expect(not world._hydrated_edit_chunks.has(first_center), "unloaded hydration marker was retained")
	_expect(not world._chunk_edit_version.has(first_center), "unloaded edit version was retained")

	# A fresh store proves the subsequent replay comes from the persisted region,
	# not from the previous World's cache or the old hydrated edit dictionary.
	var reopened := WorldStorage.new(STORAGE_ROOT)
	_expect(not reopened.open_world(WORLD_ID).is_empty(), "could not reopen flushed soak storage")
	world.set_edit_store(reopened)
	player.global_position = _center_position(first_center)
	await _wait_settled(world, first_center, "persisted reload")
	if expected_edits.has(first_center):
		var edit: Dictionary = expected_edits[first_center]
		_expect(world.get_block_world(edit["position"]) == edit["id"],
			"persisted edit did not reload at %s" % edit["position"])
	_assert_bounded_state(world, first_center, max_lifecycle)

	print("STREAM SOAK: centers=%d edits=%d max_lifecycle=%d chunks=%d" % [
		centers.size(), expected_edits.size(), max_lifecycle, world._chunks.size(),
	])
	player.queue_free()
	world.queue_free()
	await process_frame
	_cleanup_storage_root()
	if _failures.is_empty():
		print("STREAM SOAK VERIFY: PASS")
		quit(0)
		return
	for failure in _failures:
		push_error("stream_soak_verify: %s" % failure)
	print("STREAM SOAK VERIFY: FAIL (%d)" % _failures.size())
	quit(1)


func _centers() -> Array[Vector2i]:
	return [
		Vector2i(0, 0), Vector2i(STEP_CHUNKS, 0), Vector2i(STEP_CHUNKS * 2, 0),
		Vector2i(STEP_CHUNKS * 2, STEP_CHUNKS), Vector2i(STEP_CHUNKS, STEP_CHUNKS),
		Vector2i(0, STEP_CHUNKS), Vector2i(-STEP_CHUNKS, STEP_CHUNKS),
		Vector2i(-STEP_CHUNKS * 2, STEP_CHUNKS), Vector2i(-STEP_CHUNKS * 2, 0),
		Vector2i(-STEP_CHUNKS * 2, -STEP_CHUNKS), Vector2i(-STEP_CHUNKS, -STEP_CHUNKS),
		Vector2i(0, -STEP_CHUNKS),
	]


func _center_position(center: Vector2i) -> Vector3:
	return Vector3(
		float(center.x * VoxelDefs.CHUNK_SIZE + VoxelDefs.CHUNK_SIZE / 2), 96.0,
		float(center.y * VoxelDefs.CHUNK_SIZE + VoxelDefs.CHUNK_SIZE / 2)
	)


func _wait_settled(world: VoxelWorld, center: Vector2i, label: String) -> void:
	for tick in MAX_WAIT_TICKS:
		await create_timer(WAIT_TICK).timeout
		if world._stream_center != center or not _stream_queues_settled(world):
			continue
		return
	_fail("%s did not settle (chunks=%d pending=%d gen=%d mesh=%d staged=%d commits=%d)" % [
		label, world._chunks.size(), world._pending.size(), world._gen_queue.size(),
		world._mesh_queue.size(), world._generated.size(), world._commit_queue.size(),
	])


func _verify_fast_traversal(world: VoxelWorld, player: Node3D) -> void:
	var peak_pending := 0
	var peak_stale_pending := 0
	for step in range(1, FAST_TRAVEL_STEPS + 1):
		var center := Vector2i(step, 0)
		player.global_position = _center_position(center)
		await create_timer(FAST_TRAVEL_WAIT).timeout
		peak_pending = maxi(peak_pending, world._pending.size())
		var stale_pending := 0
		for pos in world._pending:
			if not world._desired.has(pos):
				stale_pending += 1
		peak_stale_pending = maxi(peak_stale_pending, stale_pending)
		_expect(world._pending.size() <= world._max_active_jobs + 1,
			"fast traversal exceeded the worker bound plus urgent collision slot")
	var final_center := Vector2i(FAST_TRAVEL_STEPS, 0)
	await _wait_settled(world, final_center, "fast traversal recovery")
	_expect(world.is_collision_ready_at(player.global_position),
		"fast traversal did not recover collision at the final center")
	print("STREAM SOAK FLIGHT: steps=%d peak_pending=%d peak_stale=%d" % [
		FAST_TRAVEL_STEPS, peak_pending, peak_stale_pending,
	])


func _stream_queues_settled(world: VoxelWorld) -> bool:
	return world._pending.is_empty() and world._gen_queue.is_empty() \
		and world._mesh_queue.is_empty() and world._generated.is_empty() \
		and world._commit_queue.is_empty()


func _place_persistent_edit(world: VoxelWorld, center: Vector2i) -> Dictionary:
	var chunk: VoxelWorld.Chunk = world._chunks.get(center)
	if chunk == null or chunk.lod:
		_fail("no full chunk available for persistent edit at %s" % center)
		return {}
	var local := VoxelDefs.CHUNK_SIZE / 2
	var column := local + local * VoxelDefs.DATA_STRIDE_Z
	var position := Vector3i(
		center.x * VoxelDefs.CHUNK_SIZE + local,
		mini(chunk.heights[column] + 1, VoxelDefs.WORLD_HEIGHT - 1),
		center.y * VoxelDefs.CHUNK_SIZE + local,
	)
	if not world.place_block(position, BlockRegistry.BLOCK_TORCH):
		_fail("could not place persistent edit at %s" % position)
		return {}
	return {"position": position, "id": BlockRegistry.BLOCK_TORCH}


func _assert_bounded_state(world: VoxelWorld, center: Vector2i, previous_max: int) -> int:
	var resident_limit := (world.unload_radius * 2 + 1) * (world.unload_radius * 2 + 1)
	var lifecycle_size := world._dirty.size() + world._generated.size() \
		+ world._chunk_edit_version.size() + world._edits_by_chunk.size() \
		+ world._hydrated_edit_chunks.size()
	_expect(world._chunks.size() <= resident_limit,
		"resident chunks exceeded bound at %s: %d > %d" % [center, world._chunks.size(), resident_limit])
	_expect(world._chunk_edit_version.size() <= world._chunks.size(),
		"edit versions outgrew loaded chunks at %s" % center)
	_expect(world._edits_by_chunk.size() <= world._chunks.size(),
		"disk edit buckets outgrew loaded chunks at %s" % center)
	_expect(world._hydrated_edit_chunks.size() <= world._chunks.size(),
		"hydration markers outgrew loaded chunks at %s" % center)
	_expect(lifecycle_size <= world._chunks.size() * 3,
		"lifecycle state outgrew resident chunks at %s: %d for %d chunks" % [
			center, lifecycle_size, world._chunks.size(),
		])
	return maxi(previous_max, lifecycle_size)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)


func _fail(message: String) -> void:
	_failures.append(message)


## This verifier owns a hidden, project-local fixture directory. Clearing it
## keeps repeat runs deterministic without touching user:// or game saves.
func _cleanup_storage_root() -> void:
	_remove_tree(ProjectSettings.globalize_path(STORAGE_ROOT))


func _remove_tree(path: String) -> void:
	var directory := DirAccess.open(path)
	if directory == null:
		return
	directory.list_dir_begin()
	var name := directory.get_next()
	while not name.is_empty():
		if name != "." and name != "..":
			var child := path.path_join(name)
			if directory.current_is_dir():
				_remove_tree(child)
			DirAccess.remove_absolute(child)
		name = directory.get_next()
	directory.list_dir_end()
	DirAccess.remove_absolute(path)
