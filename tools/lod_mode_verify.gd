extends SceneTree

const RENDER_DISTANCE := 10
const MAX_WAIT_TICKS := 240
const WAIT_TICK := 0.25

var _failures := PackedStringArray()


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var world := VoxelWorld.new()
	root.add_child(world)
	world.configure({"seed": 918273}, 10, VoxelWorld.LOD_MODE_FULL)
	_expect(world.lod_distance == 10, "full-detail mode no longer covers render distance 10")
	world.set_lod_mode(VoxelWorld.LOD_MODE_BALANCED)
	_expect(world.lod_distance == VoxelWorld.BALANCED_FULL_DETAIL_DISTANCE,
		"balanced mode did not cap full detail at 8 chunks")
	world.set_render_distance(6)
	_expect(world.lod_distance == 6, "balanced mode reduced a short render distance")
	world.set_lod_mode(VoxelWorld.LOD_MODE_FULL)
	world.set_render_distance(16)
	_expect(world.lod_distance == 16, "full-detail mode unexpectedly used compact LOD")
	world.set_render_distance(50)
	_expect(world.lod_distance == 50,
		"full-detail mode unexpectedly enabled LOD at extreme render distance")
	world._stream_center = Vector2i.ZERO
	world._rebuild_desired()
	_expect(world._desired.size() == 101 * 101,
		"extreme desired ring did not contain the complete render square")
	_expect(not world._gen_queue.is_empty() and world._gen_queue[0] == Vector2i.ZERO,
		"extreme generation queue was not built nearest-first")
	_expect(not world._chunk_uses_lod(Vector2i(50, 0)),
		"extreme full-detail boundary was classified as LOD")
	world.set_render_distance(16)
	_expect(world.lod_distance == 16,
		"full-detail mode changed after leaving extreme render distance")
	world.set_lod_mode(VoxelWorld.LOD_MODE_BALANCED)
	_expect(world.lod_distance == 8, "live balanced-mode transition did not update policy")
	world.set_render_distance(50)
	_expect(world.lod_distance == VoxelWorld.BALANCED_FULL_DETAIL_DISTANCE,
		"balanced mode did not retain its explicit inner ring at extreme distance")
	world.set_render_distance(RENDER_DISTANCE)
	var player := Node3D.new()
	root.add_child(player)
	world.setup_player(player)
	await _wait_for_stream(world)
	var lod_chunks := 0
	var full_chunks := 0
	for pos in world._chunks:
		var chunk: VoxelWorld.Chunk = world._chunks[pos]
		var distance := maxi(absi(pos.x), absi(pos.y))
		if distance > VoxelWorld.BALANCED_FULL_DETAIL_DISTANCE:
			lod_chunks += 1
			_expect(chunk.lod, "balanced outer chunk was full detail at %s" % pos)
		else:
			full_chunks += 1
			_expect(not chunk.lod, "balanced inner chunk used LOD at %s" % pos)
	_expect(lod_chunks > 0 and full_chunks > 0, "balanced stream did not produce both detail levels")
	print("LOD MODE STREAM: full=%d lod=%d" % [full_chunks, lod_chunks])
	if _failures.is_empty():
		print("LOD MODE VERIFY: PASS")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("LOD MODE VERIFY: FAIL (", _failures.size(), ")")
	quit(1)


func _wait_for_stream(world: VoxelWorld) -> void:
	var expected := (RENDER_DISTANCE * 2 + 1) * (RENDER_DISTANCE * 2 + 1)
	var waited := 0
	while (world._chunks.size() < expected or not world._pending.is_empty() \
			or not world._gen_queue.is_empty() or not world._mesh_queue.is_empty() \
			or not world._generated.is_empty() or not world._commit_queue.is_empty()) \
			and waited < MAX_WAIT_TICKS:
		await create_timer(WAIT_TICK).timeout
		waited += 1
	_expect(world._chunks.size() == expected, "balanced stream timed out at %d/%d chunks" % [
		world._chunks.size(), expected])


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
