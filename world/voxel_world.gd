class_name VoxelWorld
extends Node3D

const SPAWN_RADIUS := 1
const SPAWN_SEARCH_RADIUS := 12
const MAX_ACTIVE_JOBS := 12
const COMMIT_BUDGET_MS := 5
const REBUILD_OPPOSITE_BITS := [2, 1, 8, 4]

var render_distance := 10
var unload_radius := 12

var _blocks: BlockRegistry
var _generator: TerrainGenerator
var _mesher: ChunkMesher

var _chunks: Dictionary = {}
var _pending: Dictionary = {}
var _commit_queue: Array = []
var _gen_queue: Array[Vector2i] = []
var _gen_queued: Dictionary = {}
var _dirty: Dictionary = {}
var _desired: Dictionary = {}
var _edited_blocks: Dictionary = {}
var _chunk_edit_version: Dictionary = {}
var _stream_center := Vector2i(999999, 999999)
var _player: Node3D


class Chunk:
	var data := PackedByteArray()
	var max_y := 0
	var mask := 0
	var mesh: MeshInstance3D
	var water: MeshInstance3D
	var body: StaticBody3D
	var shape: CollisionShape3D


class PendingJob:
	var task := -1
	var version := 0
	var slot: Dictionary = {}


class CommitItem:
	var pos := Vector2i.ZERO
	var result: ChunkMesher.MeshResult
	var version := 0

	func _init(p_pos: Vector2i, p_result: ChunkMesher.MeshResult, p_version: int) -> void:
		pos = p_pos
		result = p_result
		version = p_version


func _ready() -> void:
	_blocks = BlockRegistry.new()
	_generator = TerrainGenerator.new()
	_mesher = ChunkMesher.new(_blocks)


func _process(_delta: float) -> void:
	if _player == null:
		return
	_stream_tick()


func _exit_tree() -> void:
	for pos in _pending.keys():
		WorkerThreadPool.wait_for_task_completion((_pending[pos] as PendingJob).task)
	_pending.clear()


## Must run before setup_player() and must not be called while chunk jobs are
## in flight: recreating the noise set invalidates running workers.
func configure(world_config: Dictionary, render_distance_chunks: int) -> void:
	render_distance = maxi(render_distance_chunks, 1)
	unload_radius = render_distance + 2
	_generator.configure(world_config)


func set_render_distance(value: int) -> void:
	render_distance = maxi(value, 1)
	unload_radius = render_distance + 2
	_rebuild_desired()


func setup_player(player_node: Node3D) -> void:
	_player = player_node
	_stream_center = _chunk_for_position(player_node.global_position)
	_generate_spawn_area()
	_rebuild_desired()
	_schedule_jobs()


func _stream_tick() -> void:
	var center := _chunk_for_position(_player.global_position)
	if center != _stream_center:
		_stream_center = center
		_rebuild_desired()
	_collect_jobs()
	_process_commit_queue()
	_schedule_jobs()
	_unload_far()


func _generate_spawn_area() -> void:
	for ring in range(SPAWN_RADIUS + 1):
		for dx in range(-ring, ring + 1):
			for dz in range(-ring, ring + 1):
				if maxi(absi(dx), absi(dz)) != ring:
					continue
				var pos := _stream_center + Vector2i(dx, dz)
				if _chunks.has(pos):
					continue
				var slot: Dictionary = {}
				_run_chunk_job(pos, _edited_blocks.duplicate(), _gather_neighbors(pos), slot)
				if slot.has("result"):
					_commit_chunk(pos, slot["result"])


func _rebuild_desired() -> void:
	_desired.clear()
	var wanted: Array[Vector2i] = []
	for dx in range(-render_distance, render_distance + 1):
		for dz in range(-render_distance, render_distance + 1):
			var pos := _stream_center + Vector2i(dx, dz)
			_desired[pos] = true
			if not _chunks.has(pos) and not _pending.has(pos):
				wanted.append(pos)
	var center := _stream_center
	wanted.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return (a - center).length_squared() < (b - center).length_squared()
	)
	_gen_queue = wanted
	_gen_queued.clear()
	for pos in _gen_queue:
		_gen_queued[pos] = true
	for pos in _dirty.keys():
		if _desired.has(pos) and not _pending.has(pos) and not _gen_queued.has(pos):
			_gen_queue.push_front(pos)
			_gen_queued[pos] = true


