class_name VoxelWorld
extends Node3D

const SPAWN_RADIUS := 1
const SPAWN_SEARCH_RADIUS := 12
## Half the logical cores, capped at 8. Measured on a 16-thread desktop: 8
## concurrent chunk jobs stream ~40% faster than 4, while 16 adds only ~10%
## more and risks starving the main thread on smaller machines. One additional
## high-priority near-player job may be submitted when all normal slots are
## occupied, preventing stale distant work from starving collision recovery.
const MIN_ACTIVE_JOBS := 4
const MAX_ACTIVE_JOBS := 8
## Collision shapes are only built for chunks near the player; approaching a
## distant full chunk rebuilds it to add collision instead of holding a shape
## for every loaded chunk.
const COLLISION_DISTANCE := 6
## Full-detail voxel arrays are immutable between edits. Once they are beyond
## interaction range, retain their authoritative metadata but store voxel IDs
## as a deterministic palette followed by little-endian RLE runs.
const CHUNK_DATA_RLE_HEADER_BYTES := 6
const LOD_MODE_FULL := 0
const LOD_MODE_BALANCED := 1
const BALANCED_FULL_DETAIL_DISTANCE := COLLISION_DISTANCE + 2
const STREAM_BOUNDARY_MARGIN := 0.05
## Palette/RLE cold storage is retained as a verified codec, but production
## compaction is disabled. Live flight profiling showed repeated neighbor
## decodes caused stream stutter, and a stale compressed snapshot could reach a
## remesh as a short array. Balanced LOD provides the memory saving without
## putting compression in the active meshing path.
const ENABLE_COLD_CHUNK_COMPRESSION := false
const COMMIT_BUDGET_MS := 2
## Diagnostic map rasters resolve one mode sample per pixel. The final-height
## family walks the erosion graph five times per sample, so map views request
## fewer pixels for those modes instead of freezing their refresh for seconds.
const DEBUG_MAP_MAX_RESOLUTION := 128
const DEBUG_MAP_HEAVY_RESOLUTION := 64
const DEBUG_MAP_HEAVY_MODES: Array[String] = ["height", "raw_height", "slope"]
const REBUILD_OPPOSITE_BITS := [2, 1, 8, 4, 128, 64, 32, 16]
const WATER_TICK_INTERVAL := 0.25
const WATER_CELLS_PER_TICK := 1024
const TNT_BLAST_RADIUS := 5
const NUKE_BLAST_RADIUS := 18
## Fire advances in discrete steps like water. A flammable block is never
## replaced: it enters a "burning" state (see `_burning`) for `FUEL_BURN_TICKS`
## while `FireOverlay` animates flames and smoke over its intact texture, then
## the block is destroyed. Burning blocks crawl into flammable neighbours one at
## a time, paced by `FIRE_SPREAD_PER_TICK`/`FIRE_SPREAD_PERIOD_TICKS` globally
## and a per-cell `FIRE_SPREAD_INTERVAL_TICKS`/`FIRE_IGNITION_DELAY_TICKS`
## cooldown, so a tree burns gradually. `BLOCK_FIRE` is only the standalone
## flame the flint-and-steel leaves on a non-flammable face.
const FIRE_TICK_INTERVAL := 0.25
const FIRE_CELLS_PER_TICK := 512
const FIRE_LIFETIME_TICKS := 10
const FUEL_BURN_TICKS := 16
const FIRE_SPREAD_PER_TICK := 1
const FIRE_IGNITION_DELAY_TICKS := 4
const FIRE_SPREAD_PERIOD_TICKS := 2
const FIRE_SPREAD_INTERVAL_TICKS := 2
## Light starts at MAX_LIGHT_LEVEL and attenuates at least one level per cell,
## so its furthest possible affected cell is this many horizontal steps away.
const LIGHT_MAX_PROPAGATION_DISTANCE := BlockRegistry.MAX_LIGHT_LEVEL - 1
const FIRE_OFFSETS: Array[Vector3i] = [
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
	Vector3i(0, 1, 0), Vector3i(0, -1, 0),
	Vector3i(0, 0, 1), Vector3i(0, 0, -1),
]
const WATER_NEIGHBOR_OFFSETS := [
	Vector3i.ZERO,
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
	Vector3i(0, 1, 0), Vector3i(0, -1, 0),
	Vector3i(0, 0, 1), Vector3i(0, 0, -1),
]

var render_distance := 10
var lod_distance := 5
var lod_mode := LOD_MODE_FULL
var unload_radius := 12

var _blocks: BlockRegistry
var _generator: TerrainGenerator
var _mesher: ChunkMesher

var _chunks: Dictionary = {}
var _pending: Dictionary = {}
var _commit_queue: Array = []
var _gen_queue: Array[Vector2i] = []
var _gen_queued: Dictionary = {}
var _mesh_queue: Array[Vector2i] = []
var _mesh_queued: Dictionary = {}
var _generated: Dictionary = {}
var _dirty: Dictionary = {}
var _desired: Dictionary = {}
var _edited_blocks: Dictionary = {}
var _edits_by_chunk: Dictionary = {}
var _hydrated_edit_chunks: Dictionary = {}
var _edit_store: WorldStorage
var _chunk_edit_version: Dictionary = {}
var _stream_center := Vector2i(999999, 999999)
var _player: Node3D
var _water_queue: Array[Vector3i] = []
var _water_queued: Dictionary = {}
var _water_head := 0
var _water_accum := 0.0
var _fire_queue: Array[Vector3i] = []
var _fire_queued: Dictionary = {}
var _fire_accum := 0.0
var _fire_life: Dictionary = {}
var _fire_spread_cooldown: Dictionary = {}
var _fire_spread_budget := 0
var _fire_tick_count := 0
var _burning: Dictionary = {}
var _burning_queue: Array[Vector3i] = []
var _burning_queued: Dictionary = {}
var _fire_overlay: FireOverlay
var _worldgen_revision := 0
var _max_active_jobs := MIN_ACTIVE_JOBS
var _full_jobs_measured := 0
var _lod_jobs_measured := 0
var _generation_ema_ms := 0.0
var _mesh_ema_ms := 0.0
var _terrain_ema_ms := 0.0
var _populate_ema_ms := 0.0
var _debug_task := -1
var _debug_slot: Dictionary = {}
var _debug_key := ""
var _debug_cache: Dictionary = {}


class Chunk:
	var data := PackedByteArray()
	var compressed_data := PackedByteArray()
	var heights := PackedInt32Array()
	var foliage_tints := PackedColorArray()
	var water_tints := PackedColorArray()
	var lod_solid_y := PackedInt32Array()
	var lod_solid_id := PackedByteArray()
	var lod_sub_id := PackedByteArray()
	var lod_water_y := PackedInt32Array()
	var lod_water_level := PackedByteArray()
	var max_y := 0
	var mask := 0
	var lod := false
	var mesh: MeshInstance3D
	var water: MeshInstance3D
	var body: StaticBody3D
	var shape: CollisionShape3D


## The palette uses first-seen ordering, making the representation stable for a
## given voxel array. Runs are [palette_index, length_low, length_high]. The
## raw length and palette count are little-endian uint32/uint16 header fields.
static func compress_chunk_data(raw: PackedByteArray) -> PackedByteArray:
	var palette := PackedByteArray()
	var palette_indices: Dictionary = {}
	for value in raw:
		var block_id := int(value)
		if not palette_indices.has(block_id):
			palette_indices[block_id] = palette.size()
			palette.append(block_id)
	var out := PackedByteArray()
	out.resize(CHUNK_DATA_RLE_HEADER_BYTES)
	var raw_size := raw.size()
	out[0] = raw_size & 0xff
	out[1] = (raw_size >> 8) & 0xff
	out[2] = (raw_size >> 16) & 0xff
	out[3] = (raw_size >> 24) & 0xff
	out[4] = palette.size() & 0xff
	out[5] = (palette.size() >> 8) & 0xff
	out.append_array(palette)
	var start := 0
	while start < raw_size:
		var block_id := raw[start]
		var run_length := 1
		while start + run_length < raw_size and raw[start + run_length] == block_id \
				and run_length < 65535:
			run_length += 1
		out.append(int(palette_indices[int(block_id)]))
		out.append(run_length & 0xff)
		out.append((run_length >> 8) & 0xff)
		start += run_length
	return out


static func decompress_chunk_data(compressed: PackedByteArray) -> PackedByteArray:
	if compressed.size() < CHUNK_DATA_RLE_HEADER_BYTES:
		return PackedByteArray()
	var raw_size := int(compressed[0]) | (int(compressed[1]) << 8) \
			| (int(compressed[2]) << 16) | (int(compressed[3]) << 24)
	var palette_size := int(compressed[4]) | (int(compressed[5]) << 8)
	var offset := CHUNK_DATA_RLE_HEADER_BYTES
	if raw_size == 0:
		return PackedByteArray()
	if raw_size < 0 or palette_size <= 0 or compressed.size() < offset + palette_size:
		return PackedByteArray()
	var palette := compressed.slice(offset, offset + palette_size)
	offset += palette_size
	var raw := PackedByteArray()
	raw.resize(raw_size)
	var written := 0
	while offset + 2 < compressed.size():
		var palette_index := int(compressed[offset])
		var run_length := int(compressed[offset + 1]) | (int(compressed[offset + 2]) << 8)
		offset += 3
		if palette_index >= palette.size() or run_length <= 0 or written + run_length > raw_size:
			return PackedByteArray()
		for index in range(written, written + run_length):
			raw[index] = palette[palette_index]
		written += run_length
	if offset != compressed.size() or written != raw_size:
		return PackedByteArray()
	return raw


class PendingJob:
	var task := -1
	var kind := "generate"
	var version := 0
	var config_revision := 0
	var lod := false
	var want_collision := false
	var slot: Dictionary = {}


class CommitItem:
	var pos := Vector2i.ZERO
	var result: ChunkMesher.MeshResult
	var version := 0
	var config_revision := 0
	var lod := false

	func _init(p_pos: Vector2i, p_result: ChunkMesher.MeshResult, p_version: int,
			p_config_revision: int, p_lod: bool) -> void:
		pos = p_pos
		result = p_result
		version = p_version
		config_revision = p_config_revision
		lod = p_lod


func _ready() -> void:
	_blocks = BlockRegistry.new()
	_generator = TerrainGenerator.new()
	_mesher = ChunkMesher.new(_blocks)
	_max_active_jobs = clampi(OS.get_processor_count() / 2, MIN_ACTIVE_JOBS, MAX_ACTIVE_JOBS)
	_fire_overlay = FireOverlay.new()
	_fire_overlay.name = "FireOverlay"
	add_child(_fire_overlay)


func _process(delta: float) -> void:
	_collect_debug_map()
	if _player == null:
		return
	_stream_tick()
	_water_accum += delta
	if _water_accum >= WATER_TICK_INTERVAL:
		_water_accum = 0.0
		_water_tick()
	_fire_accum += delta
	if _fire_accum >= FIRE_TICK_INTERVAL:
		_fire_accum = 0.0
		_fire_tick()


func _exit_tree() -> void:
	for pos in _pending.keys():
		WorkerThreadPool.wait_for_task_completion((_pending[pos] as PendingJob).task)
	_pending.clear()
	if _debug_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_debug_task)
		_debug_task = -1
	flush_edit_store()


