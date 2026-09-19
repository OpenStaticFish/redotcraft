extends SceneTree

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var world := VoxelWorld.new()
	root.add_child(world)
	world.set_lod_batching_enabled(true)
	var normal := "--normal" in OS.get_cmdline_user_args()
	world.configure({"seed": 918273, "world_type": 0 if normal else 1}, 2)
	# Exercise the Extreme queue builder without submitting 40,401 jobs.
	world._stream_center = Vector2i.ZERO
	world.render_distance = 100
	world._update_lod_distance()
	world._rebuild_desired()
	_expect(world._desired.size() == 40401, "Extreme ring enumeration omitted cells")
	_expect(world._gen_queue[0] == Vector2i.ZERO, "Extreme queue does not start at the player")
	for index in range(1, world._gen_queue.size()):
		_expect(not world._work_less(world._gen_queue[index], world._gen_queue[(index - 1) / 2], world._gen_queued),
			"Extreme generation heap violates nearest-first priority")
	world.set_render_distance(2)
	var target := Node3D.new()
	root.add_child(target)
	world.begin_initial_stream(target)
	await _settle(world, "initial", 20.0)
	paused = true
	world.set_render_distance(3)
	var water_time := world._water_accum
	var fire_time := world._fire_accum
	var gravity_time := world._gravity_accum
	await _settle(world, "paused expansion", 20.0)
	_expect(world._water_accum == water_time and world._fire_accum == fire_time
		and world._gravity_accum == gravity_time, "paused streaming advanced simulation")
	paused = false
	# Replace queued and in-flight requests, including crossings of the LOD band.
	world.set_render_distance(10)
	world.set_lod_mode(VoxelWorld.LOD_MODE_BALANCED)
	await create_timer(0.1).timeout
	world.set_render_distance(2)
	world.set_render_distance(10)
	await _settle(world, "rapid distance changes", 60.0)
	world.set_lod_mode(VoxelWorld.LOD_MODE_FULL)
	await create_timer(0.1).timeout
	world.set_lod_mode(VoxelWorld.LOD_MODE_BALANCED)
	await _settle(world, "in-flight mode reversal", 60.0)
	world.set_lod_mode(VoxelWorld.LOD_MODE_FULL)
	await _settle(world, "Balanced to Full", 60.0)
	world.set_lod_mode(VoxelWorld.LOD_MODE_BALANCED)
	await _settle(world, "Full to Balanced", 60.0)
	world.set_render_distance(2)
	await _settle(world, "contraction", 20.0)
	print("TRANSITION METRICS: ", world.get_worldgen_stats())
	world.free()
	target.free()
	for failure in _failures:
		push_error(failure)
	print("STREAM TRANSITION VERIFY: %s" % ("PASS" if _failures.is_empty() else "FAIL"))
	quit(0 if _failures.is_empty() else 1)


func _settle(world: VoxelWorld, label: String, budget: float) -> void:
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < budget * 1000.0:
		await create_timer(0.1).timeout
		if not world._pending.is_empty() or not world._gen_queue.is_empty() \
				or not world._mesh_queue.is_empty() or not world._generated.is_empty() \
				or not world._commit_queue.is_empty():
			continue
		if world.lod_batching_enabled and world.lod_distance < world.render_distance \
				and (not world._lod_batch_refill_complete or not world._lod_batch_queue.is_empty()):
			continue
		var complete := true
		for pos in world._desired:
			var chunk: VoxelWorld.Chunk = world._chunks.get(pos)
			if chunk == null or chunk.lod != world._chunk_uses_lod(pos):
				complete = false
		if complete:
			var compact_count := 0
			for chunk: VoxelWorld.Chunk in world._chunks.values():
				if chunk.lod:
					compact_count += 1
			var batches := world.get_lod_batch_stats()
			_expect(int(batches["invalid batches"]) == 0 and int(batches["duplicate members"]) == 0,
				"invalid/duplicate batches after %s" % label)
			_expect(int(batches["visible lod members"]) + int(batches["batched members"]) == compact_count,
				"missing or double-rendered compact chunks after %s" % label)
			_expect(int(world.get_streaming_progress().loaded) == world._desired.size(),
				"stream progress counter drifted after %s" % label)
			print("TRANSITION %s: %d desired, %d ms" % [label, world._desired.size(), Time.get_ticks_msec() - started])
			return
	_expect(false, "%s stalled: %s" % [label, world.get_worldgen_stats()])


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
