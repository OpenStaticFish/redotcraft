class_name VoxelWorld
extends Node3D

## Main-thread streaming telemetry. Worker jobs only write their private slots;
## these snapshots are assembled after completion/commit on the scene thread.
signal stream_progress_changed(progress: Dictionary)
signal initial_stream_ready

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
## Balanced LOD can reduce its opaque terrain submissions by combining four
## already-built compact chunk meshes. This is strictly a render-only cache:
## generation, edit ownership, neighbour snapshots, collision, and water stay
## with their authoritative chunks. One upload per frame keeps this optional
## presentation work from becoming a distant-streaming hitch.
const LOD_BATCH_SIZE := 2
const MAX_LOD_BATCH_UPLOADS_PER_TICK := 1
const MAX_QUEUED_LOD_BATCHES := 64
## The cap is deliberately below a worst-case group: an aggregate is rebuilt
## from four GPU surfaces on the main thread, so a pathological cliff/canopy
## group must gracefully keep its source meshes instead of causing a long hitch.
const MAX_LOD_BATCH_VERTICES := 16384
const MAX_LOD_BATCH_INDICES := 24576
const MAX_LOD_BATCH_REFILL_CANDIDATES_PER_TICK := 12
const BATCH_UPLOAD_SOFT_BUDGET_USEC := 1000
const STREAM_PROGRESS_INTERVAL := 0.15
## Diagnostic map rasters resolve one mode sample per pixel. The final-height
## family walks the erosion graph five times per sample, so map views request
## fewer pixels for those modes instead of freezing their refresh for seconds.
const DEBUG_MAP_MAX_RESOLUTION := 128
const DEBUG_MAP_HEAVY_RESOLUTION := 64
const DEBUG_MAP_HEAVY_MODES: Array[String] = ["height", "raw_height", "slope"]
const REBUILD_OPPOSITE_BITS := [2, 1, 8, 4, 128, 64, 32, 16]
const WATER_TICK_INTERVAL := 0.25
const WATER_CELLS_PER_TICK := 1024
## Falling blocks use the same bounded main-thread cadence as water. A block
## advances one cell per tick so a large collapse cannot stall one frame.
const GRAVITY_TICK_INTERVAL := 0.25
const GRAVITY_CELLS_PER_TICK := 512
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
## Experimental: it is off by default even in Balanced LOD until a target
## machine profile demonstrates that its draw-call reduction beats coarser
## 2x2 visibility culling. Full Detail never enters this path.
var lod_batching_enabled := false

var _blocks: BlockRegistry
var _generator: TerrainGenerator
var _mesher: ChunkMesher

var _chunks: Dictionary = {}
var _pending: Dictionary = {}
var _commit_queue: Array = []
var _lod_batches: Dictionary = {}
var _lod_batch_queue: Array[Vector2i] = []
var _lod_batch_queued: Dictionary = {}
var _lod_batch_rejected: Dictionary = {}
var _lod_batch_refill_found_work := false
var _lod_batch_uploads := 0
var _lod_batch_skipped := 0
var _lod_batch_geometry_rejected := 0
var _lod_batch_refill_cursor := 0
var _lod_batch_refill_complete := false
var _lod_batch_refill_passes := 0
var _commit_budget_used_usec := 0
var _gen_queue: Array[Vector2i] = []
var _gen_queued: Dictionary = {}
var _mesh_queue: Array[Vector2i] = []
var _mesh_queued: Dictionary = {}
var _generated: Dictionary = {}
var _dirty: Dictionary = {}
var _desired: Dictionary = {}
var _streamed_count := 0
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
var _gravity_queue: Array[Vector3i] = []
var _gravity_queued: Dictionary = {}
var _gravity_seeded_chunks: Dictionary = {}
var _gravity_head := 0
var _gravity_accum := 0.0
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
var _stream_progress_time := 0.0
var _initial_stream_center := Vector2i(999999, 999999)
var _initial_stream_active := false
var _initial_stream_complete := false
var _max_active_jobs := MIN_ACTIVE_JOBS
var _generation_jobs := 0
var _mesh_jobs := 0
var _discarded_jobs := 0
var _generation_usec := 0
var _mesh_usec := 0
var _commit_usec := 0
var _stream_main_usec := 0
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
## Future hostile-entity systems can install this query without coupling block
## interactions to an entity implementation. Until mobs land there are no
## threats, but sleeping already honors the contract when a query is present.
var threat_check: Callable = Callable()


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


## A batch deliberately contains no voxel state and no physics. It owns only
## one opaque MeshInstance3D plus the four source positions whose original
## render instances are hidden while this cache is valid.
class LodRenderBatch:
	var members: Array[Vector2i] = []
	var mesh: MeshInstance3D


func _ready() -> void:
	# Menus pause simulation, not the background terrain pipeline.
	process_mode = Node.PROCESS_MODE_ALWAYS
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
	_stream_progress_time += delta
	if _stream_progress_time >= STREAM_PROGRESS_INTERVAL:
		_stream_progress_time = 0.0
		_emit_stream_progress()
	if get_tree().paused:
		return
	_water_accum += delta
	if _water_accum >= WATER_TICK_INTERVAL:
		_water_accum = 0.0
		_water_tick()
	_gravity_accum += delta
	if _gravity_accum >= GRAVITY_TICK_INTERVAL:
		_gravity_accum = 0.0
		_gravity_tick()
	_fire_accum += delta
	if _fire_accum >= FIRE_TICK_INTERVAL:
		_fire_accum = 0.0
		_fire_tick()


func _exit_tree() -> void:
	_clear_lod_batches()
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
	_gravity_seeded_chunks.clear()
	_edited_blocks.clear()
	_edits_by_chunk.clear()


func flush_edit_store() -> Error:
	if _edit_store == null:
		return OK
	return _edit_store.flush_dirty_regions()


func set_render_distance(value: int) -> void:
	var normalized := maxi(value, 1)
	if render_distance == normalized:
		return
	render_distance = normalized
	# A changed boundary can turn one member of a cached 2x2 compact group into
	# Full Detail. Reveal source meshes before the asynchronous transition lands.
	_clear_lod_batches()
	_update_lod_distance()
	unload_radius = render_distance + 2
	_rebuild_desired()
	_unload_far()