## Must run before setup_player() and must not be called while chunk jobs are
## in flight: recreating the noise set invalidates running workers.
func configure(world_config: Dictionary, render_distance_chunks: int,
		stream_lod_mode: int = LOD_MODE_FULL) -> void:
	render_distance = maxi(render_distance_chunks, 1)
	lod_mode = clampi(stream_lod_mode, LOD_MODE_FULL, LOD_MODE_BALANCED)
	_update_lod_distance()
	unload_radius = render_distance + 2
	_generator.configure(world_config)
	_worldgen_revision += 1


## Attaches the main-thread persistence boundary. Region files are hydrated
## before immutable edit snapshots enter worker jobs; workers never perform I/O.
func set_edit_store(store: WorldStorage) -> void:
	_edit_store = store
	_hydrated_edit_chunks.clear()
	_edited_blocks.clear()
	_edits_by_chunk.clear()


func flush_edit_store() -> Error:
	if _edit_store == null:
		return OK
	return _edit_store.flush_dirty_regions()


func set_render_distance(value: int) -> void:
	render_distance = maxi(value, 1)
	_update_lod_distance()
	unload_radius = render_distance + 2
	_rebuild_desired()
	_unload_far()


func set_lod_mode(value: int) -> void:
	var normalized := clampi(value, LOD_MODE_FULL, LOD_MODE_BALANCED)
	if lod_mode == normalized:
		return
	lod_mode = normalized
	_update_lod_distance()
	_rebuild_desired()


func _update_lod_distance() -> void:
	# Full Detail always means authoritative full chunks through the selected
	# render distance, including Extreme values. Balanced is the explicit opt-in
	# memory/performance mode and alone enables compact distance terrain.
	lod_distance = mini(render_distance, BALANCED_FULL_DETAIL_DISTANCE) \
		if lod_mode == LOD_MODE_BALANCED else render_distance


## Physics uses this readiness boundary to suspend gravity while a teleported
## or fast-flying player waits for the authoritative collision mesh beneath the
## current horizontal position.
func is_collision_ready_at(world_position: Vector3) -> bool:
	return _is_chunk_collision_ready(_chunk_for_position(world_position))


func _is_chunk_collision_ready(chunk_position: Vector2i) -> bool:
	var chunk: Chunk = _chunks.get(chunk_position)
	return chunk != null and not chunk.lod and chunk.shape != null and chunk.shape.shape != null


## Sweeps horizontal movement through the chunk grid and returns the fraction
## that remains inside resident, rendered chunks. Collision readiness is a
## separate gravity guard: a visible LOD/full chunk must not behave like an
## invisible wall while its nearby collision rebuild catches up.
func loaded_motion_fraction(from: Vector3, to: Vector3) -> float:
	var delta := Vector2(to.x - from.x, to.z - from.z)
	var distance := delta.length()
	if distance <= 0.000001:
		return 1.0
	var chunk := _chunk_for_position(from)
	if not _chunks.has(chunk):
		return 0.0
	var target := _chunk_for_position(to)
	if target == chunk:
		return 1.0
	var step_x := 1 if delta.x > 0.0 else (-1 if delta.x < 0.0 else 0)
	var step_z := 1 if delta.y > 0.0 else (-1 if delta.y < 0.0 else 0)
	var next_x := float((chunk.x + 1) * VoxelDefs.CHUNK_SIZE) if step_x > 0 \
		else float(chunk.x * VoxelDefs.CHUNK_SIZE)
	var next_z := float((chunk.y + 1) * VoxelDefs.CHUNK_SIZE) if step_z > 0 \
		else float(chunk.y * VoxelDefs.CHUNK_SIZE)
	var t_max_x := (next_x - from.x) / delta.x if step_x != 0 else INF
	var t_max_z := (next_z - from.z) / delta.y if step_z != 0 else INF
	var t_delta_x := float(VoxelDefs.CHUNK_SIZE) / absf(delta.x) if step_x != 0 else INF
	var t_delta_z := float(VoxelDefs.CHUNK_SIZE) / absf(delta.y) if step_z != 0 else INF
	while chunk != target:
		var entry_t: float
		if is_equal_approx(t_max_x, t_max_z):
			entry_t = t_max_x
			chunk += Vector2i(step_x, step_z)
			t_max_x += t_delta_x
			t_max_z += t_delta_z
		elif t_max_x < t_max_z:
			entry_t = t_max_x
			chunk.x += step_x
			t_max_x += t_delta_x
		else:
			entry_t = t_max_z
			chunk.y += step_z
			t_max_z += t_delta_z
		if not _chunks.has(chunk):
			return clampf(entry_t - STREAM_BOUNDARY_MARGIN / distance, 0.0, 1.0)
	return 1.0


## Saved positions can come from an interrupted run that previously fell into
## unloaded terrain. Validate the two blocks occupied by the standing capsule
## after the local spawn ring is available before accepting that position.
func is_player_volume_clear(world_position: Vector3) -> bool:
	var block_x := floori(world_position.x)
	var block_z := floori(world_position.z)
	for block_y in [floori(world_position.y + 0.05), floori(world_position.y + 1.7)]:
		var block_id := get_block_world(Vector3i(block_x, block_y, block_z))
		if block_id == BlockRegistry.BLOCK_AIR or _blocks.is_water_id(block_id) \
				or _blocks.has_flag(block_id, BlockRegistry.FLAG_CROSS):
			continue
		return false
	return true


## Points streaming at a new node. The initial setup and any caller that is
## about to place physics on the target (photo mode returning to the player)
## ask for sync_spawn_area: it commits the 3x3 ring on the main thread so the
## target is not left standing in unloaded space. Mid-flight re-targets leave
## the ring to the async nearest-first stream instead of stalling the frame.
func setup_player(player_node: Node3D, sync_spawn_area := false) -> void:
	var first_setup := _player == null
	_player = player_node
	_stream_center = _chunk_for_position(player_node.global_position)
	if first_setup or sync_spawn_area:
		_generate_spawn_area()
	_rebuild_desired()
	_schedule_jobs()


func _stream_tick() -> void:
	var center := _chunk_for_position(_player.global_position)
	if center != _stream_center:
		_stream_center = center
		_rebuild_desired()
		_unload_far()
		_drop_far_collision()
	_collect_jobs()
	_process_commit_queue()
	# Discover missing nearby collision before assigning newly-opened worker
	# slots. Otherwise generation can refill every slot first while boosted
	# flight waits on a floor remesh that was only queued afterward.
	_ensure_near_collision()
	_schedule_jobs()


## Distant full chunks are committed without a collision shape. Rebuilds are
## only requested as the player gets close, which keeps shape memory bounded to
## the local area while the world stays full-detail everywhere in range.
func _ensure_near_collision() -> void:
	var candidates: Array[Vector2i] = []
	for dz in range(-COLLISION_DISTANCE, COLLISION_DISTANCE + 1):
		for dx in range(-COLLISION_DISTANCE, COLLISION_DISTANCE + 1):
			var pos := _stream_center + Vector2i(dx, dz)
			var chunk: Chunk = _chunks.get(pos)
			if chunk == null or chunk.lod:
				continue
			_restore_chunk_data(chunk)
			if chunk.shape != null and chunk.shape.shape != null:
				continue
			var pending: PendingJob = _pending.get(pos)
			if pending != null:
				# A mesh submitted while this chunk was distant contains no collision.
				# Mark it stale now so completion immediately requeues a collision build.
				if pending.kind == "mesh" and not pending.lod and not pending.want_collision:
					_dirty[pos] = true
				continue
			candidates.append(pos)
	# `_queue_rebuild()` pushes normal work to the front. Queue far-to-near so
	# the current chunk and its closest floor ring finish first, regardless of
	# dictionary/scan order or older dirty work already in the mesh queue.
	candidates.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return (a - _stream_center).length_squared() > (b - _stream_center).length_squared()
	)
	for pos in candidates:
		_queue_rebuild(pos)
		if _mesh_queued.has(pos):
			_mesh_queue.erase(pos)
			_mesh_queue.push_front(pos)


func _drop_far_collision() -> void:
	for pos in _chunks.keys():
		var chunk: Chunk = _chunks[pos]
		if chunk.shape != null and not _within_collision_range(pos):
			_remove_chunk_collision_nodes(chunk)
	if ENABLE_COLD_CHUNK_COMPRESSION:
		_compress_distant_chunks()


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
				_run_chunk_job(pos, _chunk_edits_for(pos), _gather_neighbors(pos), slot, false, true)
				if slot.has("result"):
					_record_job_metrics(slot, false)
					_commit_chunk(pos, slot["result"], false)


func _rebuild_desired() -> void:
	_desired.clear()
	_mesh_queue.clear()
	_mesh_queued.clear()
	var wanted: Array[Vector2i] = []
	# Build in nearest-first Chebyshev rings instead of filling a square and
	# sorting thousands of entries every time the player crosses a chunk edge.
	# At extreme distances this removes a large main-thread O(n log n) hitch.
	for ring in range(render_distance + 1):
		for dx in range(-ring, ring + 1):
			for dz in range(-ring, ring + 1):
				if maxi(absi(dx), absi(dz)) != ring:
					continue
				var pos := _stream_center + Vector2i(dx, dz)
				_desired[pos] = true
				var want_lod := _chunk_uses_lod(pos)
				if _chunks.has(pos) and (_chunks[pos] as Chunk).lod != want_lod:
					_dirty[pos] = true
				var staged: TerrainGenerator.GenResult = _generated.get(pos)
				if staged != null and (staged.lod != want_lod \
						or staged.config_revision != _worldgen_revision):
					_generated.erase(pos)
				if not _chunks.has(pos) and not _generated.has(pos) and not _pending.has(pos):
					wanted.append(pos)
	_gen_queue = wanted
	_gen_queued.clear()
	for pos in _gen_queue:
		_gen_queued[pos] = true
	for pos in _dirty.keys():
		if _desired.has(pos) and not _pending.has(pos) and not _gen_queued.has(pos):
			_queue_rebuild(pos)
	for pos in _generated.keys():
		if not _desired.has(pos):
			_generated.erase(pos)
		else:
			_queue_generated_mesh_if_ready(pos)


