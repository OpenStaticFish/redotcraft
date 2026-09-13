## Headless check that the render distance really renders full chunks:
## no LOD inside the configured distance, collision exists only near the
## player, and approaching a distant chunk rebuilds it with collision.
## Run:
##   redot --headless --path . --script res://tools/stream_full_verify.gd
extends SceneTree

const RENDER_DISTANCE := 10
const CONFIG := {"seed": 918273, "tree_density": 1.0, "decoration_density": 1.0}
const MAX_WAIT_TICKS := 240
const WAIT_TICK := 0.25

var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var world := VoxelWorld.new()
	root.add_child(world)
	world.configure(CONFIG, RENDER_DISTANCE)
	var player := Node3D.new()
	root.add_child(player)
	player.global_position = Vector3.ZERO
	world.setup_player(player)

	var expected := (RENDER_DISTANCE * 2 + 1) * (RENDER_DISTANCE * 2 + 1)
	var waited := 0
	while (world._chunks.size() < expected or not world._pending.is_empty()) and waited < MAX_WAIT_TICKS:
		await create_timer(WAIT_TICK).timeout
		waited += 1
	print("STREAM FULL: chunks=%d/%d wait_ticks=%d" % [world._chunks.size(), expected, waited])

	for pos in world._chunks.keys():
		if (world._chunks[pos] as VoxelWorld.Chunk).lod:
			_fail("LOD chunk inside the render distance at %s" % pos)
	var near_shapes := 0
	for pos in world._chunks.keys():
		var chunk: VoxelWorld.Chunk = world._chunks[pos]
		var distance := maxi(absi(pos.x), absi(pos.y))
		if distance <= VoxelWorld.COLLISION_DISTANCE:
			if chunk.shape.shape == null:
				_fail("near chunk missing collision at %s" % pos)
			else:
				near_shapes += 1
		elif chunk.shape.shape != null:
			_fail("distant chunk still holds a collision shape at %s" % pos)
	print("STREAM FULL: near_shapes=%d" % near_shapes)

	player.global_position = Vector3(RENDER_DISTANCE * 3 * VoxelDefs.CHUNK_SIZE, 0, 0)
	var center := world._chunk_for_position(player.global_position)
	# Wait for the stream center to move, the new ring to finish loading, and
	# the approached chunk to actually receive its collision shape. Checking
	# the queues before the first tick can exit while the move is still queued.
	waited = 0
	while waited < MAX_WAIT_TICKS:
		await create_timer(WAIT_TICK).timeout
		waited += 1
		if world._stream_center != center or world._pending.size() > 0 \
				or world._gen_queue.size() > 0 or world._commit_queue.size() > 0:
			continue
		var chunk: VoxelWorld.Chunk = world._chunks.get(center)
		if chunk != null and chunk.shape.shape != null:
			break
	var center_chunk: VoxelWorld.Chunk = world._chunks.get(center)
	if center_chunk == null or center_chunk.shape.shape == null:
		_fail("approached chunk never gained collision at %s" % center)
	for pos in world._chunks.keys():
		var chunk: VoxelWorld.Chunk = world._chunks[pos]
		if chunk.shape.shape != null \
				and maxi(absi(pos.x - center.x), absi(pos.y - center.y)) > VoxelWorld.COLLISION_DISTANCE + 1:
			_fail("stale collision shape was not dropped at %s" % pos)

	if _failures == 0:
		print("STREAM FULL VERIFY: PASS")
		quit(0)
		return
	print("STREAM FULL VERIFY: FAIL (%d)" % _failures)
	quit(1)


func _fail(message: String) -> void:
	_failures += 1
	push_error("stream_full_verify: %s" % message)