func set_lod_mode(value: int) -> void:
	var normalized := clampi(value, LOD_MODE_FULL, LOD_MODE_BALANCED)
	if lod_mode == normalized:
		return
	lod_mode = normalized
	_clear_lod_batches()
	_update_lod_distance()
	_rebuild_desired()


## Exposed for controlled Forward+ A/B profiling and safe fallback on hardware
## where four-way array uploads do not pay for their draw-call reduction.
func set_lod_batching_enabled(enabled: bool) -> void:
	if lod_batching_enabled == enabled:
		return
	lod_batching_enabled = enabled
	_clear_lod_batches()
	_reset_lod_batch_refill()


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


## Starts the first world entry without synchronously generating a spawn ring.
## Main keeps player input locked until `initial_stream_ready`; all chunk work
## continues through the ordinary nearest-first worker queues.
func begin_initial_stream(player_node: Node3D) -> void:
	_player = player_node
	_stream_center = _chunk_for_position(player_node.global_position)
	_initial_stream_center = _stream_center
	_initial_stream_active = true
	_initial_stream_complete = false
	_stream_progress_time = 0.0
	_rebuild_desired()
	_schedule_jobs()
	_emit_stream_progress()


func _stream_tick() -> void:
	var started := Time.get_ticks_usec()
	var center := _chunk_for_position(_player.global_position)
	if center != _stream_center:
		_stream_center = center
		_rebuild_desired()
		_unload_far()
		_drop_far_collision()
	_collect_jobs()
	_process_commit_queue()
	_process_lod_batch_queue()
	# Discover missing nearby collision before assigning newly-opened worker
	# slots. Otherwise generation can refill every slot first while boosted
	# flight waits on a floor remesh that was only queued afterward.
	_ensure_near_collision()
	_schedule_jobs()
	_update_initial_stream_state()
	_stream_main_usec += Time.get_ticks_usec() - started


func _update_initial_stream_state() -> void:
	if not _initial_stream_active or _initial_stream_complete:
		return
	for dz in range(-SPAWN_RADIUS, SPAWN_RADIUS + 1):
		for dx in range(-SPAWN_RADIUS, SPAWN_RADIUS + 1):
			var pos := _initial_stream_center + Vector2i(dx, dz)
			var chunk: Chunk = _chunks.get(pos)
			if chunk == null or chunk.lod or not _is_chunk_collision_ready(pos):
				return
	_initial_stream_complete = true
	_emit_stream_progress()
	initial_stream_ready.emit()


## Distant full chunks are committed without a collision shape. Rebuilds are
## only requested as the player gets close, which keeps shape memory bounded to
## the local area while the world stays full-detail everywhere in range.
func _ensure_near_collision() -> void:
	for dz in range(-COLLISION_DISTANCE, COLLISION_DISTANCE + 1):
		for dx in range(-COLLISION_DISTANCE, COLLISION_DISTANCE + 1):
			var pos := _stream_center + Vector2i(dx, dz)
			if not _desired.has(pos):
				continue
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
			_queue_rebuild(pos)


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
	_streamed_count = 0
	_mesh_queue.clear()
	_mesh_queued.clear()
	var wanted: Array[Vector2i] = []
	# Build in nearest-first Chebyshev rings instead of filling a square and
	# sorting thousands of entries every time the player crosses a chunk edge.
	# At extreme distances this removes a large main-thread O(n log n) hitch.
	for ring in range(render_distance + 1):
		for dx in range(-ring, ring + 1):
			# Enumerate the perimeter itself, not every interior cell on every
			# ring (the latter visits O(radius^3) cells during a distance change).
			var zs := range(-ring, ring + 1) if absi(dx) == ring else [-ring, ring]
			for dz in zs:
				var pos := _stream_center + Vector2i(dx, dz)
				_desired[pos] = true
				var want_lod := _chunk_uses_lod(pos)
				if _chunks.has(pos) and (_chunks[pos] as Chunk).lod != want_lod:
					_dirty[pos] = true
				elif _chunks.has(pos):
					_streamed_count += 1
				var staged: TerrainGenerator.GenResult = _generated.get(pos)
				if staged != null and (staged.lod != want_lod \
						or staged.config_revision != _worldgen_revision):
					_generated.erase(pos)
				if not _chunks.has(pos) and not _generated.has(pos) and not _pending.has(pos):
					wanted.append(pos)
	_gen_queue = wanted
	_gen_queued.clear()
	for pos in _gen_queue:
		_gen_queued[pos] = false
	# Bottom-up heap construction is linear, including at Extreme distance.
	for index in range(_gen_queue.size() / 2 - 1, -1, -1):
		_work_sift_down(_gen_queue, _gen_queued, index)
	for pos in _dirty.keys():
		if _desired.has(pos) and not _pending.has(pos) and not _gen_queued.has(pos):
			_queue_rebuild(pos)
	for pos in _generated.keys():
		if not _desired.has(pos):
			_generated.erase(pos)
		else:
			_queue_generated_mesh_if_ready(pos)
	_reconcile_lod_batches()
	_reset_lod_batch_refill()


func _schedule_jobs() -> void:
	if _gen_queue.is_empty() and _mesh_queue.is_empty():
		return
	while not _mesh_queue.is_empty() or not _gen_queue.is_empty():
		if _pending.size() > _max_active_jobs:
			break
		var mesh_job := _next_work_is_mesh()
		var next_pos: Vector2i = _mesh_queue[0] if mesh_job else _gen_queue[0]
		var urgent := not _chunk_uses_lod(next_pos) and _within_collision_range(next_pos)
		if _pending.size() >= _max_active_jobs and not urgent:
			break
		# Only nearby full-detail work can use the one bounded overflow slot.
		var pos: Vector2i
		if mesh_job:
			pos = _work_pop(_mesh_queue, _mesh_queued)
		else:
			pos = _work_pop(_gen_queue, _gen_queued)
		if not _desired.has(pos):
			continue
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
		if job.kind == "generate":
			_generation_jobs += 1
		else:
			_mesh_jobs += 1