func _schedule_jobs() -> void:
	if _gen_queue.is_empty() and _mesh_queue.is_empty():
		return
	while not _mesh_queue.is_empty() or not _gen_queue.is_empty():
		var mesh_job := false
		var queue_index := 0
		if _pending.size() > _max_active_jobs:
			break
		var urgent_mesh_index := _urgent_queue_index(_mesh_queue)
		var urgent_generation_index := _urgent_queue_index(_gen_queue)
		if urgent_mesh_index >= 0:
			mesh_job = true
			queue_index = urgent_mesh_index
		elif urgent_generation_index >= 0:
			queue_index = urgent_generation_index
		elif _pending.size() < _max_active_jobs:
			# Away from the player, finish already-generated meshes before doing
			# more terrain work. Near the player, the urgent branches above always
			# fill real chunk holes before unrelated distance remeshes.
			mesh_job = not _mesh_queue.is_empty()
		else:
			break
		# At the normal cap, only the urgent branches can reach this point. This
		# is the single bounded overflow slot; WorkerThreadPool high priority runs
		# it as soon as stale distance work releases a worker.
		var pos: Vector2i
		if mesh_job:
			pos = _mesh_queue[queue_index]
			_mesh_queue.remove_at(queue_index)
			_mesh_queued.erase(pos)
		else:
			pos = _gen_queue[queue_index]
			_gen_queue.remove_at(queue_index)
			_gen_queued.erase(pos)
		if _pending.has(pos):
			continue
		if mesh_job and not _chunks.has(pos) and not _generated.has(pos):
			continue
		if not mesh_job and (_chunks.has(pos) or _generated.has(pos)) and not _dirty.has(pos):
			continue
		_dirty.erase(pos)
		var lod := _chunk_uses_lod(pos)
		var job := PendingJob.new()
		job.version = _chunk_edit_version.get(pos, 0)
		job.config_revision = _worldgen_revision
		job.lod = lod
		job.slot = {}
		var high_priority := not lod and _within_collision_range(pos)
		job.want_collision = high_priority
		var chunk: Chunk = _chunks.get(pos)
		if mesh_job and chunk != null and chunk.lod == lod:
			job.kind = "mesh"
			if lod:
				job.task = WorkerThreadPool.add_task(
					_run_lod_remesh_job.bind(chunk.lod_solid_y.duplicate(), chunk.lod_solid_id.duplicate(),
						chunk.lod_sub_id.duplicate(), chunk.lod_water_y.duplicate(),
						chunk.lod_water_level.duplicate(), chunk.max_y,
						chunk.foliage_tints.duplicate(), chunk.water_tints.duplicate(),
						_gather_lod_neighbors(pos), job.slot),
					false, "voxel_lod_remesh")
			else:
				job.task = WorkerThreadPool.add_task(
					_run_full_remesh_job.bind(_chunk_data_snapshot(chunk), chunk.foliage_tints.duplicate(),
						chunk.water_tints.duplicate(), _gather_neighbors(pos), job.slot, high_priority),
					high_priority, "voxel_full_remesh")
		elif mesh_job:
			job.kind = "mesh"
			var generated: TerrainGenerator.GenResult = _generated.get(pos)
			if generated == null:
				continue
			job.task = WorkerThreadPool.add_task(
				_run_generated_mesh_job.bind(generated, _gather_generated_neighbors(pos, lod),
					job.slot, lod, high_priority),
				high_priority, "voxel_generated_mesh")
		else:
			job.kind = "generate"
			job.task = WorkerThreadPool.add_task(
				_run_generation_job.bind(pos, _chunk_edits_for(pos), job.slot, lod),
				high_priority,
				"voxel_generate")
		_pending[pos] = job


func _urgent_queue_index(queue: Array[Vector2i]) -> int:
	for index in queue.size():
		var pos := queue[index]
		if not _chunk_uses_lod(pos) and _within_collision_range(pos):
			return index
	return -1


func _process_commit_queue() -> void:
	var start := Time.get_ticks_msec()
	while not _commit_queue.is_empty():
		var commit_index := _next_commit_index()
		var item: CommitItem = _commit_queue[commit_index]
		_commit_queue.remove_at(commit_index)
		if not _desired.has(item.pos):
			_discard_unloaded_chunk_state(item.pos)
			continue
		var mode_stale := item.lod != _chunk_uses_lod(item.pos)
		if item.version != _chunk_edit_version.get(item.pos, 0) or item.config_revision != _worldgen_revision or mode_stale:
			_queue_rebuild(item.pos)
			continue
		_commit_chunk(item.pos, item.result, item.lod)
		if Time.get_ticks_msec() - start > COMMIT_BUDGET_MS:
			break


func _next_commit_index() -> int:
	var best_index := 0
	var best_priority := 3
	var best_distance := 1 << 30
	for index in _commit_queue.size():
		var item: CommitItem = _commit_queue[index]
		var distance := (item.pos - _stream_center).length_squared()
		var priority := 2
		if not item.lod and _within_collision_range(item.pos):
			priority = 0 if item.result.build_collision else 1
		if priority < best_priority or (priority == best_priority and distance < best_distance):
			best_index = index
			best_priority = priority
			best_distance = distance
	return best_index


func _collect_jobs() -> void:
	for pos in _pending.keys():
		var job: PendingJob = _pending[pos]
		if not WorkerThreadPool.is_task_completed(job.task):
			continue
		WorkerThreadPool.wait_for_task_completion(job.task)
		_pending.erase(pos)
		if not _desired.has(pos):
			# No off-screen result is useful. Purging only after the worker has
			# completed preserves its edit-version stale check until this point.
			_discard_unloaded_chunk_state(pos)
			continue
		if _dirty.has(pos):
			# An edit invalidated this job's neighbor snapshot while it was running.
			# Discard the stale result and immediately schedule a fresh build.
			if _desired.has(pos):
				_queue_rebuild(pos)
			continue
		if job.kind == "generate":
			if job.slot.has("generated") and job.slot["generated"] != null \
					and _desired.has(pos) and job.version == _chunk_edit_version.get(pos, 0) \
					and job.config_revision == _worldgen_revision and job.lod == _chunk_uses_lod(pos):
				var generated: TerrainGenerator.GenResult = job.slot["generated"]
				generated.config_revision = job.config_revision
				_generated[pos] = generated
				_queue_generated_meshes_around(pos)
			elif _desired.has(pos):
				_queue_rebuild(pos)
			continue
		if job.slot.has("result") and job.slot["result"] != null:
			_record_job_metrics(job.slot, job.lod)
			_commit_queue.append(CommitItem.new(pos, job.slot["result"], job.version,
				job.config_revision, job.lod))


## Worker-thread entry point. Only reads state that is immutable while jobs
## are in flight (generator noise set, mesher tables, block registry).
func _run_chunk_job(chunk_pos: Vector2i, edits: Dictionary, neighbors, slot: Dictionary,
		lod: bool, want_collision: bool = true) -> void:
	var generated := _generator.generate_data(chunk_pos, edits, lod)
	var mesh_start := Time.get_ticks_usec()
	if lod:
		slot["result"] = _mesher.build_lod(generated.lod_solid_y, generated.lod_solid_id, generated.lod_sub_id, generated.lod_water_y, generated.lod_water_level, generated.max_y, generated.foliage_tints, generated.water_tints, neighbors)
	else:
		slot["result"] = _mesher.build(generated.data, generated.max_y, generated.heights, generated.foliage_tints, generated.water_tints, neighbors, want_collision)
	slot["timings"] = generated.timings
	slot["mesh_us"] = Time.get_ticks_usec() - mesh_start


func _run_generation_job(chunk_pos: Vector2i, edits: Dictionary, slot: Dictionary,
		lod: bool) -> void:
	slot["generated"] = _generator.generate_data(chunk_pos, edits, lod)


func _run_generated_mesh_job(generated: TerrainGenerator.GenResult, neighbors,
		slot: Dictionary, lod: bool, want_collision: bool) -> void:
	var mesh_start := Time.get_ticks_usec()
	if lod:
		slot["result"] = _mesher.build_lod(generated.lod_solid_y, generated.lod_solid_id,
			generated.lod_sub_id, generated.lod_water_y, generated.lod_water_level,
			generated.max_y, generated.foliage_tints, generated.water_tints, neighbors)
	else:
		slot["result"] = _mesher.build(generated.data, generated.max_y, generated.heights,
			generated.foliage_tints, generated.water_tints, neighbors, want_collision)
	slot["timings"] = generated.timings
	slot["mesh_us"] = Time.get_ticks_usec() - mesh_start


## Rebuilds an authoritative loaded chunk from a thread-safe voxel snapshot.
## Edits already mutate Chunk.data, so rerunning terrain, caves, ores, and
## population here was redundant and dominated seam/collision rebuild cost.
func _run_full_remesh_job(data: PackedByteArray, foliage_tints: PackedColorArray,
		water_tints: PackedColorArray, neighbors: ChunkMesher.NeighborSet,
		slot: Dictionary, want_collision: bool) -> void:
	var scan_start := Time.get_ticks_usec()
	var heights := PackedInt32Array()
	heights.resize(VoxelDefs.CHUNK_AREA)
	var max_y := 0
	for z in VoxelDefs.CHUNK_SIZE:
		for x in VoxelDefs.CHUNK_SIZE:
			var column := x + z * VoxelDefs.DATA_STRIDE_Z
			var top := -1
			for y in range(VoxelDefs.WORLD_HEIGHT - 1, -1, -1):
				if data[column + y * VoxelDefs.DATA_STRIDE_Y] != BlockRegistry.BLOCK_AIR:
					top = y
					break
			heights[column] = top
			max_y = maxi(max_y, top)
	var scan_us := Time.get_ticks_usec() - scan_start
	var mesh_start := Time.get_ticks_usec()
	slot["result"] = _mesher.build(data, max_y, heights, foliage_tints, water_tints,
		neighbors, want_collision)
	slot["timings"] = {
		"terrain_us": 0,
		"populate_us": 0,
		"heightmap_us": scan_us,
		"generation_us": 0,
	}
	slot["mesh_us"] = Time.get_ticks_usec() - mesh_start


func _run_lod_remesh_job(solid_y: PackedInt32Array, solid_id: PackedByteArray,
		sub_id: PackedByteArray, water_y: PackedInt32Array, water_level: PackedByteArray,
		max_y: int, foliage_tints: PackedColorArray, water_tints: PackedColorArray,
		neighbors: ChunkMesher.LodNeighbors, slot: Dictionary) -> void:
	var mesh_start := Time.get_ticks_usec()
	slot["result"] = _mesher.build_lod(solid_y, solid_id, sub_id, water_y, water_level,
		max_y, foliage_tints, water_tints, neighbors)
	slot["timings"] = {"terrain_us": 0, "populate_us": 0, "heightmap_us": 0, "generation_us": 0}
	slot["mesh_us"] = Time.get_ticks_usec() - mesh_start


func _record_job_metrics(slot: Dictionary, lod: bool) -> void:
	var timings: Dictionary = slot.get("timings", {})
	var alpha := 0.12
	var generation_ms := float(timings.get("generation_us", 0)) / 1000.0
	var mesh_ms := float(slot.get("mesh_us", 0)) / 1000.0
	var terrain_ms := float(timings.get("terrain_us", 0)) / 1000.0
	var populate_ms := float(timings.get("populate_us", 0)) / 1000.0
	if _full_jobs_measured + _lod_jobs_measured == 0:
		_generation_ema_ms = generation_ms
		_mesh_ema_ms = mesh_ms
		_terrain_ema_ms = terrain_ms
		_populate_ema_ms = populate_ms
	else:
		_generation_ema_ms = lerpf(_generation_ema_ms, generation_ms, alpha)
		_mesh_ema_ms = lerpf(_mesh_ema_ms, mesh_ms, alpha)
		_terrain_ema_ms = lerpf(_terrain_ema_ms, terrain_ms, alpha)
		_populate_ema_ms = lerpf(_populate_ema_ms, populate_ms, alpha)
	if lod:
		_lod_jobs_measured += 1
	else:
		_full_jobs_measured += 1


