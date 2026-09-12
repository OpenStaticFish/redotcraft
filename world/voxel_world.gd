class_name VoxelWorld
extends Node3D

const SPAWN_RADIUS := 1
const SPAWN_SEARCH_RADIUS := 12
const MAX_ACTIVE_JOBS := 12
const COMMIT_BUDGET_MS := 5
const REBUILD_OPPOSITE_BITS := [2, 1, 8, 4]
const WATER_TICK_INTERVAL := 0.25
const WATER_CELLS_PER_TICK := 1024
const WATER_NEIGHBOR_OFFSETS := [
	Vector3i.ZERO,
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
	Vector3i(0, 1, 0), Vector3i(0, -1, 0),
	Vector3i(0, 0, 1), Vector3i(0, 0, -1),
]

var render_distance := 10
var lod_distance := 5
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
var _edits_by_chunk: Dictionary = {}
var _chunk_edit_version: Dictionary = {}
var _stream_center := Vector2i(999999, 999999)
var _player: Node3D
var _water_queue: Array[Vector3i] = []
var _water_queued: Dictionary = {}
var _water_head := 0
var _water_accum := 0.0


class Chunk:
	var data := PackedByteArray()
	var heights := PackedByteArray()
	var max_y := 0
	var mask := 0
	var lod := false
	var mesh: MeshInstance3D
	var water: MeshInstance3D
	var body: StaticBody3D
	var shape: CollisionShape3D


class PendingJob:
	var task := -1
	var version := 0
	var lod := false
	var slot: Dictionary = {}


class CommitItem:
	var pos := Vector2i.ZERO
	var result: ChunkMesher.MeshResult
	var version := 0
	var lod := false

	func _init(p_pos: Vector2i, p_result: ChunkMesher.MeshResult, p_version: int, p_lod: bool) -> void:
		pos = p_pos
		result = p_result
		version = p_version
		lod = p_lod


func _ready() -> void:
	_blocks = BlockRegistry.new()
	_generator = TerrainGenerator.new()
	_mesher = ChunkMesher.new(_blocks)


func _process(delta: float) -> void:
	if _player == null:
		return
	_stream_tick()
	_water_accum += delta
	if _water_accum >= WATER_TICK_INTERVAL:
		_water_accum = 0.0
		_water_tick()


func _exit_tree() -> void:
	for pos in _pending.keys():
		WorkerThreadPool.wait_for_task_completion((_pending[pos] as PendingJob).task)
	_pending.clear()


## Must run before setup_player() and must not be called while chunk jobs are
## in flight: recreating the noise set invalidates running workers.
func configure(world_config: Dictionary, render_distance_chunks: int) -> void:
	render_distance = maxi(render_distance_chunks, 1)
	lod_distance = maxi(3, render_distance / 2)
	unload_radius = render_distance + 2
	_generator.configure(world_config)


func set_render_distance(value: int) -> void:
	render_distance = maxi(value, 1)
	lod_distance = maxi(3, render_distance / 2)
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
				_run_chunk_job(pos, _chunk_edits_for(pos), _gather_neighbors(pos), slot, false)
				if slot.has("result"):
					_commit_chunk(pos, slot["result"], false)


func _rebuild_desired() -> void:
	_desired.clear()
	var wanted: Array[Vector2i] = []
	for dx in range(-render_distance, render_distance + 1):
		for dz in range(-render_distance, render_distance + 1):
			var pos := _stream_center + Vector2i(dx, dz)
			_desired[pos] = true
			var want_lod := _chunk_uses_lod(pos)
			if _chunks.has(pos) and (_chunks[pos] as Chunk).lod != want_lod:
				_dirty[pos] = true
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
	while _pending.size() < MAX_ACTIVE_JOBS and not _gen_queue.is_empty():
		var pos: Vector2i = _gen_queue.pop_front()
		_gen_queued.erase(pos)
		if _pending.has(pos):
			continue
		if _chunks.has(pos) and not _dirty.has(pos):
			continue
		_dirty.erase(pos)
		var lod := _chunk_uses_lod(pos)
		var job := PendingJob.new()
		job.version = _chunk_edit_version.get(pos, 0)
		job.lod = lod
		job.slot = {}
		job.task = WorkerThreadPool.add_task(
			_run_chunk_job.bind(pos, _chunk_edits_for(pos), _gather_job_neighbors(pos, lod), job.slot, lod),
			true,
			"voxel_chunk")
		_pending[pos] = job