## Queues are min-heaps. The membership maps also mark urgent edited owners.
## Keys depend only on the stream center and that mark, not mutable chunk state.
## Re-centering rebuilds both heaps; queued edits can only promote an entry.
func _work_priority(pos: Vector2i, edited: bool) -> int:
	var offset := pos - _stream_center
	var ring := maxi(absi(offset.x), absi(offset.y))
	var tier := 4
	if ring == 0:
		tier = 0
	elif ring <= SPAWN_RADIUS:
		tier = 1 if edited else 2
	elif ring <= COLLISION_DISTANCE:
		tier = 3
	return tier * 1000000000 + offset.length_squared()


func _work_less(a: Vector2i, b: Vector2i, queued: Dictionary) -> bool:
	var a_priority := _work_priority(a, bool(queued.get(a, false)))
	var b_priority := _work_priority(b, bool(queued.get(b, false)))
	if a_priority != b_priority:
		return a_priority < b_priority
	return a.x < b.x or (a.x == b.x and a.y < b.y)


func _work_push(queue: Array[Vector2i], queued: Dictionary, pos: Vector2i, edited := false) -> void:
	var index := queue.size()
	if queued.has(pos):
		if not edited or bool(queued[pos]):
			return
		index = queue.find(pos)
	else:
		queue.append(pos)
	queued[pos] = edited
	while index > 0:
		var parent := (index - 1) / 2
		if not _work_less(queue[index], queue[parent], queued):
			break
		var swap := queue[parent]
		queue[parent] = queue[index]
		queue[index] = swap
		index = parent


func _work_sift_down(queue: Array[Vector2i], queued: Dictionary, index: int) -> void:
	while index * 2 + 1 < queue.size():
		var child := index * 2 + 1
		if child + 1 < queue.size() and _work_less(queue[child + 1], queue[child], queued):
			child += 1
		if not _work_less(queue[child], queue[index], queued):
			return
		var swap := queue[index]
		queue[index] = queue[child]
		queue[child] = swap
		index = child


func _work_pop(queue: Array[Vector2i], queued: Dictionary) -> Vector2i:
	var pos := queue[0]
	var last: Vector2i = queue.pop_back()
	queued.erase(pos)
	if not queue.is_empty():
		queue[0] = last
		_work_sift_down(queue, queued, 0)
	return pos


func _next_work_is_mesh() -> bool:
	if _mesh_queue.is_empty():
		return false
	if _gen_queue.is_empty():
		return true
	# Finish render/collision work first only when its priority is at least as
	# close. Distant completed terrain must not starve nearby missing chunks.
	return _work_priority(_mesh_queue[0], bool(_mesh_queued[_mesh_queue[0]])) \
		<= _work_priority(_gen_queue[0], bool(_gen_queued[_gen_queue[0]]))


func _process_commit_queue() -> void:
	var start := Time.get_ticks_msec()
	_commit_budget_used_usec = 0
	while not _commit_queue.is_empty():
		var commit_index := _next_commit_index()
		var item: CommitItem = _commit_queue[commit_index]
		_commit_queue.remove_at(commit_index)
		if not _desired.has(item.pos):
			_discarded_jobs += 1
			_discard_unloaded_chunk_state(item.pos)
			continue
		var mode_stale := item.lod != _chunk_uses_lod(item.pos)
		if item.version != _chunk_edit_version.get(item.pos, 0) or item.config_revision != _worldgen_revision or mode_stale:
			_discarded_jobs += 1
			_queue_rebuild(item.pos)
			continue
		var commit_start := Time.get_ticks_usec()
		_commit_chunk(item.pos, item.result, item.lod)
		_commit_usec += Time.get_ticks_usec() - commit_start
		if Time.get_ticks_msec() - start > COMMIT_BUDGET_MS:
			break
	_commit_budget_used_usec = Time.get_ticks_usec() - start * 1000


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
		if job.kind == "generate":
			var generated_result: TerrainGenerator.GenResult = job.slot.get("generated")
			if generated_result != null:
				_generation_usec += int(generated_result.timings.get("generation_us", 0))
		else:
			_mesh_usec += int(job.slot.get("mesh_us", 0))
		if not _desired.has(pos):
			# No off-screen result is useful. Purging only after the worker has
			# completed preserves its edit-version stale check until this point.
			_discarded_jobs += 1
			_discard_unloaded_chunk_state(pos)
			continue
		if _dirty.has(pos):
			_discarded_jobs += 1
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
				_discarded_jobs += 1
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
	_work_push(_mesh_queue, _mesh_queued, pos)


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


## Groups are aligned in chunk coordinates (including negatives) so a stream
## recenter never changes ownership. They only combine opaque compact LOD
## surfaces; water remains per chunk to retain the renderer's existing
## transparent-object ordering and culling behaviour.
func _lod_batch_key(pos: Vector2i) -> Vector2i:
	return Vector2i(floori(float(pos.x) / float(LOD_BATCH_SIZE)),
		floori(float(pos.y) / float(LOD_BATCH_SIZE)))


func _lod_batch_members(key: Vector2i) -> Array[Vector2i]:
	var origin := key * LOD_BATCH_SIZE
	return [origin, origin + Vector2i(1, 0), origin + Vector2i(0, 1), origin + Vector2i(1, 1)]


func _lod_batch_priority(key: Vector2i) -> int:
	var center := key * LOD_BATCH_SIZE + Vector2i(1, 1)
	return (center - _stream_center).length_squared()


func _queue_lod_batch_for(pos: Vector2i) -> void:
	if not lod_batching_enabled or not _chunk_uses_lod(pos):
		return
	_lod_batch_refill_complete = false
	var key := _lod_batch_key(pos)
	if _lod_batches.has(key):
		_invalidate_lod_batch(key)
	if _lod_batch_queued.has(key):
		return
	if _lod_batch_queue.size() >= MAX_QUEUED_LOD_BATCHES:
		var furthest_index := 0
		var furthest_priority := _lod_batch_priority(_lod_batch_queue[0])
		for index in range(1, _lod_batch_queue.size()):
			var priority := _lod_batch_priority(_lod_batch_queue[index])
			if priority > furthest_priority:
				furthest_index = index
				furthest_priority = priority
		if _lod_batch_priority(key) >= furthest_priority:
			_lod_batch_skipped += 1
			return
		var evicted: Vector2i = _lod_batch_queue[furthest_index]
		_lod_batch_queue.remove_at(furthest_index)
		_lod_batch_queued.erase(evicted)
		_lod_batch_skipped += 1
	_lod_batch_queue.append(key)
	_lod_batch_queued[key] = true