func _chunk_uses_lod(pos: Vector2i) -> bool:
	return maxi(absi(pos.x - _stream_center.x), absi(pos.y - _stream_center.y)) > lod_distance


func _queue_generated_meshes_around(pos: Vector2i) -> void:
	_queue_generated_mesh_if_ready(pos)
	for direction in VoxelDefs.DIRS_8:
		_queue_generated_mesh_if_ready(pos + direction)


func _queue_generated_mesh_if_ready(pos: Vector2i) -> void:
	if not _generated.has(pos) or not _desired.has(pos) or _pending.has(pos) \
			or _mesh_queued.has(pos) or not _generated_neighbors_ready(pos):
		return
	_mesh_queue.append(pos)
	_mesh_queued[pos] = true


func _generated_neighbors_ready(pos: Vector2i) -> bool:
	var lod := _chunk_uses_lod(pos)
	var directions := VoxelDefs.DIRS_4 if lod else VoxelDefs.DIRS_8
	for direction in directions:
		var neighbor_pos: Vector2i = pos + direction
		if not _desired.has(neighbor_pos):
			continue
		var chunk: Chunk = _chunks.get(neighbor_pos)
		if chunk != null and chunk.lod == _chunk_uses_lod(neighbor_pos):
			continue
		var generated: TerrainGenerator.GenResult = _generated.get(neighbor_pos)
		if generated == null or generated.lod != _chunk_uses_lod(neighbor_pos) \
				or generated.config_revision != _worldgen_revision:
			return false
	return true


func _gather_generated_neighbors(pos: Vector2i, lod: bool):
	if lod:
		var lod_out := ChunkMesher.LodNeighbors.new()
		for index in VoxelDefs.DIRS_4.size():
			var direction: Vector2i = VoxelDefs.DIRS_4[index]
			var neighbor_pos := pos + direction
			var chunk: Chunk = _chunks.get(neighbor_pos)
			if chunk != null and chunk.lod == _chunk_uses_lod(neighbor_pos):
				lod_out.edges[direction] = _build_lod_edge(chunk, direction)
			elif _generated.has(neighbor_pos):
				lod_out.edges[direction] = _build_generated_lod_edge(_generated[neighbor_pos], direction)
			else:
				continue
			lod_out.mask |= (1 << index)
		return lod_out
	var out := ChunkMesher.NeighborSet.new()
	for index in VoxelDefs.DIRS_8.size():
		var direction: Vector2i = VoxelDefs.DIRS_8[index]
		var neighbor_pos := pos + direction
		var chunk: Chunk = _chunks.get(neighbor_pos)
		if chunk != null and chunk.lod == _chunk_uses_lod(neighbor_pos):
			if chunk.lod:
				out.samples[direction] = ChunkMesher.NeighborSample.from_lod(
					chunk.lod_solid_y.duplicate(), chunk.lod_solid_id.duplicate(),
					chunk.lod_sub_id.duplicate(), chunk.lod_water_y.duplicate())
			else:
				out.samples[direction] = ChunkMesher.NeighborSample.new(
					_chunk_data_snapshot(chunk), chunk.max_y, chunk.heights.duplicate())
		elif _generated.has(neighbor_pos):
			var generated: TerrainGenerator.GenResult = _generated[neighbor_pos]
			if generated.lod:
				out.samples[direction] = ChunkMesher.NeighborSample.from_lod(
					generated.lod_solid_y, generated.lod_solid_id,
					generated.lod_sub_id, generated.lod_water_y)
			else:
				out.samples[direction] = ChunkMesher.NeighborSample.new(
					generated.data.duplicate(), generated.max_y, generated.heights.duplicate())
		else:
			continue
		out.mask |= (1 << index)
	return out


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
	var data := _chunk_data_snapshot(chunk) if not chunk.lod else PackedByteArray()
	for index in VoxelDefs.CHUNK_SIZE:
		var local_x := index if direction.y != 0 else (0 if direction.x > 0 else VoxelDefs.CHUNK_SIZE - 1)
		var local_z := index if direction.x != 0 else (0 if direction.y > 0 else VoxelDefs.CHUNK_SIZE - 1)
		var column := local_x + local_z * VoxelDefs.DATA_STRIDE_Z
		if chunk.lod:
			edge.solid[index] = chunk.lod_solid_y[column]
			edge.water[index] = chunk.lod_water_y[column]
			continue
		var solid := ChunkMesher.LOD_NONE
		var water := ChunkMesher.LOD_NONE
		for y in range(chunk.max_y, -1, -1):
			var id: int = data[column + y * VoxelDefs.DATA_STRIDE_Y]
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


func _build_generated_lod_edge(generated: TerrainGenerator.GenResult,
		direction: Vector2i) -> ChunkMesher.LodEdge:
	var edge := ChunkMesher.LodEdge.new()
	edge.solid.resize(VoxelDefs.CHUNK_SIZE)
	edge.water.resize(VoxelDefs.CHUNK_SIZE)
	for index in VoxelDefs.CHUNK_SIZE:
		var local_x := index if direction.y != 0 else (0 if direction.x > 0 else VoxelDefs.CHUNK_SIZE - 1)
		var local_z := index if direction.x != 0 else (0 if direction.y > 0 else VoxelDefs.CHUNK_SIZE - 1)
		var column := local_x + local_z * VoxelDefs.DATA_STRIDE_Z
		if generated.lod:
			edge.solid[index] = generated.lod_solid_y[column]
			edge.water[index] = generated.lod_water_y[column]
			continue
		var solid := ChunkMesher.LOD_NONE
		var water := ChunkMesher.LOD_NONE
		for y in range(generated.max_y, -1, -1):
			var id: int = generated.data[column + y * VoxelDefs.DATA_STRIDE_Y]
			if water == ChunkMesher.LOD_NONE and _blocks.is_water_id(id):
				water = y
			if solid == ChunkMesher.LOD_NONE and id != BlockRegistry.BLOCK_AIR \
					and not _blocks.is_water_id(id) and not _blocks.has_flag(id, BlockRegistry.FLAG_CROSS):
				solid = y
			if solid != ChunkMesher.LOD_NONE and water != ChunkMesher.LOD_NONE:
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
		if chunk.lod:
			out.samples[direction] = ChunkMesher.NeighborSample.from_lod(
				chunk.lod_solid_y.duplicate(), chunk.lod_solid_id.duplicate(),
				chunk.lod_sub_id.duplicate(), chunk.lod_water_y.duplicate())
		else:
			out.samples[direction] = ChunkMesher.NeighborSample.new(
				_chunk_data_snapshot(chunk), chunk.max_y, chunk.heights.duplicate())
		out.mask |= (1 << index)
	return out


## Worker jobs own their snapshots. Decoding here never exposes the compressed
## backing array to a worker and does not make a distant chunk mutable.
func _chunk_data_snapshot(chunk: Chunk) -> PackedByteArray:
	if not chunk.data.is_empty():
		return chunk.data.duplicate()
	return decompress_chunk_data(chunk.compressed_data)


func _restore_chunk_data(chunk: Chunk) -> void:
	if chunk.lod or not chunk.data.is_empty() or chunk.compressed_data.is_empty():
		return
	var restored := decompress_chunk_data(chunk.compressed_data)
	if restored.size() != VoxelDefs.CHUNK_AREA * VoxelDefs.WORLD_HEIGHT:
		push_error("voxel_world: invalid compressed full-detail chunk data")
		return
	chunk.data = restored
	chunk.compressed_data.clear()


func _compress_distant_chunks() -> void:
	for pos in _chunks:
		var chunk: Chunk = _chunks[pos]
		if chunk.lod or _within_collision_range(pos) or chunk.data.is_empty():
			continue
		var compressed := compress_chunk_data(chunk.data)
		if compressed.size() < chunk.data.size():
			chunk.compressed_data = compressed
			chunk.data.clear()


func _commit_chunk(pos: Vector2i, res: ChunkMesher.MeshResult, lod: bool) -> void:
	_generated.erase(pos)
	var chunk: Chunk = _chunks.get(pos)
	var mode_changed := chunk != null and chunk.lod != lod
	if chunk == null:
		chunk = _create_chunk_nodes(pos)
		_chunks[pos] = chunk
	chunk.lod = lod
	chunk.data = res.data
	chunk.compressed_data.clear()
	chunk.heights = res.heights
	chunk.foliage_tints = res.foliage_tints
	chunk.water_tints = res.water_tints
	chunk.lod_solid_y = res.lod_solid_y
	chunk.lod_solid_id = res.lod_solid_id
	chunk.lod_sub_id = res.lod_sub_id
	chunk.lod_water_y = res.lod_water_y
	chunk.lod_water_level = res.lod_water_level
	chunk.max_y = res.max_y
	chunk.mask = res.mask
	if not lod:
		_seed_fire_edits(pos)
	chunk.mesh.mesh = ChunkMesher.arrays_to_mesh(res.verts, res.normals, res.uvs, res.colors, res.indices, _blocks.material, res.light, res.layers)
	chunk.water.mesh = ChunkMesher.arrays_to_mesh(res.water_verts, res.water_normals, res.water_uvs, res.water_colors, res.water_indices, _blocks.water_material, res.water_light)
	if not lod and _within_collision_range(pos) and not res.collision.is_empty():
		_ensure_chunk_collision_nodes(chunk, pos)
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(res.collision)
		shape.backface_collision = true
		chunk.shape.shape = shape
	else:
		_remove_chunk_collision_nodes(chunk)
	_remesh_on_commit_neighbors(pos)
	if mode_changed:
		_invalidate_mode_change_neighbors(pos)
	if ENABLE_COLD_CHUNK_COMPRESSION:
		_compress_distant_chunks()


func _invalidate_mode_change_neighbors(pos: Vector2i) -> void:
	for direction in VoxelDefs.DIRS_8:
		var neighbor_pos: Vector2i = pos + direction
		var neighbor: Chunk = _chunks.get(neighbor_pos)
		if neighbor != null and _desired_neighbors_ready(neighbor_pos, neighbor.lod):
			_queue_rebuild(neighbor_pos, true, true)


func _within_collision_range(pos: Vector2i) -> bool:
	return maxi(absi(pos.x - _stream_center.x), absi(pos.y - _stream_center.y)) <= COLLISION_DISTANCE


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
	return chunk


func _ensure_chunk_collision_nodes(chunk: Chunk, pos: Vector2i) -> void:
	if chunk.body != null and is_instance_valid(chunk.body) and chunk.shape != null \
			and is_instance_valid(chunk.shape):
		return
	chunk.body = StaticBody3D.new()
	chunk.body.name = "Body_%d_%d" % [pos.x, pos.y]
	chunk.body.position = Vector3(pos.x * VoxelDefs.CHUNK_SIZE, 0.0,
		pos.y * VoxelDefs.CHUNK_SIZE)
	chunk.body.collision_layer = VoxelDefs.COLLISION_LAYER_WORLD
	chunk.body.collision_mask = 0
	add_child(chunk.body)
	chunk.shape = CollisionShape3D.new()
	chunk.body.add_child(chunk.shape)


func _remove_chunk_collision_nodes(chunk: Chunk) -> void:
	if chunk.shape != null and is_instance_valid(chunk.shape):
		chunk.shape.shape = null
	if chunk.body != null and is_instance_valid(chunk.body):
		chunk.body.queue_free()
	chunk.shape = null
	chunk.body = null