func _schedule_jobs() -> void:
	if _gen_queue.is_empty():
		return
	var edits_snapshot := _edited_blocks.duplicate()
	while _pending.size() < MAX_ACTIVE_JOBS and not _gen_queue.is_empty():
		var pos: Vector2i = _gen_queue.pop_front()
		_gen_queued.erase(pos)
		if _pending.has(pos):
			continue
		if _chunks.has(pos) and not _dirty.has(pos):
			continue
		_dirty.erase(pos)
		var job := PendingJob.new()
		job.version = _chunk_edit_version.get(pos, 0)
		job.slot = {}
		job.task = WorkerThreadPool.add_task(
			_run_chunk_job.bind(pos, edits_snapshot, _gather_neighbors(pos), job.slot),
			true,
			"voxel_chunk")
		_pending[pos] = job


func _process_commit_queue() -> void:
	var start := Time.get_ticks_msec()
	while not _commit_queue.is_empty():
		var item: CommitItem = _commit_queue.pop_front()
		if not _desired.has(item.pos):
			continue
		if item.version != _chunk_edit_version.get(item.pos, 0):
			_queue_rebuild(item.pos)
			continue
		_commit_chunk(item.pos, item.result)
		if Time.get_ticks_msec() - start > COMMIT_BUDGET_MS:
			break


func _collect_jobs() -> void:
	for pos in _pending.keys():
		var job: PendingJob = _pending[pos]
		if not WorkerThreadPool.is_task_completed(job.task):
			continue
		WorkerThreadPool.wait_for_task_completion(job.task)
		_pending.erase(pos)
		if job.slot.has("result"):
			_commit_queue.append(CommitItem.new(pos, job.slot["result"], job.version))


## Worker-thread entry point. Only reads state that is immutable while jobs
## are in flight (generator noise set, mesher tables, block registry).
func _run_chunk_job(chunk_pos: Vector2i, edits: Dictionary, neighbors: ChunkMesher.NeighborSet, slot: Dictionary) -> void:
	var generated := _generator.generate_data(chunk_pos, edits)
	slot["result"] = _mesher.build(generated.data, generated.max_y, neighbors)


func _gather_neighbors(pos: Vector2i) -> ChunkMesher.NeighborSet:
	var out := ChunkMesher.NeighborSet.new()
	for index in VoxelDefs.DIRS_8.size():
		var direction: Vector2i = VoxelDefs.DIRS_8[index]
		var chunk: Chunk = _chunks.get(pos + direction)
		if chunk == null:
			continue
		out.samples[direction] = ChunkMesher.NeighborSample.new(chunk.data.duplicate(), chunk.max_y)
		if index < 4:
			out.mask |= (1 << index)
	return out


func _commit_chunk(pos: Vector2i, res: ChunkMesher.MeshResult) -> void:
	var chunk: Chunk = _chunks.get(pos)
	if chunk == null:
		chunk = _create_chunk_nodes(pos)
		_chunks[pos] = chunk
	chunk.data = res.data
	chunk.max_y = res.max_y
	chunk.mask = res.mask
	chunk.mesh.mesh = ChunkMesher.arrays_to_mesh(res.verts, res.normals, res.uvs, res.colors, res.indices, _blocks.material, res.light)
	chunk.water.mesh = ChunkMesher.arrays_to_mesh(res.water_verts, res.water_normals, res.water_uvs, res.water_colors, res.water_indices, _blocks.water_material)
	if res.collision.is_empty():
		chunk.shape.shape = null
	else:
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(res.collision)
		shape.backface_collision = true
		chunk.shape.shape = shape
	_remesh_on_commit_neighbors(pos)


