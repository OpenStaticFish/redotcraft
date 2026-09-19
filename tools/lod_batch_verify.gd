## Structural coverage for render-only 2x2 Balanced-LOD aggregation. This runs
## headless: it validates ownership/visibility, mesh attributes, invalidation,
## and bounded scheduling without claiming any GPU performance result.
extends SceneTree

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var world := VoxelWorld.new()
	root.add_child(world)
	await process_frame
	_expect(not world.lod_batching_enabled, "experimental LOD batching must default off")
	world.set_lod_batching_enabled(true)
	world._stream_center = Vector2i.ZERO
	world.render_distance = 24
	world.lod_distance = 0
	var group := [Vector2i(20, 20), Vector2i(21, 20), Vector2i(20, 21), Vector2i(21, 21)]
	for pos in group:
		world._desired[pos] = true
		var chunk := world._create_chunk_nodes(pos)
		chunk.lod = true
		chunk.mesh.mesh = _source_mesh(world)
		world._chunks[pos] = chunk
		world._queue_lod_batch_for(pos)
	# Pending commits have strict foreground priority over optional aggregation.
	world._commit_queue.append(VoxelWorld.CommitItem.new(Vector2i(99, 99),
		ChunkMesher.MeshResult.new(), 0, 0, true))
	world._process_lod_batch_queue()
	_expect(world._lod_batches.is_empty() and not world._lod_batch_queue.is_empty(),
		"batch upload ran while a commit was waiting")
	world._commit_queue.clear()
	world._process_lod_batch_queue()
	var stats := world.get_lod_batch_stats()
	_expect(int(stats["batches"]) == 1, "eligible 2x2 LOD group was not batched")
	_expect(int(stats["batched members"]) == 4, "batch did not own all four compact chunks")
	_expect(int(stats["visible lod members"]) == 0, "batched chunks also rendered source meshes")
	_expect(int(stats["invalid batches"]) == 0, "batch node/member state is invalid")
	_expect(int(stats["duplicate members"]) == 0, "a compact chunk appears in more than one batch")
	var batch: VoxelWorld.LodRenderBatch = world._lod_batches.get(Vector2i(10, 10))
	_expect(batch != null and batch.mesh.mesh != null, "batch did not produce an opaque mesh")
	if batch != null and batch.mesh.mesh != null:
		var arrays: Array = batch.mesh.mesh.surface_get_arrays(0)
		_expect(arrays[Mesh.ARRAY_CUSTOM0] is PackedFloat32Array,
			"batched mesh lost block-light custom attribute")
		_expect(arrays[Mesh.ARRAY_CUSTOM1] is PackedFloat32Array,
			"batched mesh lost texture-layer custom attribute")
		_expect((arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() == 24,
			"batched mesh did not preserve all source triangles")
	_expect(batch == null or batch.mesh.get_child_count() == 0,
		"render-only batch unexpectedly owns collision nodes")
	# Fill the bounded queue with closer entries, then prove a farther eligible
	# group rejected at that moment is revisited after the queue drains. Refill
	# scans the desired grid incrementally; it owns no unbounded candidate list.
	world._invalidate_lod_batch(Vector2i(10, 10))
	for z in 8:
		for x in 8:
			world._queue_lod_batch_for(Vector2i(x * 2 + 2, z * 2 + 2))
	_expect(world._lod_batch_queue.size() == VoxelWorld.MAX_QUEUED_LOD_BATCHES,
		"near candidate setup did not fill the bounded LOD batch queue")
	world._queue_lod_batch_for(group[0])
	_expect(not world._lod_batch_queued.has(Vector2i(10, 10)),
		"a farther group unexpectedly bypassed a full nearest queue")
	world._lod_batch_queue.clear()
	world._lod_batch_queued.clear()
	world._reset_lod_batch_refill()
	for _scan in 70:
		world._refill_lod_batch_queue()
	_expect(not world._lod_batch_queue.is_empty(), "bounded refill did not revisit an eligible group")
	world._process_lod_batch_queue()
	world._free_chunk(group[0])
	stats = world.get_lod_batch_stats()
	_expect(int(stats["batches"]) == 0, "unloading a source did not invalidate its batch")
	for pos in group.slice(1):
		var remaining: VoxelWorld.Chunk = world._chunks[pos]
		_expect(remaining.mesh.visible, "batch invalidation left a surviving source hidden")
	# A pathological source buffer must remain visible rather than making one
	# nonpreemptible main-thread aggregate larger than the documented cap.
	var cap_group := [Vector2i(30, 30), Vector2i(31, 30), Vector2i(30, 31), Vector2i(31, 31)]
	for index in cap_group.size():
		var pos: Vector2i = cap_group[index]
		world._desired[pos] = true
		var chunk := world._create_chunk_nodes(pos)
		chunk.lod = true
		chunk.mesh.mesh = _source_mesh(world,
			VoxelWorld.MAX_LOD_BATCH_VERTICES + 1 if index == 0 else 4)
		world._chunks[pos] = chunk
		world._queue_lod_batch_for(pos)
	var rejected_before := world._lod_batch_geometry_rejected
	world._process_lod_batch_queue()
	_expect(world._lod_batch_geometry_rejected == rejected_before + 1,
		"oversized LOD group was not rejected before upload")
	_expect(not world._lod_batches.has(Vector2i(15, 15)),
		"oversized LOD group created a render batch")
	_expect((world._chunks[cap_group[0]] as VoxelWorld.Chunk).mesh.visible,
		"oversized LOD source was hidden instead of retained")
	_expect(not world._lod_batch_is_eligible(Vector2i(15, 15)),
		"oversized group would be retried on every refill pass")
	world._invalidate_lod_batch(Vector2i(15, 15))
	_expect(world._lod_batch_is_eligible(Vector2i(15, 15)),
		"member invalidation did not allow the group to be reconsidered")
	world._lod_batch_queue.clear()
	world._lod_batch_queued.clear()
	world._lod_batch_refill_complete = true
	var idle_cursor := world._lod_batch_refill_cursor
	world._process_lod_batch_queue()
	_expect(world._lod_batch_refill_cursor == idle_cursor,
		"settled batching continued scanning the desired grid")
	world._queue_lod_batch_for(cap_group[0])
	_expect(not world._lod_batch_refill_complete,
		"new chunk work did not wake settled batching")

	# No batch scheduling is a worker task, so it cannot consume urgent capacity.
	_expect(world._pending.is_empty(), "LOD batch scheduling submitted a worker job")
	world.set_lod_batching_enabled(false)
	_expect(int(world.get_lod_batch_stats()["batches"]) == 0,
		"disabling batching did not reveal/remove all aggregates")
	_expect(world._lod_batch_queue.is_empty(), "disabling batching retained upload requests")
	world.free()
	for failure in _failures:
		push_error(failure)
	print("LOD BATCH VERIFY: %s" % ("PASS" if _failures.is_empty() else "FAIL"))
	quit(0 if _failures.is_empty() else 1)


func _source_mesh(world: VoxelWorld, vertex_count: int = 4) -> ArrayMesh:
	var vertices := PackedVector3Array([
		Vector3.ZERO, Vector3(1.0, 0.0, 0.0), Vector3(1.0, 0.0, 1.0), Vector3(0.0, 0.0, 1.0),
	])
	var normals := PackedVector3Array([Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP])
	var uvs := PackedVector2Array([Vector2.ZERO, Vector2.RIGHT, Vector2.ONE, Vector2.DOWN])
	var colors := PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE])
	var light := PackedFloat32Array([0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0,
		0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0])
	var layers := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
	var indices := PackedInt32Array([0, 2, 1, 0, 3, 2])
	if vertex_count > 4:
		vertices.resize(vertex_count)
		normals.resize(vertex_count)
		uvs.resize(vertex_count)
		colors.resize(vertex_count)
		light.resize(vertex_count * 4)
		layers.resize(vertex_count)
		vertices[0] = Vector3.ZERO
		vertices[1] = Vector3.RIGHT
		vertices[2] = Vector3.FORWARD
		for index in vertex_count:
			normals[index] = Vector3.UP
			colors[index] = Color.WHITE
	return ChunkMesher.arrays_to_mesh(vertices, normals, uvs, colors, indices,
		world.get_registry().material, light, layers)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