func _remesh_on_commit_neighbors(pos: Vector2i) -> void:
	for index in VoxelDefs.DIRS_8.size():
		var direction: Vector2i = VoxelDefs.DIRS_8[index]
		var neighbor: Chunk = _chunks.get(pos + direction)
		if neighbor == null or (neighbor.lod and index >= VoxelDefs.DIRS_4.size()):
			continue
		if (neighbor.mask & REBUILD_OPPOSITE_BITS[index]) == 0 \
				and _desired_neighbors_ready(pos + direction, neighbor.lod):
			_queue_rebuild(pos + direction, true, true)


## Wait until the complete desired neighbor ring exists before doing one seam
## rebuild. Rebuilding after every individual commit caused a burst of up to
## eight redundant terrain+mesh jobs per chunk and noticeable stream stutter.
func _desired_neighbors_ready(pos: Vector2i, lod: bool) -> bool:
	var directions := VoxelDefs.DIRS_4 if lod else VoxelDefs.DIRS_8
	for direction in directions:
		var neighbor_pos: Vector2i = pos + direction
		if not _desired.has(neighbor_pos):
			continue
		var neighbor: Chunk = _chunks.get(neighbor_pos)
		if neighbor == null or neighbor.lod != _chunk_uses_lod(neighbor_pos):
			return false
	return true


func _queue_rebuild(pos: Vector2i, preserve_if_pending := false,
		low_priority := false) -> void:
	if _pending.has(pos):
		if preserve_if_pending:
			_dirty[pos] = true
		return
	if _gen_queued.has(pos) or _mesh_queued.has(pos):
		return
	_dirty[pos] = true
	var chunk: Chunk = _chunks.get(pos)
	var can_remesh := chunk != null and chunk.lod == _chunk_uses_lod(pos)
	if can_remesh:
		if low_priority:
			_mesh_queue.append(pos)
		else:
			_mesh_queue.push_front(pos)
		_mesh_queued[pos] = true
	else:
		_generated.erase(pos)
		if low_priority:
			_gen_queue.append(pos)
		else:
			_gen_queue.push_front(pos)
		_gen_queued[pos] = true


func _unload_far() -> void:
	for pos in _chunks.keys():
		if maxi(absi(pos.x - _stream_center.x), absi(pos.y - _stream_center.y)) > unload_radius:
			_free_chunk(pos)
	_discard_unloaded_stream_state()


func _free_chunk(pos: Vector2i) -> void:
	var chunk: Chunk = _chunks.get(pos)
	if chunk == null:
		return
	# queue_free() is deferred. Remove physics immediately so a large render-
	# distance contraction cannot leave one-frame ghost walls from old bodies.
	_remove_chunk_collision_nodes(chunk)
	chunk.mesh.queue_free()
	chunk.water.queue_free()
	_chunks.erase(pos)
	_discard_unloaded_chunk_state(pos)


## A disk-backed chunk can drop its hydrated edit snapshot once its scene nodes
## are gone: WorldStorage remains the authoritative copy. Keep versions while a
## worker or commit item still refers to them, otherwise a late stale result
## could look current after a fast return to the same stream center. In-memory
## worlds intentionally retain their edit buckets so procedural reloads still
## replay unsaved edits.
func _discard_unloaded_stream_state() -> void:
	var candidates: Dictionary = {}
	for pos in _dirty:
		candidates[pos] = true
	for pos in _generated:
		candidates[pos] = true
	for pos in _chunk_edit_version:
		candidates[pos] = true
	if _edit_store != null:
		for pos in _hydrated_edit_chunks:
			candidates[pos] = true
		for pos in _edits_by_chunk:
			candidates[pos] = true
	for pos in candidates:
		_discard_unloaded_chunk_state(pos)


func _discard_unloaded_chunk_state(pos: Vector2i) -> void:
	if _chunks.has(pos) or _desired.has(pos) or _pending.has(pos):
		return
	for queued_item in _commit_queue:
		var item: CommitItem = queued_item
		if item.pos == pos:
			return
	_generated.erase(pos)
	_dirty.erase(pos)
	_chunk_edit_version.erase(pos)
	if _edit_store == null:
		return
	var edits: Dictionary = _edits_by_chunk.get(pos, {})
	for position in edits:
		_edited_blocks.erase(position)
	_edits_by_chunk.erase(pos)
	_hydrated_edit_chunks.erase(pos)


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


func is_full_chunk_resident_at(cell: Vector3i) -> bool:
	var chunk := _loaded_chunk_for(cell)
	return chunk != null and not chunk.lod


func is_burning_at(cell: Vector3i) -> bool:
	return _burning.has(cell)


func get_block_world(block_position: Vector3i) -> int:
	var chunk := _loaded_chunk_for(block_position)
	if chunk == null or chunk.lod:
		return BlockRegistry.BLOCK_AIR
	_restore_chunk_data(chunk)
	return chunk.data[_data_index(block_position)]


func is_water_at(world_position: Vector3) -> bool:
	return _blocks.is_water_id(get_block_world(Vector3i(floori(world_position.x), floori(world_position.y), floori(world_position.z))))


## Ambient snapshot for the underwater pass: whether the camera is submerged,
## its depth below the local water surface, and the biome's water grading tint.
## The upward water scan is bounded and only runs on the throttled ambience
## update, so it never sits in a per-frame path.
func get_water_ambience(world_position: Vector3) -> Dictionary:
	var block_x := floori(world_position.x)
	var block_z := floori(world_position.z)
	var block_y := floori(world_position.y)
	var block_id := get_block_world(Vector3i(block_x, block_y, block_z))
	if not _blocks.is_water_id(block_id):
		# A camera inside a cross plant is still inside the water column; treat
		# it as submerged whenever water sits directly above so the overlay and
		# fog do not pop while swimming through vegetation.
		if not _blocks.has_flag(block_id, BlockRegistry.FLAG_CROSS) \
				or not _blocks.is_water_id(get_block_world(Vector3i(block_x, block_y + 1, block_z))):
			return {"submerged": false, "depth": 0.0, "tint": Color.WHITE, "biome": -1}
	var surface_y := block_y
	while surface_y - block_y < 48 and surface_y + 1 < VoxelDefs.WORLD_HEIGHT \
			and _blocks.is_water_id(get_block_world(Vector3i(block_x, surface_y + 1, block_z))):
		surface_y += 1
	var depth := float(surface_y - block_y) + (1.0 - (world_position.y - floorf(world_position.y)))
	var biome := _generator.biome_id_at(block_x, block_z)
	return {
		"submerged": true,
		"depth": maxf(depth, 0.0),
		"tint": _generator.water_tint_for(biome),
		"biome": biome,
	}


## Cave-biome ambience is only active in loaded full-detail underground air.
## A bounded ceiling probe prevents a region label from grading the surface or
## a broad entrance; it runs beside the already-throttled underwater query.
func get_cave_ambience(world_position: Vector3) -> Dictionary:
	var position := Vector3i(floori(world_position.x), floori(world_position.y), floori(world_position.z))
	var chunk := _loaded_chunk_for(position)
	if chunk == null or chunk.lod or position.y < 4:
		return {"active": false, "biome": BiomeCatalog.CAVE_BIOME_NONE, "tint": Color.WHITE, "depth": 0.0}
	var block_id := get_block_world(position)
	if block_id != BlockRegistry.BLOCK_AIR and not _blocks.has_flag(block_id, BlockRegistry.FLAG_CROSS):
		return {"active": false, "biome": BiomeCatalog.CAVE_BIOME_NONE, "tint": Color.WHITE, "depth": 0.0}
	# Mega-caves can be more than 32 blocks tall. Probe to the loaded column's
	# actual top so their ambience does not disappear merely because the ceiling
	# is high above the camera. First require real terrain depth: a tree canopy
	# or player roof over a surface camera must never activate cave grading.
	var chunk_position := _chunk_for_block(position)
	var local_x := position.x - chunk_position.x * VoxelDefs.CHUNK_SIZE
	var local_z := position.z - chunk_position.y * VoxelDefs.CHUNK_SIZE
	var column := local_x + local_z * VoxelDefs.DATA_STRIDE_Z
	var column_top := mini(chunk.heights[column], VoxelDefs.WORLD_HEIGHT - 1)
	if float(column_top) - world_position.y < 4.0:
		return {"active": false, "biome": BiomeCatalog.CAVE_BIOME_NONE, "tint": Color.WHITE, "depth": 0.0}
	var ceiling_y := -1
	for y in range(position.y + 1, column_top + 1):
		var overhead := get_block_world(Vector3i(position.x, y, position.z))
		if overhead != BlockRegistry.BLOCK_AIR \
				and not _blocks.has_flag(overhead, BlockRegistry.FLAG_CROSS) \
				and not _blocks.has_flag(overhead, BlockRegistry.FLAG_LEAVES):
			ceiling_y = y
			break
	if ceiling_y < 0:
		return {"active": false, "biome": BiomeCatalog.CAVE_BIOME_NONE, "tint": Color.WHITE, "depth": 0.0}
	var biome := _generator.cave_biome_id_at(position.x, position.y, position.z)
	if not BiomeCatalog.is_cave_biome(biome):
		return {"active": false, "biome": biome, "tint": Color.WHITE, "depth": 0.0}
	var surface_y := float(chunk.heights[column])
	var depth := clampf((surface_y - world_position.y) / 48.0, 0.0, 1.0)
	return {"active": true, "biome": biome, "tint": BiomeCatalog.cave_ambience_color(biome), "depth": depth}


func break_block(block_position: Vector3i) -> int:
	if block_position.y <= 0:
		return BlockRegistry.BLOCK_AIR
	var chunk_position := _chunk_for_block(block_position)
	var chunk: Chunk = _chunks.get(chunk_position)
	if chunk == null or chunk.lod:
		return BlockRegistry.BLOCK_AIR
	_restore_chunk_data(chunk)
	var index := _data_index(block_position)
	var block_id: int = chunk.data[index]
	if not _blocks.is_breakable(block_id):
		return BlockRegistry.BLOCK_AIR
	chunk.data[index] = BlockRegistry.BLOCK_AIR
	_record_edit(block_position, BlockRegistry.BLOCK_AIR)
	_touch_chunk(chunk_position, block_position, block_id, BlockRegistry.BLOCK_AIR)
	_seed_water(block_position)
	return block_id


func place_block(block_position: Vector3i, block_id: int) -> bool:
	if not _blocks.is_valid_id(block_id):
		return false
	if block_position.y < 0 or block_position.y >= VoxelDefs.WORLD_HEIGHT:
		return false
	var chunk_position := _chunk_for_block(block_position)
	var chunk: Chunk = _chunks.get(chunk_position)
	if chunk == null or chunk.lod:
		return false
	_restore_chunk_data(chunk)
	var index := _data_index(block_position)
	var existing: int = chunk.data[index]
	if existing != BlockRegistry.BLOCK_AIR and not _blocks.is_water_id(existing):
		return false
	chunk.data[index] = block_id
	_record_edit(block_position, block_id)
	_touch_chunk(chunk_position, block_position, existing, block_id)
	_seed_water(block_position)
	return true