## Scan the existing desired grid incrementally instead of retaining an
## unbounded "all batches" list. A queue cap can therefore protect a frame
## without permanently abandoning a group that was far away when batching was
## toggled on: future bounded passes revisit it after nearer uploads drain.
func _reset_lod_batch_refill() -> void:
	_lod_batch_rejected.clear()
	_lod_batch_refill_cursor = 0
	_lod_batch_refill_complete = false
	_lod_batch_refill_passes = 0
	_lod_batch_refill_found_work = false


func _refill_lod_batch_queue() -> void:
	if not lod_batching_enabled or _desired.is_empty() or _lod_batch_refill_complete:
		return
	var minimum := _lod_batch_key(_stream_center - Vector2i(render_distance, render_distance))
	var maximum := _lod_batch_key(_stream_center + Vector2i(render_distance, render_distance))
	var width := maximum.x - minimum.x + 1
	var height := maximum.y - minimum.y + 1
	var total := width * height
	if total <= 0:
		return
	for _candidate in MAX_LOD_BATCH_REFILL_CANDIDATES_PER_TICK:
		var index := _lod_batch_refill_cursor
		var key := minimum + Vector2i(index % width, index / width)
		if not _lod_batches.has(key) and not _lod_batch_queued.has(key) and _lod_batch_is_eligible(key):
			_lod_batch_refill_found_work = true
			_queue_lod_batch_for(key * LOD_BATCH_SIZE)
		_lod_batch_refill_cursor = (_lod_batch_refill_cursor + 1) % total
		if _lod_batch_refill_cursor == 0:
			_lod_batch_refill_passes += 1
			_lod_batch_refill_complete = not _lod_batch_refill_found_work
			_lod_batch_refill_found_work = false
			if _lod_batch_refill_complete:
				return


func _lod_batch_is_eligible(key: Vector2i) -> bool:
	if not lod_batching_enabled or _lod_batch_rejected.has(key):
		return false
	for pos in _lod_batch_members(key):
		if not _desired.has(pos) or not _chunk_uses_lod(pos):
			return false
		var chunk: Chunk = _chunks.get(pos)
		if chunk == null or not chunk.lod or chunk.mesh == null or chunk.mesh.mesh == null:
			return false
	return true


## The foreground stream always wins. Compact aggregates are presentation-only:
## if a collision-ring chunk is missing/not ready or a commit still needs the
## scene thread, leave all source meshes visible and service that work first.
func _batching_has_foreground_pressure() -> bool:
	if not _commit_queue.is_empty():
		return true
	for dz in range(-COLLISION_DISTANCE, COLLISION_DISTANCE + 1):
		for dx in range(-COLLISION_DISTANCE, COLLISION_DISTANCE + 1):
			var pos := _stream_center + Vector2i(dx, dz)
			if not _desired.has(pos):
				continue
			var chunk: Chunk = _chunks.get(pos)
			if chunk == null or chunk.lod or not _is_chunk_collision_ready(pos):
				return true
	return false


## ArrayMesh construction is a RenderingServer-facing operation and therefore
## intentionally stays on the scene thread. It does not create worker tasks,
## cannot consume the urgent collision slot, and is capped by the caller.
func _process_lod_batch_queue() -> void:
	if not lod_batching_enabled or lod_distance >= render_distance:
		return
	if _lod_batch_refill_complete and _lod_batch_queue.is_empty():
		return
	if _batching_has_foreground_pressure():
		return
	# `_process_commit_queue()` gets the first share of the streaming frame. The
	# actual ArrayMesh upload below cannot be preempted, so this is a soft guard:
	# do not begin it after commits have already used most of their time budget.
	if _commit_budget_used_usec > COMMIT_BUDGET_MS * 1000 - BATCH_UPLOAD_SOFT_BUDGET_USEC:
		return
	_refill_lod_batch_queue()
	var uploads := 0
	while uploads < MAX_LOD_BATCH_UPLOADS_PER_TICK and not _lod_batch_queue.is_empty():
		var closest_index := 0
		var closest_priority := _lod_batch_priority(_lod_batch_queue[0])
		for index in range(1, _lod_batch_queue.size()):
			var priority := _lod_batch_priority(_lod_batch_queue[index])
			if priority < closest_priority:
				closest_index = index
				closest_priority = priority
		var key: Vector2i = _lod_batch_queue[closest_index]
		_lod_batch_queue.remove_at(closest_index)
		_lod_batch_queued.erase(key)
		if not _lod_batch_is_eligible(key):
			continue
		_build_lod_batch(key)
		uploads += 1