func _process_commit_queue() -> void:
	var start := Time.get_ticks_msec()
	while not _commit_queue.is_empty():
		var item: CommitItem = _commit_queue.pop_front()
		if not _desired.has(item.pos):
			continue
		if item.version != _chunk_edit_version.get(item.pos, 0) or item.lod != _chunk_uses_lod(item.pos):
			_queue_rebuild(item.pos)
			continue
		_commit_chunk(item.pos, item.result, item.lod)
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
			_commit_queue.append(CommitItem.new(pos, job.slot["result"], job.version, job.lod))


## Worker-thread entry point. Only reads state that is immutable while jobs
## are in flight (generator noise set, mesher tables, block registry).
func _run_chunk_job(chunk_pos: Vector2i, edits: Dictionary, neighbors, slot: Dictionary, lod: bool) -> void:
	var generated := _generator.generate_data(chunk_pos, edits)
	if lod:
		slot["result"] = _mesher.build_lod(generated.data, generated.max_y, generated.heights, neighbors)
	else:
		slot["result"] = _mesher.build(generated.data, generated.max_y, generated.heights, neighbors)


func _chunk_uses_lod(pos: Vector2i) -> bool:
	return maxi(absi(pos.x - _stream_center.x), absi(pos.y - _stream_center.y)) > lod_distance


func _gather_job_neighbors(pos: Vector2i, lod: bool):
	if lod:
		return _gather_lod_neighbors(pos)
	return _gather_neighbors(pos)


func _gather_lod_neighbors(pos: Vector2i) -> ChunkMesher.LodNeighbors:
	var out := ChunkMesher.LodNeighbors.new()
	for index in VoxelDefs.DIRS_4.size():
		var direction: Vector2i = VoxelDefs.DIRS_4[index]
		var chunk: Chunk = _chunks.get(pos + direction)
		if chunk == null:
			continue
		out.edges[direction] = _build_lod_edge(chunk, direction)
		out.mask |= (1 << index)
	return out


func _build_lod_edge(chunk: Chunk, direction: Vector2i) -> ChunkMesher.LodEdge:
	var edge := ChunkMesher.LodEdge.new()
	edge.solid.resize(VoxelDefs.CHUNK_SIZE)
	edge.water.resize(VoxelDefs.CHUNK_SIZE)
	for index in VoxelDefs.CHUNK_SIZE:
		var local_x := index if direction.y != 0 else (0 if direction.x > 0 else VoxelDefs.CHUNK_SIZE - 1)
		var local_z := index if direction.x != 0 else (0 if direction.y > 0 else VoxelDefs.CHUNK_SIZE - 1)
		var column := local_x + local_z * VoxelDefs.DATA_STRIDE_Z
		var solid := ChunkMesher.LOD_NONE
		var water := ChunkMesher.LOD_NONE
		for y in range(chunk.max_y, -1, -1):
			var id: int = chunk.data[column + y * VoxelDefs.DATA_STRIDE_Y]
			if id == BlockRegistry.BLOCK_AIR:
				continue
			if _blocks.is_water_id(id):
				if water == ChunkMesher.LOD_NONE:
					water = y
				continue
			if _blocks.has_flag(id, BlockRegistry.FLAG_CROSS):
				continue
			solid = y
			break
		edge.solid[index] = solid
		edge.water[index] = water
	return edge


func _gather_neighbors(pos: Vector2i) -> ChunkMesher.NeighborSet:
	var out := ChunkMesher.NeighborSet.new()
	for index in VoxelDefs.DIRS_8.size():
		var direction: Vector2i = VoxelDefs.DIRS_8[index]
		var chunk: Chunk = _chunks.get(pos + direction)
		if chunk == null:
			continue
		out.samples[direction] = ChunkMesher.NeighborSample.new(chunk.data.duplicate(), chunk.max_y, chunk.heights.duplicate())
		if index < 4:
			out.mask |= (1 << index)
	return out


func _commit_chunk(pos: Vector2i, res: ChunkMesher.MeshResult, lod: bool) -> void:
	var chunk: Chunk = _chunks.get(pos)
	if chunk == null:
		chunk = _create_chunk_nodes(pos)
		_chunks[pos] = chunk
	chunk.lod = lod
	chunk.data = res.data
	chunk.heights = res.heights
	chunk.max_y = res.max_y
	chunk.mask = res.mask
	chunk.mesh.mesh = ChunkMesher.arrays_to_mesh(res.verts, res.normals, res.uvs, res.colors, res.indices, _blocks.material, res.light, res.layers)
	chunk.water.mesh = ChunkMesher.arrays_to_mesh(res.water_verts, res.water_normals, res.water_uvs, res.water_colors, res.water_indices, _blocks.water_material, res.water_light)
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
	return _blocks.is_water_id(get_block_world(Vector3i(floori(world_position.x), floori(world_position.y), floori(world_position.z))))


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
	_record_edit(block_position, BlockRegistry.BLOCK_AIR)
	_touch_chunk(chunk_position, block_position)
	_seed_water(block_position)
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
	var existing: int = chunk.data[index]
	if existing != BlockRegistry.BLOCK_AIR and not _blocks.is_water_id(existing):
		return false
	chunk.data[index] = block_id
	_record_edit(block_position, block_id)
	_touch_chunk(chunk_position, block_position)
	_seed_water(block_position)
	return true