## Activates an explosive block and returns a small result payload for HUD
## feedback. There is deliberately no fuse or animation: these blocks are
## inspection tools for opening terrain and exposing the generation layers.
func trigger_explosive(block_position: Vector3i) -> Dictionary:
	var block_id := get_block_world(block_position)
	var radius := 0
	match block_id:
		BlockRegistry.BLOCK_TNT:
			radius = TNT_BLAST_RADIUS
		BlockRegistry.BLOCK_NUKE:
			radius = NUKE_BLAST_RADIUS
		_:
			return {}
	return {
		"name": _blocks.get_block_name(block_id),
		"radius": radius,
		"removed": carve_sphere(block_position, radius),
	}


## Removes breakable voxels in a sphere while batching chunk invalidation.
## Calling break_block() for every voxel would enqueue thousands of duplicate
## mesh jobs; this path records every persistent edit but rebuilds each affected
## chunk (and each touched edge neighbor) only once.
func carve_sphere(center: Vector3i, radius: int) -> int:
	var safe_radius := clampi(radius, 1, 32)
	var radius_squared := safe_radius * safe_radius
	var changed_chunks: Dictionary = {}
	var rebuild_chunks: Dictionary = {}
	var water_shell: Array[Vector3i] = []
	var interior_water: Dictionary = {}
	var removed := 0
	var shell_inner_squared := (safe_radius - 1) * (safe_radius - 1)
	# Walk vertical runs so the horizontal chunk lookup and local data offset are
	# computed once per column rather than once per removed voxel. This keeps the
	# large nuke carve responsive without complicating edits with a coroutine.
	for z in range(center.z - safe_radius, center.z + safe_radius + 1):
		var dz := z - center.z
		for x in range(center.x - safe_radius, center.x + safe_radius + 1):
			var dx := x - center.x
			var horizontal_squared := dx * dx + dz * dz
			if horizontal_squared > radius_squared:
				continue
			var chunk_position := _chunk_for_block(Vector3i(x, center.y, z))
			var chunk: Chunk = _chunks.get(chunk_position)
			if chunk == null or chunk.lod:
				continue
			_restore_chunk_data(chunk)
			var local_x := x - chunk_position.x * VoxelDefs.CHUNK_SIZE
			var local_z := z - chunk_position.y * VoxelDefs.CHUNK_SIZE
			var column_index := local_x + local_z * VoxelDefs.DATA_STRIDE_Z
			var vertical_radius := floori(sqrt(float(radius_squared - horizontal_squared)))
			var min_y := maxi(center.y - vertical_radius, 1)
			var max_y := mini(center.y + vertical_radius, VoxelDefs.WORLD_HEIGHT - 1)
			var column_changed := false
			for y in range(min_y, max_y + 1):
				var position := Vector3i(x, y, z)
				var index := column_index + y * VoxelDefs.DATA_STRIDE_Y
				var block_id: int = chunk.data[index]
				if _blocks.is_water_id(block_id):
					interior_water[position] = true
					continue
				if not _blocks.is_breakable(block_id):
					continue
				chunk.data[index] = BlockRegistry.BLOCK_AIR
				_record_edit_in_chunk(position, BlockRegistry.BLOCK_AIR, chunk_position)
				removed += 1
				column_changed = true
				var dy := y - center.y
				if horizontal_squared + dy * dy >= shell_inner_squared:
					water_shell.append(position)
			if column_changed:
				changed_chunks[chunk_position] = true
	for chunk_position in changed_chunks:
		_chunk_edit_version[chunk_position] = _chunk_edit_version.get(chunk_position, 0) + 1
		_stage_chunk_edits(chunk_position)
		rebuild_chunks[chunk_position] = true
		_add_loaded_light_ring(rebuild_chunks, chunk_position)
	for chunk_position in rebuild_chunks:
		# Every sampled neighbor needs fresh light and face data. Preserve this
		# request if its current job captured the pre-explosion snapshot.
		_queue_rebuild(chunk_position, true)
	for position in water_shell:
		for offset in WATER_NEIGHBOR_OFFSETS:
			if _blocks.is_water_id(get_block_world(position + offset)):
				_seed_water(position)
				break
	for position in interior_water:
		_seed_water(position)
	return removed


## Flint and steel either detonates an explosive block or lights fire on the
## face the player clicked. `normal` is the face normal reported by the player's
## voxel raycast, so the fire lands in the air cell in front of the target.
func use_flint_and_steel(block_position: Vector3i, normal: Vector3i) -> Dictionary:
	var block_id := get_block_world(block_position)
	if block_id == BlockRegistry.BLOCK_TNT or block_id == BlockRegistry.BLOCK_NUKE:
		return trigger_explosive(block_position)
	# A flammable block catches fire itself; anything else lights the air cell in
	# front of the clicked face (so flint and steel can still start a ground fire).
	if _blocks.is_flammable(block_id):
		if _is_submerged(block_position):
			return {"ignited": 0, "blocked": "wet"}
		if _burning.has(block_position):
			return {"ignited": 0, "blocked": "burning"}
		if not ignite_fire(block_position):
			return {}
	elif normal != Vector3i.ZERO and ignite_fire(block_position + normal):
		pass
	else:
		return {}
	return {"name": "FIRE", "radius": 0, "removed": 0, "ignited": 1}


## Fire cannot start in a flooded cell: any face touching water counts as
## submerged, which stops flint-and-steel lighting a mangrove log at the
## waterline and keeps the flame out of the water it later seeds back.
func _is_submerged(block_position: Vector3i) -> bool:
	for offset in FIRE_OFFSETS:
		if _blocks.is_water_id(get_block_world(block_position + offset)):
			return true
	return false


## Public ignition entry point. A flammable target starts burning in place (its
## block stays put; `FireOverlay` draws the flames/smoke); an air target gets a
## standalone `BLOCK_FIRE` flame. Burning state is transient, so the overlay is
## refreshed immediately while the world tick keeps it moving.
func ignite_fire(block_position: Vector3i, life := FIRE_LIFETIME_TICKS) -> bool:
	var changed_chunks: Dictionary = {}
	var ignited := false
	if _blocks.is_flammable(get_block_world(block_position)):
		ignited = _start_burning(block_position, changed_chunks)
	else:
		ignited = _ignite_fire_cell(block_position, life, changed_chunks)
	if not ignited:
		return false
	if not changed_chunks.is_empty():
		_flush_fire_changes(changed_chunks)
	if _fire_overlay != null:
		_fire_overlay.refresh(_burning, FUEL_BURN_TICKS)
	return true


## Places a standalone flame in an air cell. Flammable blocks never take this
## path; they burn in place through `_start_burning()`.
func _ignite_fire_cell(block_position: Vector3i, life: int, changed_chunks: Dictionary) -> bool:
	var chunk := _loaded_chunk_for(block_position)
	if chunk == null or chunk.lod:
		return false
	_restore_chunk_data(chunk)
	var existing := get_block_world(block_position)
	if existing == BlockRegistry.BLOCK_FIRE:
		_fire_life[block_position] = maxi(int(_fire_life.get(block_position, 0)), life)
		_queue_fire(block_position)
		return false
	if existing != BlockRegistry.BLOCK_AIR:
		return false
	chunk.data[_data_index(block_position)] = BlockRegistry.BLOCK_FIRE
	_record_edit(block_position, BlockRegistry.BLOCK_FIRE)
	_fire_life[block_position] = life
	_fire_spread_cooldown[block_position] = FIRE_IGNITION_DELAY_TICKS
	_queue_fire(block_position)
	changed_chunks[_chunk_for_block(block_position)] = true
	return true


## Enters the burning state without touching the block itself: it keeps its
## texture and collision while `FireOverlay` adds the flames and smoke. The
## block is only removed when the burn timer expires. `changed_chunks` stays
## empty because no voxel changed.
func _start_burning(block_position: Vector3i, _changed_chunks: Dictionary) -> bool:
	if not _blocks.is_flammable(get_block_world(block_position)):
		return false
	if _is_submerged(block_position):
		return false
	if _burning.has(block_position):
		return false
	_burning[block_position] = FUEL_BURN_TICKS
	_fire_spread_cooldown[block_position] = FIRE_IGNITION_DELAY_TICKS
	_queue_burning(block_position)
	return true


func _queue_fire(block_position: Vector3i) -> void:
	if block_position.y < 0 or block_position.y >= VoxelDefs.WORLD_HEIGHT:
		return
	if _fire_queued.has(block_position):
		return
	_fire_queued[block_position] = true
	_fire_queue.append(block_position)


func _queue_burning(block_position: Vector3i) -> void:
	if block_position.y < 0 or block_position.y >= VoxelDefs.WORLD_HEIGHT:
		return
	if _burning_queued.has(block_position):
		return
	_burning_queued[block_position] = true
	_burning_queue.append(block_position)


## Fire spreads in discrete ticks. Burning blocks keep their block until the
## timer expires and the destruction is recorded through `_record_edit()`, so
## the settled result (air, destroyed fuel, exploded explosives) survives chunk
## regeneration. A global per-tick ignition budget plus per-cell cooldowns keep
## the front creeping instead of the whole tree catching at once.
func _fire_tick() -> void:
	var budget := FIRE_CELLS_PER_TICK
	var changed_chunks := {}
	_fire_spread_budget = FIRE_SPREAD_PER_TICK if _fire_tick_count % FIRE_SPREAD_PERIOD_TICKS == 0 else 0
	_fire_tick_count += 1
	# Snapshot the cells queued before this tick and clear the live queues so a
	# newly affected cell waits for the next tick. Without this a single cell
	# would re-queue itself and could burn out many times inside one call.
	var snapshot := _fire_queue
	_fire_queue = []
	_fire_queued.clear()
	var index := 0
	while index < snapshot.size() and budget > 0:
		var position: Vector3i = snapshot[index]
		index += 1
		budget -= 1
		if _loaded_chunk_for(position) == null:
			_fire_life.erase(position)
			_fire_spread_cooldown.erase(position)
			continue
		_update_fire_cell(position, changed_chunks)
	_requeue_remaining(snapshot, index, _fire_queue, _fire_queued)
	budget = FIRE_CELLS_PER_TICK
	var burn_snapshot := _burning_queue
	_burning_queue = []
	_burning_queued.clear()
	index = 0
	while index < burn_snapshot.size() and budget > 0:
		var position: Vector3i = burn_snapshot[index]
		index += 1
		budget -= 1
		_update_burning_cell(position, changed_chunks)
	_requeue_remaining(burn_snapshot, index, _burning_queue, _burning_queued)
	_flush_fire_changes(changed_chunks)
	if _fire_overlay != null:
		_fire_overlay.refresh(_burning, FUEL_BURN_TICKS)


func _requeue_remaining(snapshot: Array[Vector3i], start: int, queue: Array[Vector3i], queued: Dictionary) -> void:
	for remaining in range(start, snapshot.size()):
		var position: Vector3i = snapshot[remaining]
		if queued.has(position):
			continue
		queued[position] = true
		queue.append(position)