func _build_lod_batch(key: Vector2i) -> void:
	_invalidate_lod_batch(key)
	if not _lod_batch_is_eligible(key):
		return
	var origin_chunks := key * LOD_BATCH_SIZE
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var light := PackedFloat32Array()
	var layers := PackedFloat32Array()
	var indices := PackedInt32Array()
	var members := _lod_batch_members(key)
	var vertex_total := 0
	var index_total := 0
	for pos in members:
		var source_mesh: Mesh = (_chunks[pos] as Chunk).mesh.mesh
		vertex_total += source_mesh.surface_get_array_len(0)
		index_total += source_mesh.surface_get_array_index_len(0)
	if vertex_total > MAX_LOD_BATCH_VERTICES or index_total > MAX_LOD_BATCH_INDICES:
		_lod_batch_geometry_rejected += 1
		_lod_batch_rejected[key] = true
		return
	for pos in members:
		var chunk: Chunk = _chunks[pos]
		var arrays: Array = chunk.mesh.mesh.surface_get_arrays(0)
		if arrays.size() <= Mesh.ARRAY_INDEX:
			return
		var source_vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var source_normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var source_uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		var source_colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		var source_light: PackedFloat32Array = arrays[Mesh.ARRAY_CUSTOM0]
		var source_layers: PackedFloat32Array = arrays[Mesh.ARRAY_CUSTOM1]
		var source_indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		if source_vertices.is_empty() or source_light.is_empty() or source_layers.is_empty():
			return
		var offset := Vector3(float((pos.x - origin_chunks.x) * VoxelDefs.CHUNK_SIZE), 0.0,
			float((pos.y - origin_chunks.y) * VoxelDefs.CHUNK_SIZE))
		var base := vertices.size()
		for vertex in source_vertices:
			vertices.append(vertex + offset)
		normals.append_array(source_normals)
		uvs.append_array(source_uvs)
		colors.append_array(source_colors)
		light.append_array(source_light)
		layers.append_array(source_layers)
		for index in source_indices:
			indices.append(index + base)
	var mesh := ChunkMesher.arrays_to_mesh(vertices, normals, uvs, colors, indices,
		_blocks.material, light, layers)
	if mesh == null:
		return
	var batch := LodRenderBatch.new()
	batch.members = members
	batch.mesh = MeshInstance3D.new()
	batch.mesh.name = "LodBatch_%d_%d" % [key.x, key.y]
	batch.mesh.position = Vector3(origin_chunks.x * VoxelDefs.CHUNK_SIZE, 0.0,
		origin_chunks.y * VoxelDefs.CHUNK_SIZE)
	batch.mesh.mesh = mesh
	add_child(batch.mesh)
	_lod_batches[key] = batch
	for pos in members:
		(_chunks[pos] as Chunk).mesh.visible = false
	_lod_batch_uploads += 1


func _invalidate_lod_batch(key: Vector2i) -> void:
	# A new member mesh may fit even when the previous group was oversized.
	_lod_batch_rejected.erase(key)
	var batch: LodRenderBatch = _lod_batches.get(key)
	if batch == null:
		return
	if batch.mesh != null and is_instance_valid(batch.mesh):
		batch.mesh.visible = false
	for pos in batch.members:
		var chunk: Chunk = _chunks.get(pos)
		if chunk != null and chunk.mesh != null and is_instance_valid(chunk.mesh):
			chunk.mesh.visible = true
	if batch.mesh != null and is_instance_valid(batch.mesh):
		# Hiding above is immediate; deleting the old aggregate is deferred.
		batch.mesh.queue_free()
	_lod_batches.erase(key)


func _clear_lod_batches() -> void:
	for key in _lod_batches.keys():
		_invalidate_lod_batch(key)
	_lod_batch_queue.clear()
	_lod_batch_queued.clear()
	_reset_lod_batch_refill()


func _reconcile_lod_batches() -> void:
	for key in _lod_batches.keys():
		if not _lod_batch_is_eligible(key):
			_invalidate_lod_batch(key)


func _commit_chunk(pos: Vector2i, res: ChunkMesher.MeshResult, lod: bool) -> void:
	# A replacement cannot share an old aggregate: reveal its current authoritative
	# mesh first, then request a fresh group only after this commit has landed.
	_invalidate_lod_batch(_lod_batch_key(pos))
	_generated.erase(pos)
	var chunk: Chunk = _chunks.get(pos)
	var was_streamed := chunk != null and _desired.has(pos) \
		and chunk.lod == _chunk_uses_lod(pos)
	if not was_streamed and _desired.has(pos) and lod == _chunk_uses_lod(pos):
		_streamed_count += 1
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
		_seed_gravity_edits(pos)
	else:
		# A later transition back to Full Detail must retry candidates that were
		# intentionally unavailable while this chunk held compact data.
		_gravity_seeded_chunks.erase(pos)
	chunk.mesh.mesh = ChunkMesher.arrays_to_mesh(res.verts, res.normals, res.uvs, res.colors, res.indices, _blocks.material, res.light, res.layers)
	chunk.water.mesh = ChunkMesher.arrays_to_mesh(res.water_verts, res.water_normals, res.water_uvs, res.water_colors, res.water_indices, _blocks.water_material, res.water_light)
	chunk.mesh.visible = true
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
	if lod:
		_queue_lod_batch_for(pos)


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
		if preserve_if_pending and not low_priority:
			if _mesh_queued.has(pos):
				_work_push(_mesh_queue, _mesh_queued, pos, true)
			else:
				_work_push(_gen_queue, _gen_queued, pos, true)
		return
	_dirty[pos] = true
	var chunk: Chunk = _chunks.get(pos)
	var can_remesh := chunk != null and chunk.lod == _chunk_uses_lod(pos)
	if can_remesh:
		_work_push(_mesh_queue, _mesh_queued, pos, preserve_if_pending and not low_priority)
	else:
		_generated.erase(pos)
		_work_push(_gen_queue, _gen_queued, pos, preserve_if_pending and not low_priority)


func _unload_far() -> void:
	for pos in _chunks.keys():
		if maxi(absi(pos.x - _stream_center.x), absi(pos.y - _stream_center.y)) > unload_radius:
			_free_chunk(pos)
	_discard_unloaded_stream_state()


func _free_chunk(pos: Vector2i) -> void:
	var chunk: Chunk = _chunks.get(pos)
	if chunk == null:
		return
	_invalidate_lod_batch(_lod_batch_key(pos))
	if _desired.has(pos) and chunk.lod == _chunk_uses_lod(pos):
		_streamed_count -= 1
	# queue_free() is deferred. Remove physics immediately so a large render-
	# distance contraction cannot leave one-frame ghost walls from old bodies.
	_remove_chunk_collision_nodes(chunk)
	chunk.mesh.queue_free()
	chunk.water.queue_free()
	_chunks.erase(pos)
	_gravity_seeded_chunks.erase(pos)
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