func _create_chunk_nodes(pos: Vector2i) -> Chunk:
	var chunk := Chunk.new()
	var chunk_origin := Vector3(pos.x * VoxelDefs.CHUNK_SIZE, 0.0, pos.y * VoxelDefs.CHUNK_SIZE)
	chunk.mesh = MeshInstance3D.new()
	chunk.mesh.name = "Chunk_%d_%d" % [pos.x, pos.y]
	chunk.mesh.position = chunk_origin
	add_child(chunk.mesh)
	chunk.water = MeshInstance3D.new()
	chunk.water.name = "Water_%d_%d" % [pos.x, pos.y]
	chunk.water.position = chunk_origin
	chunk.water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(chunk.water)
	chunk.body = StaticBody3D.new()
	chunk.body.name = "Body_%d_%d" % [pos.x, pos.y]
	chunk.body.position = chunk_origin
	chunk.body.collision_layer = VoxelDefs.COLLISION_LAYER_WORLD
	chunk.body.collision_mask = 0
	add_child(chunk.body)
	chunk.shape = CollisionShape3D.new()
	chunk.body.add_child(chunk.shape)
	return chunk


func _remesh_on_commit_neighbors(pos: Vector2i) -> void:
	for index in VoxelDefs.DIRS_4.size():
		var neighbor: Chunk = _chunks.get(pos + VoxelDefs.DIRS_4[index])
		if neighbor == null:
			continue
		if (neighbor.mask & REBUILD_OPPOSITE_BITS[index]) == 0:
			_queue_rebuild(pos + VoxelDefs.DIRS_4[index])


func _queue_rebuild(pos: Vector2i) -> void:
	if _pending.has(pos) or _gen_queued.has(pos):
		return
	_dirty[pos] = true
	_gen_queue.push_front(pos)
	_gen_queued[pos] = true


func _unload_far() -> void:
	for pos in _chunks.keys():
		if maxi(absi(pos.x - _stream_center.x), absi(pos.y - _stream_center.y)) > unload_radius:
			_free_chunk(pos)


func _free_chunk(pos: Vector2i) -> void:
	var chunk: Chunk = _chunks.get(pos)
	if chunk == null:
		return
	chunk.mesh.queue_free()
	chunk.water.queue_free()
	chunk.body.queue_free()
	_chunks.erase(pos)


func _chunk_for_position(world_position: Vector3) -> Vector2i:
	return Vector2i(
		floori(world_position.x / float(VoxelDefs.CHUNK_SIZE)),
		floori(world_position.z / float(VoxelDefs.CHUNK_SIZE))
	)


func _chunk_for_block(block_position: Vector3i) -> Vector2i:
	return Vector2i(
		floori(float(block_position.x) / float(VoxelDefs.CHUNK_SIZE)),
		floori(float(block_position.z) / float(VoxelDefs.CHUNK_SIZE))
	)


func _loaded_chunk_for(block_position: Vector3i) -> Chunk:
	if block_position.y < 0 or block_position.y >= VoxelDefs.WORLD_HEIGHT:
		return null
	return _chunks.get(_chunk_for_block(block_position))


func _data_index(block_position: Vector3i) -> int:
	var chunk_position := _chunk_for_block(block_position)
	var local_x := block_position.x - chunk_position.x * VoxelDefs.CHUNK_SIZE
	var local_z := block_position.z - chunk_position.y * VoxelDefs.CHUNK_SIZE
	return local_x + local_z * VoxelDefs.DATA_STRIDE_Z + block_position.y * VoxelDefs.DATA_STRIDE_Y


func get_block_world(block_position: Vector3i) -> int:
	var chunk := _loaded_chunk_for(block_position)
	if chunk == null:
		return BlockRegistry.BLOCK_AIR
	return chunk.data[_data_index(block_position)]


func is_water_at(world_position: Vector3) -> bool:
	return get_block_world(Vector3i(floori(world_position.x), floori(world_position.y), floori(world_position.z))) == BlockRegistry.BLOCK_WATER