func _record_edit(block_position: Vector3i, block_id: int) -> void:
	_edited_blocks[block_position] = block_id
	var chunk_position := _chunk_for_block(block_position)
	var bucket = _edits_by_chunk.get(chunk_position)
	if bucket == null:
		bucket = {}
		_edits_by_chunk[chunk_position] = bucket
	bucket[block_position] = block_id


func _chunk_edits_for(pos: Vector2i) -> Dictionary:
	var bucket = _edits_by_chunk.get(pos)
	if bucket == null:
		return {}
	return bucket.duplicate()


func _seed_water(block_position: Vector3i) -> void:
	for offset in WATER_NEIGHBOR_OFFSETS:
		_queue_water(block_position + offset)


func _queue_water(position: Vector3i) -> void:
	if position.y < 1 or position.y >= VoxelDefs.WORLD_HEIGHT:
		return
	if _water_queued.has(position):
		return
	_water_queued[position] = true
	_water_queue.append(position)


## Cellular flow: only runs for cells seeded by edits or by nearby water
## changes, so oceans and lakes stay static until disturbed.
func _water_tick() -> void:
	var budget := WATER_CELLS_PER_TICK
	while budget > 0 and _water_head < _water_queue.size():
		var position: Vector3i = _water_queue[_water_head]
		_water_head += 1
		budget -= 1
		_water_queued.erase(position)
		if _loaded_chunk_for(position) == null:
			continue
		_update_water_cell(position)
	if _water_head == _water_queue.size():
		_water_queue.clear()
		_water_head = 0
	elif _water_head > 4096:
		_water_queue = _water_queue.slice(_water_head)
		_water_head = 0


func _update_water_cell(position: Vector3i) -> void:
	var id := get_block_world(position)
	if id != BlockRegistry.BLOCK_AIR and not _blocks.is_water_id(id):
		return
	var is_source := id == BlockRegistry.BLOCK_WATER
	var current_level := _blocks.water_level(id)
	var feed := 0
	if _blocks.is_water_id(get_block_world(position + Vector3i(0, 1, 0))):
		feed = 7
	for direction in VoxelDefs.DIRS_4:
		var neighbor := get_block_world(position + Vector3i(direction.x, 0, direction.y))
		if not _blocks.is_water_id(neighbor):
			continue
		feed = maxi(feed, 7 if neighbor == BlockRegistry.BLOCK_WATER else _blocks.water_level(neighbor) - 1)
	if is_source:
		feed = 8
	if feed != current_level:
		_water_place(position, _blocks.water_id_for_level(feed))
	if feed <= 0:
		return
	var below := get_block_world(position + Vector3i(0, -1, 0))
	if below == BlockRegistry.BLOCK_AIR:
		if position.y > 1:
			_water_place(position + Vector3i(0, -1, 0), _blocks.water_id_for_level(7))
		return
	if feed <= 1:
		return
	for direction in VoxelDefs.DIRS_4:
		var target := position + Vector3i(direction.x, 0, direction.y)
		var target_id := get_block_world(target)
		if target_id == BlockRegistry.BLOCK_AIR:
			_water_place(target, _blocks.water_id_for_level(feed - 1))
		elif _blocks.is_water_id(target_id) and target_id != BlockRegistry.BLOCK_WATER and _blocks.water_level(target_id) < feed - 1:
			_water_place(target, _blocks.water_id_for_level(feed - 1))


func _water_place(position: Vector3i, block_id: int) -> void:
	var chunk := _loaded_chunk_for(position)
	if chunk == null:
		return
	var index := _data_index(position)
	if chunk.data[index] == block_id:
		return
	chunk.data[index] = block_id
	_record_edit(position, block_id)
	_touch_chunk(_chunk_for_block(position), position)
	for offset in WATER_NEIGHBOR_OFFSETS:
		_queue_water(position + offset)


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