func is_threatened(world_position: Vector3, radius: float = 8.0) -> bool:
	return threat_check.is_valid() and bool(threat_check.call(world_position, radius))


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
	if BlockRegistry.is_door(block_id):
		var lower_position := block_position - Vector3i.UP if BlockRegistry.door_upper(block_id) else block_position
		_remove_door_part(lower_position)
		_remove_door_part(lower_position + Vector3i.UP)
		return BlockRegistry.BLOCK_WOOD_DOOR
	chunk.data[index] = BlockRegistry.BLOCK_AIR
	_record_edit(block_position, BlockRegistry.BLOCK_AIR)
	_touch_chunk(chunk_position, block_position, block_id, BlockRegistry.BLOCK_AIR)
	_seed_water(block_position)
	_seed_gravity(block_position)
	return BlockRegistry.canonical_id(block_id)


func place_block(block_position: Vector3i, block_id: int, facing: int = BlockRegistry.FACING_NORTH,
		placement_normal: Vector3i = Vector3i.UP) -> bool:
	if not _blocks.is_valid_id(block_id):
		return false
	var canonical := BlockRegistry.canonical_id(block_id)
	var placed_id := BlockRegistry.placement_variant(canonical, facing, placement_normal)
	if canonical == BlockRegistry.BLOCK_WOOD_DOOR:
		return _place_door(block_position, placed_id)
	if canonical == BlockRegistry.BLOCK_WOOD_LADDER:
		if placement_normal.y != 0 or placement_normal == Vector3i.ZERO:
			return false
		var support := get_block_world(block_position - placement_normal)
		if support == BlockRegistry.BLOCK_AIR or _blocks.is_water_id(support) \
				or _blocks.has_flag(support, BlockRegistry.FLAG_CROSS):
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
	chunk.data[index] = placed_id
	_record_edit(block_position, placed_id)
	_touch_chunk(chunk_position, block_position, existing, placed_id)
	_seed_water(block_position)
	_seed_gravity(block_position)
	return true


func _place_door(lower_position: Vector3i, lower_id: int) -> bool:
	var upper_position := lower_position + Vector3i.UP
	if lower_position.y < 0 or upper_position.y >= VoxelDefs.WORLD_HEIGHT:
		return false
	for position in [lower_position, upper_position]:
		var loaded := _loaded_chunk_for(position)
		if loaded == null or loaded.lod:
			return false
		var existing := get_block_world(position)
		if existing != BlockRegistry.BLOCK_AIR and not _blocks.is_water_id(existing):
			return false
	_set_placed_block(lower_position, lower_id)
	_set_placed_block(upper_position, BlockRegistry.door_with_upper(lower_id, true))
	return true


func _set_placed_block(position: Vector3i, block_id: int) -> void:
	var chunk_position := _chunk_for_block(position)
	var chunk: Chunk = _chunks[chunk_position]
	_restore_chunk_data(chunk)
	var index := _data_index(position)
	var existing: int = chunk.data[index]
	chunk.data[index] = block_id
	_record_edit(position, block_id)
	_touch_chunk(chunk_position, position, existing, block_id)
	_seed_water(position)
	_seed_gravity(position)


func _remove_door_part(position: Vector3i) -> void:
	var chunk := _loaded_chunk_for(position)
	if chunk == null or chunk.lod:
		return
	_restore_chunk_data(chunk)
	var index := _data_index(position)
	var existing: int = chunk.data[index]
	if not BlockRegistry.is_door(existing):
		return
	chunk.data[index] = BlockRegistry.BLOCK_AIR
	_record_edit(position, BlockRegistry.BLOCK_AIR)
	_touch_chunk(_chunk_for_block(position), position, existing, BlockRegistry.BLOCK_AIR)
	_seed_water(position)
	_seed_gravity(position)


## Opens or closes both persisted halves together. Interaction is valid from
## either half and survives chunk boundaries because each voxel is an edit.
func toggle_door(block_position: Vector3i) -> bool:
	var clicked := get_block_world(block_position)
	if not BlockRegistry.is_door(clicked):
		return false
	var lower_position := block_position - Vector3i.UP if BlockRegistry.door_upper(clicked) else block_position
	var upper_position := lower_position + Vector3i.UP
	var lower := get_block_world(lower_position)
	var upper := get_block_world(upper_position)
	if not BlockRegistry.is_door(lower) or not BlockRegistry.is_door(upper):
		return false
	var opened := not BlockRegistry.door_open(lower)
	_set_existing_block(lower_position, BlockRegistry.door_with_open(lower, opened))
	_set_existing_block(upper_position, BlockRegistry.door_with_open(upper, opened))
	return true


func _set_existing_block(position: Vector3i, block_id: int) -> void:
	var chunk := _loaded_chunk_for(position)
	if chunk == null or chunk.lod:
		return
	_restore_chunk_data(chunk)
	var index := _data_index(position)
	var previous: int = chunk.data[index]
	chunk.data[index] = block_id
	_record_edit(position, block_id)
	_touch_chunk(_chunk_for_block(position), position, previous, block_id)


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
	var door_counterparts: Dictionary = {}
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
				if BlockRegistry.is_door(block_id):
					var counterpart := position + (Vector3i.DOWN if BlockRegistry.door_upper(block_id) else Vector3i.UP)
					door_counterparts[counterpart] = true
				chunk.data[index] = BlockRegistry.BLOCK_AIR
				_record_edit_in_chunk(position, BlockRegistry.BLOCK_AIR, chunk_position)
				_seed_gravity(position)
				removed += 1
				column_changed = true
				var dy := y - center.y
				if horizontal_squared + dy * dy >= shell_inner_squared:
					water_shell.append(position)
			if column_changed:
				changed_chunks[chunk_position] = true
	for position: Vector3i in door_counterparts:
		removed += _remove_door_for_batch(position, changed_chunks)
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
	_seed_gravity(position)
	changed_chunks[_chunk_for_block(position)] = true


## Final state of a burnt block: it crumbles to ash and disappears. This is the
## only voxel change in the burning lifecycle, so it is the one persisted. Like
## `break_block()`/`carve_sphere()`, the new air lets adjacent water flow in.
func _destroy_burnt_block(position: Vector3i, changed_chunks: Dictionary) -> void:
	if BlockRegistry.is_door(get_block_world(position)):
		var lower := position - Vector3i.UP if BlockRegistry.door_upper(get_block_world(position)) else position
		_remove_door_for_batch(lower, changed_chunks)
		_remove_door_for_batch(lower + Vector3i.UP, changed_chunks)
		return
	var chunk := _loaded_chunk_for(position)
	if chunk == null or chunk.lod:
		return
	_restore_chunk_data(chunk)
	chunk.data[_data_index(position)] = BlockRegistry.BLOCK_AIR
	_record_edit(position, BlockRegistry.BLOCK_AIR)
	_seed_water(position)
	_seed_gravity(position)
	changed_chunks[_chunk_for_block(position)] = true


