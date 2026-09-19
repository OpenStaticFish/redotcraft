## Deterministic scheduler tests: no worker timing assumptions or rendered assets.
extends SceneTree

var _failures: Array[String] = []


func _initialize() -> void:
	var world := VoxelWorld.new()
	world._stream_center = Vector2i.ZERO
	world._work_push(world._gen_queue, world._gen_queued, Vector2i.ZERO)
	world._work_push(world._mesh_queue, world._mesh_queued, Vector2i(5, 0))
	_expect(not world._next_work_is_mesh(), "distant mesh overtook generation under the player")
	world._work_push(world._mesh_queue, world._mesh_queued, Vector2i.ZERO)
	_expect(world._next_work_is_mesh(), "ready mesh did not win equal-distance generation")
	world._work_pop(world._mesh_queue, world._mesh_queued)
	world._work_pop(world._gen_queue, world._gen_queued)
	world._work_push(world._gen_queue, world._gen_queued, Vector2i(8, 0))
	_expect(world._next_work_is_mesh(), "closer collision mesh lost to distant generation")
	world._work_pop(world._mesh_queue, world._mesh_queued)
	world._work_push(world._mesh_queue, world._mesh_queued, Vector2i(12, 0))
	_expect(not world._next_work_is_mesh(), "far mesh bypassed closer far generation")
	world._gen_queue.clear()
	world._gen_queued.clear()
	world._mesh_queue.clear()
	world._mesh_queued.clear()

	# Completion/invalidation order must not determine dispatch order. Squared
	# distance also orders a farther ring's axis before a nearer ring's corner.
	var positions: Array[Vector2i] = [Vector2i(8, 0), Vector2i(3, 3), Vector2i(4, 0),
		Vector2i(-1, 0), Vector2i(0, 1), Vector2i.ZERO, Vector2i(-8, 0)]
	for pos in positions:
		world._work_push(world._mesh_queue, world._mesh_queued, pos)
		world._work_push(world._mesh_queue, world._mesh_queued, pos)
	_expect(world._mesh_queue.size() == positions.size(), "heap duplicated queued positions")
	var expected: Array[Vector2i] = [Vector2i.ZERO, Vector2i(-1, 0), Vector2i(0, 1),
		Vector2i(4, 0), Vector2i(3, 3), Vector2i(-8, 0), Vector2i(8, 0)]
	for pos in expected:
		_expect(world._work_pop(world._mesh_queue, world._mesh_queued) == pos,
			"mesh queue lost closest-first ordering at %s" % pos)
	_expect(world._mesh_queued.is_empty(), "heap membership remained after drain")

	# Local edited-owner feedback never outranks the player's own chunk.
	# Far edits cannot bypass closer collision repairs.
	for pos in [Vector2i.ZERO, Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 0), Vector2i(5, 0)]:
		world._work_push(world._mesh_queue, world._mesh_queued, pos)
	world._work_push(world._mesh_queue, world._mesh_queued, Vector2i(1, 1), true)
	world._work_push(world._mesh_queue, world._mesh_queued, Vector2i(5, 0), true)
	_expect(world._mesh_queue.size() == 5, "edit promotion duplicated a mesh")
	for pos in [Vector2i.ZERO, Vector2i(1, 1), Vector2i(0, 1), Vector2i(2, 0), Vector2i(5, 0)]:
		_expect(world._work_pop(world._mesh_queue, world._mesh_queued) == pos,
			"edit/safety priority mismatch at %s" % pos)

	# Changing centers rebuilds priorities, including in negative coordinates.
	world.render_distance = 4
	world.lod_distance = 4
	world._stream_center = Vector2i(-17, 9)
	world._rebuild_desired()
	var last_priority := -1
	while not world._gen_queue.is_empty():
		var pos := world._work_pop(world._gen_queue, world._gen_queued)
		var priority := world._work_priority(pos, false)
		_expect(priority >= last_priority, "recentered queue is out of order")
		last_priority = priority
	world.free()
	for failure in _failures:
		push_error(failure)
	print("CHUNK PRIORITY VERIFY: %s" % ("PASS" if _failures.is_empty() else "FAIL"))
	quit(0 if _failures.is_empty() else 1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