func break_block(block_position: Vector3i) -> int:
	if block_position.y <= 0:
		return BlockRegistry.BLOCK_AIR
	var chunk_position := _chunk_for_block(block_position)
	var chunk: Chunk = _chunks.get(chunk_position)
	if chunk == null:
		return BlockRegistry.BLOCK_AIR
	var index := _data_index(block_position)
	var block_id: int = chunk.data[index]
	if not _blocks.is_breakable(block_id):
		return BlockRegistry.BLOCK_AIR
	chunk.data[index] = BlockRegistry.BLOCK_AIR
	_edited_blocks[block_position] = BlockRegistry.BLOCK_AIR
	_touch_chunk(chunk_position, block_position)
	return block_id


func place_block(block_position: Vector3i, block_id: int) -> bool:
	if not _blocks.is_valid_id(block_id):
		return false
	if block_position.y < 0 or block_position.y >= VoxelDefs.WORLD_HEIGHT:
		return false
	var chunk_position := _chunk_for_block(block_position)
	var chunk: Chunk = _chunks.get(chunk_position)
	if chunk == null:
		return false
	var index := _data_index(block_position)
	if chunk.data[index] != BlockRegistry.BLOCK_AIR:
		return false
	chunk.data[index] = block_id
	_edited_blocks[block_position] = block_id
	_touch_chunk(chunk_position, block_position)
	return true


func _touch_chunk(chunk_position: Vector2i, block_position: Vector3i) -> void:
	_chunk_edit_version[chunk_position] = _chunk_edit_version.get(chunk_position, 0) + 1
	_queue_rebuild(chunk_position)
	var local_x := block_position.x - chunk_position.x * VoxelDefs.CHUNK_SIZE
	var local_z := block_position.z - chunk_position.y * VoxelDefs.CHUNK_SIZE
	if local_x == 0:
		_queue_rebuild(chunk_position + Vector2i(-1, 0))
	elif local_x == VoxelDefs.CHUNK_SIZE - 1:
		_queue_rebuild(chunk_position + Vector2i(1, 0))
	if local_z == 0:
		_queue_rebuild(chunk_position + Vector2i(0, -1))
	elif local_z == VoxelDefs.CHUNK_SIZE - 1:
		_queue_rebuild(chunk_position + Vector2i(0, 1))


func get_spawn_position() -> Vector3:
	return _generator.find_spawn_position()


## Returns the closest column to `desired` whose topmost block is a solid,
## non-foliage block with two air cells above it. Requires the spawn-area
## chunks to be generated; falls back to `desired` when nothing is found.
func find_safe_spawn(desired: Vector3) -> Vector3:
	var base_x := floori(desired.x)
	var base_z := floori(desired.z)
	var scan_top := mini(floori(desired.y) + 20, VoxelDefs.WORLD_HEIGHT - 3)
	for radius in range(0, SPAWN_SEARCH_RADIUS + 1):
		for dx in range(-radius, radius + 1):
			for dz in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dz)) != radius:
					continue
				var ground_y := _find_column_spawn(base_x + dx, base_z + dz, scan_top)
				if ground_y >= 0:
					return Vector3(float(base_x + dx) + 0.5, float(ground_y) + 1.5, float(base_z + dz) + 0.5)
	return desired


func _find_column_spawn(block_x: int, block_z: int, scan_top: int) -> int:
	for y in range(scan_top, 0, -1):
		var id := get_block_world(Vector3i(block_x, y, block_z))
		if id == BlockRegistry.BLOCK_AIR:
			continue
		if not _blocks.is_opaque(id):
			return -1
		if get_block_world(Vector3i(block_x, y + 1, block_z)) != BlockRegistry.BLOCK_AIR:
			return -1
		if get_block_world(Vector3i(block_x, y + 2, block_z)) != BlockRegistry.BLOCK_AIR:
			return -1
		return y
	return -1


func get_block_name(block_id: int) -> String:
	return _blocks.get_block_name(block_id)


func get_biome_name(world_position: Vector3) -> String:
	return _generator.biome_name(world_position)


func get_loaded_chunk_count() -> int:
	return _chunks.size()


func get_blocks_material() -> Material:
	return _blocks.material


func make_block_mesh(block_id: int) -> ArrayMesh:
	return _mesher.make_block_mesh(block_id)