func _remove_door_for_batch(position: Vector3i, changed_chunks: Dictionary) -> int:
	var chunk := _loaded_chunk_for(position)
	if chunk == null or chunk.lod:
		return 0
	_restore_chunk_data(chunk)
	var index := _data_index(position)
	if not BlockRegistry.is_door(chunk.data[index]):
		return 0
	chunk.data[index] = BlockRegistry.BLOCK_AIR
	_record_edit(position, BlockRegistry.BLOCK_AIR)
	_seed_water(position)
	_seed_gravity(position)
	changed_chunks[_chunk_for_block(position)] = true
	return 1


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


## A block update can either place a gravity block or remove/change its support.
## Queue both the changed cell and the cell directly above it; that upper cell is
## the only one in the column whose support can have changed.
func _seed_gravity(block_position: Vector3i) -> void:
	_queue_gravity(block_position)
	_queue_gravity(block_position + Vector3i.UP)


## Rehydrated edits store final voxel states rather than transient queue state.
## Rechecking every edited cell and its upper neighbour resumes interrupted
## falls after reload without depending on dictionary or chunk load order.
func _seed_gravity_edits(pos: Vector2i) -> void:
	if _gravity_seeded_chunks.has(pos):
		return
	_gravity_seeded_chunks[pos] = true
	var bucket: Dictionary = _edits_by_chunk.get(pos, {})
	var positions: Array[Vector3i] = []
	for key in bucket:
		positions.append(key)
	positions.sort_custom(func(a: Vector3i, b: Vector3i) -> bool:
		if a.y != b.y:
			return a.y < b.y
		if a.z != b.z:
			return a.z < b.z
		return a.x < b.x
	)
	for position in positions:
		_seed_gravity(position)


func _queue_gravity(position: Vector3i) -> void:
	if position.y <= 0 or position.y >= VoxelDefs.WORLD_HEIGHT:
		return
	if _gravity_queued.has(position):
		return
	var chunk := _loaded_chunk_for(position)
	if chunk == null or chunk.lod:
		return
	_restore_chunk_data(chunk)
	if not _blocks.is_gravity_block(chunk.data[_data_index(position)]):
		return
	_gravity_queued[position] = true
	_gravity_queue.append(position)


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
	_seed_gravity(position)
	changed_chunks[_chunk_for_block(position)] = true
	for offset in WATER_NEIGHBOR_OFFSETS:
		_queue_water(position + offset)


## Settles sand, red sand, and gravel after nearby persistent edits. A block
## advances one cell per tick; every moved source and destination is recorded
## before persistence/versioning is batched for the affected chunk ring.
func _gravity_tick() -> void:
	var budget := GRAVITY_CELLS_PER_TICK
	var changed_chunks: Dictionary = {}
	# Snapshot the tail: cells woken by a move wait for the next simulation step.
	# Besides making the fall rate stable, this prevents one tall column from
	# consuming the whole per-frame budget by repeatedly re-queuing itself.
	var tick_end := _gravity_queue.size()
	while budget > 0 and _gravity_head < tick_end:
		var position: Vector3i = _gravity_queue[_gravity_head]
		_gravity_head += 1
		budget -= 1
		_gravity_queued.erase(position)
		_update_gravity_cell(position, changed_chunks)
	_flush_gravity_changes(changed_chunks)
	if _gravity_head == _gravity_queue.size():
		_gravity_queue.clear()
		_gravity_head = 0
	elif _gravity_head > 4096:
		_gravity_queue = _gravity_queue.slice(_gravity_head)
		_gravity_head = 0


func _update_gravity_cell(position: Vector3i, changed_chunks: Dictionary) -> void:
	if position.y <= 1:
		return
	var chunk := _loaded_chunk_for(position)
	if chunk == null or chunk.lod:
		return
	_restore_chunk_data(chunk)
	var source_index := _data_index(position)
	var block_id: int = chunk.data[source_index]
	if not _blocks.is_gravity_block(block_id):
		return
	var destination := position + Vector3i.DOWN
	# Falling is vertical, so this is currently the same x/z chunk. Keep the
	# resident check explicit so a future lateral reaction cannot treat unknown
	# unloaded or compact LOD data as empty space.
	var destination_chunk := _loaded_chunk_for(destination)
	if destination_chunk == null or destination_chunk.lod:
		return
	_restore_chunk_data(destination_chunk)
	var destination_index := _data_index(destination)
	var destination_id: int = destination_chunk.data[destination_index]
	if not _is_gravity_passable(destination_id):
		return
	chunk.data[source_index] = BlockRegistry.BLOCK_AIR
	destination_chunk.data[destination_index] = block_id
	_record_edit(position, BlockRegistry.BLOCK_AIR)
	_record_edit(destination, block_id)
	changed_chunks[_chunk_for_block(position)] = true
	changed_chunks[_chunk_for_block(destination)] = true
	_seed_water(position)
	_seed_water(destination)
	_queue_gravity(destination)
	_queue_gravity(position + Vector3i.UP)


func _is_gravity_passable(block_id: int) -> bool:
	# Cross blocks have inventory value and VoxelWorld has no drop owner. Treat
	# them as support rather than silently replacing them during simulation.
	return block_id == BlockRegistry.BLOCK_AIR or _blocks.is_water_id(block_id)


func _flush_gravity_changes(changed_chunks: Dictionary) -> void:
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
	# Neighbor light/seam updates remain required, but the edited owner gets
	# explicit feedback priority instead of waiting behind their heavy remeshes.
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