func _update_fire_cell(position: Vector3i, changed_chunks: Dictionary) -> void:
	if get_block_world(position) != BlockRegistry.BLOCK_FIRE:
		_fire_life.erase(position)
		_fire_spread_cooldown.erase(position)
		return
	var cooldown := _decrement_fire_cooldown(position)
	# Catch adjacent fuel on fire and chain-detonate exposed explosives. A blast
	# carves and records its own edits, so the fire simply stops here.
	var fueled := false
	for offset in FIRE_OFFSETS:
		var neighbor := position + offset
		var neighbor_id := get_block_world(neighbor)
		if neighbor_id == BlockRegistry.BLOCK_TNT or neighbor_id == BlockRegistry.BLOCK_NUKE:
			trigger_explosive(neighbor)
			continue
		if not _blocks.is_flammable(neighbor_id):
			continue
		fueled = true
		if _fire_spread_budget <= 0 or cooldown > 0 or _burning.has(neighbor):
			continue
		if _start_burning(neighbor, changed_chunks):
			_fire_spread_budget -= 1
			cooldown = FIRE_SPREAD_INTERVAL_TICKS
			_fire_spread_cooldown[position] = cooldown
	var life := int(_fire_life.get(position, FIRE_LIFETIME_TICKS)) - 1
	if fueled:
		life = FIRE_LIFETIME_TICKS
	if life <= 0 or not _fire_supported(position):
		_extinguish_fire(position, changed_chunks)
	else:
		_fire_life[position] = life
		_queue_fire(position)


func _update_burning_cell(position: Vector3i, changed_chunks: Dictionary) -> void:
	if _loaded_chunk_for(position) == null:
		_burning.erase(position)
		_fire_spread_cooldown.erase(position)
		return
	# The player broke or replaced the block while it was burning.
	if not _blocks.is_flammable(get_block_world(position)):
		_burning.erase(position)
		_fire_spread_cooldown.erase(position)
		return
	var cooldown := _decrement_fire_cooldown(position)
	for offset in FIRE_OFFSETS:
		var neighbor := position + offset
		var neighbor_id := get_block_world(neighbor)
		if neighbor_id == BlockRegistry.BLOCK_TNT or neighbor_id == BlockRegistry.BLOCK_NUKE:
			trigger_explosive(neighbor)
			continue
		if not _blocks.is_flammable(neighbor_id) or _burning.has(neighbor):
			continue
		if _fire_spread_budget <= 0:
			break
		if cooldown > 0:
			continue
		if _start_burning(neighbor, changed_chunks):
			_fire_spread_budget -= 1
			cooldown = FIRE_SPREAD_INTERVAL_TICKS
			_fire_spread_cooldown[position] = cooldown
	# A chain blast in the loop above may have carved this very block; bail before
	# re-recording an AIR edit that `carve_sphere` already handled.
	if not _blocks.is_flammable(get_block_world(position)):
		_burning.erase(position)
		_fire_spread_cooldown.erase(position)
		return
	var ticks := int(_burning[position]) - 1
	if ticks <= 0:
		_burning.erase(position)
		_fire_spread_cooldown.erase(position)
		_destroy_burnt_block(position, changed_chunks)
		return
	_burning[position] = ticks
	_queue_burning(position)


func _decrement_fire_cooldown(position: Vector3i) -> int:
	var cooldown := int(_fire_spread_cooldown.get(position, 0))
	if cooldown > 0:
		cooldown -= 1
		_fire_spread_cooldown[position] = cooldown
	return cooldown


## Fire needs any non-air, non-water neighbor to keep burning (solid blocks,
## glass, foliage, even other fire); otherwise it floats in air and dies.
func _fire_supported(position: Vector3i) -> bool:
	for offset in FIRE_OFFSETS:
		var neighbor_id := get_block_world(position + offset)
		if neighbor_id == BlockRegistry.BLOCK_AIR or _blocks.is_water_id(neighbor_id):
			continue
		return true
	return false


func _extinguish_fire(position: Vector3i, changed_chunks: Dictionary) -> void:
	_fire_life.erase(position)
	_fire_spread_cooldown.erase(position)
	var chunk := _loaded_chunk_for(position)
	if chunk == null or chunk.lod:
		return
	_restore_chunk_data(chunk)
	if get_block_world(position) != BlockRegistry.BLOCK_FIRE:
		return
	chunk.data[_data_index(position)] = BlockRegistry.BLOCK_AIR
	_record_edit(position, BlockRegistry.BLOCK_AIR)
	_seed_water(position)
	changed_chunks[_chunk_for_block(position)] = true


## Final state of a burnt block: it crumbles to ash and disappears. This is the
## only voxel change in the burning lifecycle, so it is the one persisted. Like
## `break_block()`/`carve_sphere()`, the new air lets adjacent water flow in.
func _destroy_burnt_block(position: Vector3i, changed_chunks: Dictionary) -> void:
	var chunk := _loaded_chunk_for(position)
	if chunk == null or chunk.lod:
		return
	_restore_chunk_data(chunk)
	chunk.data[_data_index(position)] = BlockRegistry.BLOCK_AIR
	_record_edit(position, BlockRegistry.BLOCK_AIR)
	_seed_water(position)
	changed_chunks[_chunk_for_block(position)] = true


## Batches fire edits like the water tick: each touched chunk is versioned once
## and its full light ring invalidated once, however many cells changed.
func _flush_fire_changes(changed_chunks: Dictionary) -> void:
	if changed_chunks.is_empty():
		return
	var rebuild_chunks := {}
	for chunk_position in changed_chunks:
		_chunk_edit_version[chunk_position] = _chunk_edit_version.get(chunk_position, 0) + 1
		_stage_chunk_edits(chunk_position)
		rebuild_chunks[chunk_position] = true
		_add_loaded_light_ring(rebuild_chunks, chunk_position)
	for chunk_position in rebuild_chunks:
		_queue_rebuild(chunk_position, true)


func _record_edit(block_position: Vector3i, block_id: int) -> void:
	_record_edit_in_chunk(block_position, block_id, _chunk_for_block(block_position))


func _record_edit_in_chunk(block_position: Vector3i, block_id: int, chunk_position: Vector2i) -> void:
	_edited_blocks[block_position] = block_id
	var bucket = _edits_by_chunk.get(chunk_position)
	if bucket == null:
		bucket = {}
		_edits_by_chunk[chunk_position] = bucket
	bucket[block_position] = block_id


func _chunk_edits_for(pos: Vector2i) -> Dictionary:
	_hydrate_chunk_edits(pos)
	var bucket = _edits_by_chunk.get(pos)
	if bucket == null:
		return {}
	return bucket.duplicate()


func _hydrate_chunk_edits(pos: Vector2i) -> void:
	if _hydrated_edit_chunks.has(pos):
		return
	_hydrated_edit_chunks[pos] = true
	if _edit_store == null:
		return
	var edits := _edit_store.load_chunk_edits(pos)
	if edits.is_empty():
		return
	_edits_by_chunk[pos] = edits
	for position in edits:
		_edited_blocks[position] = edits[position]


func _stage_chunk_edits(pos: Vector2i) -> void:
	if _edit_store == null:
		return
	var bucket: Dictionary = _edits_by_chunk.get(pos, {})
	_edit_store.stage_chunk_edits(pos, bucket)


## A regenerated chunk can bring persisted fire back from `_edited_blocks`.
## Re-arm those cells so a still-burning edit resumes its live simulation
## instead of sitting as an immortal flame after an unload/reload cycle.
func _seed_fire_edits(pos: Vector2i) -> void:
	var bucket = _edits_by_chunk.get(pos)
	if bucket == null:
		return
	for key in bucket:
		if int(bucket[key]) != BlockRegistry.BLOCK_FIRE:
			continue
		if not _fire_life.has(key):
			_fire_life[key] = FIRE_LIFETIME_TICKS
		_queue_fire(key)


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
	var changed_chunks := {}
	while budget > 0 and _water_head < _water_queue.size():
		var position: Vector3i = _water_queue[_water_head]
		_water_head += 1
		budget -= 1
		_water_queued.erase(position)
		if _loaded_chunk_for(position) == null:
			continue
		_update_water_cell(position, changed_chunks)
	if not changed_chunks.is_empty():
		var rebuild_chunks := {}
		for chunk_position in changed_chunks:
			_chunk_edit_version[chunk_position] = _chunk_edit_version.get(chunk_position, 0) + 1
			_stage_chunk_edits(chunk_position)
			rebuild_chunks[chunk_position] = true
			_add_loaded_light_ring(rebuild_chunks, chunk_position)
		for chunk_position in rebuild_chunks:
			_queue_rebuild(chunk_position, true)
	if _water_head == _water_queue.size():
		_water_queue.clear()
		_water_head = 0
	elif _water_head > 4096:
		_water_queue = _water_queue.slice(_water_head)
		_water_head = 0


func _update_water_cell(position: Vector3i, changed_chunks: Dictionary) -> void:
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
		_water_place(position, _blocks.water_id_for_level(feed), changed_chunks)
	if feed <= 0:
		return
	var below := get_block_world(position + Vector3i(0, -1, 0))
	if below == BlockRegistry.BLOCK_AIR:
		if position.y > 1:
			_water_place(position + Vector3i(0, -1, 0), _blocks.water_id_for_level(7), changed_chunks)
		return
	if feed <= 1:
		return
	for direction in VoxelDefs.DIRS_4:
		var target := position + Vector3i(direction.x, 0, direction.y)
		var target_id := get_block_world(target)
		if target_id == BlockRegistry.BLOCK_AIR:
			_water_place(target, _blocks.water_id_for_level(feed - 1), changed_chunks)
		elif _blocks.is_water_id(target_id) and target_id != BlockRegistry.BLOCK_WATER and _blocks.water_level(target_id) < feed - 1:
			_water_place(target, _blocks.water_id_for_level(feed - 1), changed_chunks)


func _water_place(position: Vector3i, block_id: int, changed_chunks: Dictionary) -> void:
	var chunk := _loaded_chunk_for(position)
	if chunk == null or chunk.lod:
		return
	_restore_chunk_data(chunk)
	var index := _data_index(position)
	if chunk.data[index] == block_id:
		return
	chunk.data[index] = block_id
	_record_edit(position, block_id)
	changed_chunks[_chunk_for_block(position)] = true
	for offset in WATER_NEIGHBOR_OFFSETS:
		_queue_water(position + offset)


## Single-cell edits always remesh their owner. Neighbor snapshots only need
## invalidating when light can actually change, except at the edited chunk's
## boundary where equal-attenuation blocks can still change emitted faces/AO.
## Batch edits intentionally retain `_add_loaded_light_ring()` because keeping
## every changed position to make this decision would defeat their batching.
func _touch_chunk(chunk_position: Vector2i, block_position: Vector3i,
		old_block_id: int, new_block_id: int) -> void:
	_chunk_edit_version[chunk_position] = _chunk_edit_version.get(chunk_position, 0) + 1
	_stage_chunk_edits(chunk_position)
	var rebuild_neighbors: Array[Vector2i] = []
	for direction in VoxelDefs.DIRS_8:
		var neighbor_position: Vector2i = chunk_position + direction
		if _chunks.has(neighbor_position) \
				and _single_edit_can_invalidate_neighbor(old_block_id, new_block_id,
					block_position, neighbor_position):
			rebuild_neighbors.append(neighbor_position)
	# Neighbor light/seam updates remain required, but the edited owner controls
	# interaction feedback and collision. Queue neighbors at the back and the
	# owner last at the front so mining/placing cannot sit behind several heavy
	# light-volume remeshes while extreme-distance streaming is active.
	for neighbor_position in rebuild_neighbors:
		_queue_rebuild(neighbor_position, true, true)
	_queue_rebuild(chunk_position, true)