## Beds need a same-floor search rather than the surface spawn scanner above.
## A roof is often the topmost opaque block in an indoor column, so using
## find_safe_spawn() would incorrectly move the saved respawn onto the roof.
func find_bed_spawn(bed_position: Vector3i, radius: int = 3) -> Dictionary:
	var safe_radius := clampi(radius, 1, 8)
	for ring in range(1, safe_radius + 1):
		for dx in range(-ring, ring + 1):
			for dz in range(-ring, ring + 1):
				if maxi(absi(dx), absi(dz)) != ring:
					continue
				var feet_cell := bed_position + Vector3i(dx, 0, dz)
				if not _is_standable_cell(feet_cell):
					continue
				return {"found": true, "position": Vector3(feet_cell) + Vector3(0.5, 0.5, 0.5)}
	return {"found": false}


## Tests whether a previously validated spawn is still safe. Bed respawns use
## this before falling back to the surface-oriented find_safe_spawn().
func is_standable_spawn(world_position: Vector3) -> bool:
	if not world_position.is_finite():
		return false
	return _is_standable_cell(Vector3i(
		floori(world_position.x), floori(world_position.y), floori(world_position.z)))


func _is_standable_cell(feet_cell: Vector3i) -> bool:
	if get_block_world(feet_cell) != BlockRegistry.BLOCK_AIR \
			or get_block_world(feet_cell + Vector3i.UP) != BlockRegistry.BLOCK_AIR:
		return false
	var below := get_block_world(feet_cell + Vector3i.DOWN)
	return below != BlockRegistry.BLOCK_AIR and not _blocks.is_water_id(below) \
		and not _blocks.has_flag(below, BlockRegistry.FLAG_CROSS)


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
	var stream := get_streaming_progress()
	return {
		"chunks": "%d full / %d lod" % [full_chunks, lod_chunks],
		"streamed": int(stream["loaded"]),
		"stream total": int(stream["total"]),
		"pending": _pending.size(),
		"queued": _gen_queue.size() + _mesh_queue.size(),
		"generated waiting": _generated.size(),
		"commits": _commit_queue.size(),
		"gen ms ema": _generation_ema_ms,
		"terrain ms": _terrain_ema_ms,
		"populate ms": _populate_ema_ms,
		"mesh ms ema": _mesh_ema_ms,
		"revision": _worldgen_revision,
		"workers": "%d / %d (+1 urgent)" % [_pending.size(), _max_active_jobs],
		"generation jobs": _generation_jobs,
		"mesh jobs": _mesh_jobs,
		"discarded jobs": _discarded_jobs,
		"generation worker ms total": float(_generation_usec) / 1000.0,
		"mesh worker ms total": float(_mesh_usec) / 1000.0,
		"commit ms total": float(_commit_usec) / 1000.0,
		"stream main ms total": float(_stream_main_usec) / 1000.0,
		"lod render batches": _lod_batches.size(),
		"lod batch queued": _lod_batch_queue.size(),
		"lod batch uploads": _lod_batch_uploads,
		"lod batch skipped": _lod_batch_skipped,
		"lod batch geometry rejected": _lod_batch_geometry_rejected,
	}


## Render-only diagnostic for the headless structural verifier and the display
## profiler. A compact source is counted once: either hidden under exactly one
## valid batch or visible as its own mesh. Water is intentionally not counted
## as batched because it remains an individual transparent surface.
func get_lod_batch_stats() -> Dictionary:
	var batched_members: Dictionary = {}
	var visible_members := 0
	var invalid_batches := 0
	for key in _lod_batches:
		var batch: LodRenderBatch = _lod_batches[key]
		if batch == null or batch.members.size() != LOD_BATCH_SIZE * LOD_BATCH_SIZE \
				or batch.mesh == null or not is_instance_valid(batch.mesh):
			invalid_batches += 1
			continue
		for pos in batch.members:
			batched_members[pos] = int(batched_members.get(pos, 0)) + 1
	for pos in _chunks:
		var chunk: Chunk = _chunks[pos]
		if not chunk.lod:
			continue
		if chunk.mesh != null and chunk.mesh.visible:
			visible_members += 1
	var duplicate_members := 0
	for count in batched_members.values():
		if int(count) > 1:
			duplicate_members += 1
	return {
		"enabled": lod_batching_enabled,
		"batches": _lod_batches.size(),
		"batched members": batched_members.size(),
		"visible lod members": visible_members,
		"duplicate members": duplicate_members,
		"invalid batches": invalid_batches,
		"queued": _lod_batch_queue.size(),
		"uploads": _lod_batch_uploads,
		"skipped": _lod_batch_skipped,
		"geometry rejected": _lod_batch_geometry_rejected,
		"refill complete": _lod_batch_refill_complete,
		"refill passes": _lod_batch_refill_passes,
	}


## A cheap scene-thread snapshot used by the entry overlay and compact HUD
## feedback. `loaded` counts only chunks that match the current detail mode, so
## a Full/LOD transition never reports stale terrain as finished streaming.
func get_streaming_progress() -> Dictionary:
	var loaded := _streamed_count
	var total := _desired.size()
	var spawn_loaded := 0
	var spawn_collision := 0
	var spawn_center := _initial_stream_center if _initial_stream_active else _stream_center
	if spawn_center.x == 999999:
		spawn_center = Vector2i.ZERO
	for dz in range(-SPAWN_RADIUS, SPAWN_RADIUS + 1):
		for dx in range(-SPAWN_RADIUS, SPAWN_RADIUS + 1):
			var pos := spawn_center + Vector2i(dx, dz)
			var chunk: Chunk = _chunks.get(pos)
			if chunk != null and not chunk.lod:
				spawn_loaded += 1
				if _is_chunk_collision_ready(pos):
					spawn_collision += 1
	return {
		"loaded": loaded,
		"total": total,
		"pending": _pending.size(),
		"queued": _gen_queue.size() + _mesh_queue.size(),
		"generated": _generated.size(),
		"commits": _commit_queue.size(),
		"spawn_loaded": spawn_loaded,
		"spawn_collision": spawn_collision,
		"spawn_total": (SPAWN_RADIUS * 2 + 1) * (SPAWN_RADIUS * 2 + 1),
		"initial_ready": _initial_stream_complete,
		"streaming": total > 0 and loaded < total,
	}


func _emit_stream_progress() -> void:
	stream_progress_changed.emit(get_streaming_progress())


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