## Light volumes are identical outside the owner unless a cell's attenuation
## or emission changes. Comparing the actual emission color also catches two
## different colored emitters (for example, torch -> glowstone).
static func _single_edit_requires_light_neighbor_rebuild(old_block_id: int,
		new_block_id: int) -> bool:
	return _light_attenuation_for_id(old_block_id) != _light_attenuation_for_id(new_block_id) \
		or _is_emissive_id(old_block_id) != _is_emissive_id(new_block_id) \
		or _emission_color_for_id(old_block_id) != _emission_color_for_id(new_block_id)


## Equal attenuation does not imply equal boundary mesh topology. Transparent
## cube faces are culled against an equal neighbour, while water levels alter
## water-face culling. Opaque swaps and like-for-like foliage remain stable.
static func _single_edit_can_change_boundary_visibility(old_block_id: int,
		new_block_id: int) -> bool:
	if old_block_id == new_block_id \
			or _light_attenuation_for_id(old_block_id) != _light_attenuation_for_id(new_block_id):
		return false
	if _water_level_for_id(old_block_id) != _water_level_for_id(new_block_id):
		return true
	if _is_cross_id(old_block_id) != _is_cross_id(new_block_id):
		return true
	return _is_nonopaque_cube_id(old_block_id) or _is_nonopaque_cube_id(new_block_id)


## Selects one loaded neighbour for a one-cell edit. Lighting may reach into a
## nearby chunk within its finite Manhattan range; equal-attenuation geometry
## only reaches chunks sharing the edited cell's edge or corner.
static func _single_edit_can_invalidate_neighbor(old_block_id: int, new_block_id: int,
		block_position: Vector3i, neighbor_position: Vector2i) -> bool:
	if _single_edit_requires_light_neighbor_rebuild(old_block_id, new_block_id):
		return _light_can_reach_chunk_horizontally(block_position, neighbor_position)
	return _single_edit_can_change_boundary_visibility(old_block_id, new_block_id) \
		and _block_touches_chunk_boundary(block_position, neighbor_position)


static func _light_attenuation_for_id(block_id: int) -> int:
	if _is_opaque_id(block_id):
		return BlockRegistry.MAX_LIGHT_LEVEL
	if _is_water_id(block_id):
		return BlockRegistry.ATTENUATION_WATER
	if (_block_flags_for_id(block_id) & BlockRegistry.FLAG_LEAVES) != 0:
		return BlockRegistry.ATTENUATION_LEAVES
	return 0


static func _is_opaque_id(block_id: int) -> bool:
	return (_block_flags_for_id(block_id) & BlockRegistry.FLAG_OPAQUE) != 0


static func _is_nonopaque_cube_id(block_id: int) -> bool:
	return block_id != BlockRegistry.BLOCK_AIR and not _is_opaque_id(block_id) \
		and not _is_water_id(block_id) \
		and (_block_flags_for_id(block_id) & (BlockRegistry.FLAG_CROSS | BlockRegistry.FLAG_LEAVES)) == 0


static func _is_cross_id(block_id: int) -> bool:
	return (_block_flags_for_id(block_id) & BlockRegistry.FLAG_CROSS) != 0


static func _is_water_id(block_id: int) -> bool:
	return block_id == BlockRegistry.BLOCK_WATER \
		or (block_id >= BlockRegistry.BLOCK_WATER_FLOW_7 and block_id <= BlockRegistry.BLOCK_WATER_FLOW_1)


static func _water_level_for_id(block_id: int) -> int:
	if block_id == BlockRegistry.BLOCK_WATER:
		return 8
	if block_id >= BlockRegistry.BLOCK_WATER_FLOW_7 and block_id <= BlockRegistry.BLOCK_WATER_FLOW_1:
		return BlockRegistry.BLOCK_WATER_FLOW_1 - block_id + 1
	return 0


static func _is_emissive_id(block_id: int) -> bool:
	return ((_block_flags_for_id(block_id) & BlockRegistry.FLAG_EMISSIVE) != 0 \
		or BlockRegistry.EMISSIVE_COLORS.has(block_id)) and block_id > BlockRegistry.BLOCK_AIR


static func _emission_color_for_id(block_id: int) -> Color:
	return BlockRegistry.EMISSIVE_COLORS.get(block_id, Color.BLACK)


static func _block_flags_for_id(block_id: int) -> int:
	if block_id < BlockRegistry.BLOCK_AIR or block_id >= BlockRegistry.BLOCK_DEFS.size():
		return 0
	return int(BlockRegistry.BLOCK_DEFS[block_id][5])


static func _block_touches_chunk_boundary(block_position: Vector3i,
		neighbor_position: Vector2i) -> bool:
	var owner := Vector2i(
		floori(float(block_position.x) / float(VoxelDefs.CHUNK_SIZE)),
		floori(float(block_position.z) / float(VoxelDefs.CHUNK_SIZE))
	)
	var direction := neighbor_position - owner
	if absi(direction.x) > 1 or absi(direction.y) > 1 or direction == Vector2i.ZERO:
		return false
	var local_x := block_position.x - owner.x * VoxelDefs.CHUNK_SIZE
	var local_z := block_position.z - owner.y * VoxelDefs.CHUNK_SIZE
	var touches_x := direction.x == 0 \
		or (direction.x < 0 and local_x == 0) \
		or (direction.x > 0 and local_x == VoxelDefs.CHUNK_SIZE - 1)
	var touches_z := direction.y == 0 \
		or (direction.y < 0 and local_z == 0) \
		or (direction.y > 0 and local_z == VoxelDefs.CHUNK_SIZE - 1)
	return touches_x and touches_z


## Returns whether any horizontal cell in `chunk_position` lies within the
## bounded baked-light propagation range of `block_position`. The interval
## calculation is valid for negative world/chunk coordinates and naturally
## handles diagonals through Manhattan distance.
static func _light_can_reach_chunk_horizontally(block_position: Vector3i,
		chunk_position: Vector2i) -> bool:
	var min_x := chunk_position.x * VoxelDefs.CHUNK_SIZE
	var min_z := chunk_position.y * VoxelDefs.CHUNK_SIZE
	var max_x := min_x + VoxelDefs.CHUNK_SIZE - 1
	var max_z := min_z + VoxelDefs.CHUNK_SIZE - 1
	var x_distance := _distance_to_closed_interval(block_position.x, min_x, max_x)
	var z_distance := _distance_to_closed_interval(block_position.z, min_z, max_z)
	return x_distance + z_distance <= LIGHT_MAX_PROPAGATION_DISTANCE


static func _distance_to_closed_interval(value: int, minimum: int, maximum: int) -> int:
	if value < minimum:
		return minimum - value
	if value > maximum:
		return value - maximum
	return 0


func _add_loaded_light_ring(rebuilds: Dictionary, chunk_position: Vector2i) -> void:
	for direction in VoxelDefs.DIRS_8:
		if _chunks.has(chunk_position + direction):
			rebuilds[chunk_position + direction] = true


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


## Immutable block tables + texture array; used by HUD/inventory icon renderers.
func get_registry() -> BlockRegistry:
	return _blocks


func get_biome_name(world_position: Vector3) -> String:
	return _generator.biome_name(world_position)


## Cheap dominant-biome id for ambience grading (weather precipitation, wind
## bed, mist). No raw/slope work, so it is safe on the throttled weather poll.
func get_biome_id(world_position: Vector3) -> int:
	return _generator.biome_id_at(floori(world_position.x), floori(world_position.z))


func get_worldgen_stats() -> Dictionary:
	var full_chunks := 0
	var lod_chunks := 0
	for chunk_value in _chunks.values():
		var chunk := chunk_value as Chunk
		if chunk.lod:
			lod_chunks += 1
		else:
			full_chunks += 1
	return {
		"chunks": "%d full / %d lod" % [full_chunks, lod_chunks],
		"pending": _pending.size(),
		"queued": _gen_queue.size() + _mesh_queue.size(),
		"generated waiting": _generated.size(),
		"commits": _commit_queue.size(),
		"gen ms ema": _generation_ema_ms,
		"terrain ms": _terrain_ema_ms,
		"populate ms": _populate_ema_ms,
		"mesh ms ema": _mesh_ema_ms,
		"revision": _worldgen_revision,
	}


## Starts or polls an asynchronous diagnostic-map request. The expensive noise
## sampling never blocks the main thread; callers receive `pending = true`
## until the immutable worker result is available.
##
## `sample_size` is the requested raster width in pixels (and `stride` the
## requested blocks per pixel): `max_resolution` caps the pixels actually
## sampled, and the stride is scaled so the requested world span is preserved.
## The default 32 keeps the F3 overlay's historical detail and cost; the HUD
## map views pass a higher cap for sharper rasters.
func request_debug_map(mode: String, center: Vector2i, sample_size: int, stride: int, max_resolution: int = 32) -> Dictionary:
	_collect_debug_map()
	var resolution := clampi(sample_size, 16, clampi(max_resolution, 16, DEBUG_MAP_MAX_RESOLUTION))
	if mode in DEBUG_MAP_HEAVY_MODES:
		resolution = mini(resolution, DEBUG_MAP_HEAVY_RESOLUTION)
	var resolution_scale := maxi(1, ceili(float(sample_size) / float(resolution)))
	var safe_stride := clampi(stride * resolution_scale, 1, 32)
	var key := "%s:%d:%d:%d:%d:%d" % [mode, center.x, center.y, resolution, safe_stride, _worldgen_revision]
	if _debug_cache.has(key):
		return _debug_cache[key]
	if _debug_task < 0:
		_debug_key = key
		_debug_slot = {}
		# The F3 overlay's small rasters stay ahead of streaming; the larger
		# HUD/atlas rasters queue normally so they cannot stall chunk jobs.
		_debug_task = WorkerThreadPool.add_task(
			_run_debug_map_job.bind(mode, center, resolution, safe_stride, _debug_slot),
			resolution <= 32,
			"worldgen_debug_map")
	return {"pending": true, "width": resolution, "height": resolution}


func _run_debug_map_job(mode: String, center: Vector2i, resolution: int, stride: int, slot: Dictionary) -> void:
	slot["result"] = _generator.build_debug_map(mode, center, resolution, stride)


func _collect_debug_map() -> void:
	if _debug_task < 0 or not WorkerThreadPool.is_task_completed(_debug_task):
		return
	WorkerThreadPool.wait_for_task_completion(_debug_task)
	if _debug_slot.has("result"):
		_debug_cache[_debug_key] = _debug_slot["result"]
		if _debug_cache.size() > 8:
			_debug_cache.erase(_debug_cache.keys()[0])
	_debug_task = -1
	_debug_slot = {}
	_debug_key = ""


func get_loaded_chunk_count() -> int:
	return _chunks.size()


func get_blocks_material() -> Material:
	return _blocks.material


func make_block_mesh(block_id: int) -> ArrayMesh:
	return _mesher.make_block_mesh(block_id)
