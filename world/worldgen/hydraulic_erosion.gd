## Optional deterministic local hydraulic erosion.
##
## Each globally aligned 64x64 authoritative tile is solved from a 24-cell halo.
## The halo exceeds a droplet's fixed 20-cell lifetime, so no simulated rainfall
## outside the solve can reach an authoritative cell. The result is faded to zero
## at every authoritative edge. Adjacent tiles consequently share a zero modifier
## at their boundary while RegionalErosion supplies the continuous base terrain.
## This is deliberately a bounded local solve, not a TerraForged-compatible model.
class_name HydraulicErosion
extends RefCounted

const TILE_SIZE: int = 64
const MAX_DROPLET_STEPS: int = 20
const HALO: int = MAX_DROPLET_STEPS + 4
const SIM_SIDE: int = TILE_SIZE + HALO * 2
const DROPLET_SPACING: int = 4
const EDGE_FADE: float = 8.0
# 32 x 64 x 64 float deltas = 512 KiB, excluding small Dictionary overhead.
const MAX_CACHE_TILES: int = 32
const RAIN_SALT: int = 29573


class CachedTile:
	var delta: PackedFloat32Array
	var last_use: int

	func _init(p_delta: PackedFloat32Array, p_last_use: int) -> void:
		delta = p_delta
		last_use = p_last_use


var _seed: int = 0
var _strength: float = 0.0
var _cache_prefix: String = ""
var _configured: bool = false

# TerrainSampler is shared by worker jobs. Cache access, insertion, touch, and
# eviction all happen while this mutex is held. Misses are solved outside the lock;
# a racing duplicate solve is discarded, and pure fixed-order simulation gives both
# jobs the same answer regardless of which one populates the cache first.
var _cache_mutex := Mutex.new()
var _cache: Dictionary = {}
var _cache_tick: int = 0


func _init(config: WorldGenConfig = null) -> void:
	if config != null:
		configure(config)


## Configure before worker use only. regional_erosion is intentionally the sole
## erosion amount: enabling this phase adds detail without creating another knob.
func configure(config: WorldGenConfig) -> void:
	if _configured:
		push_warning("HydraulicErosion is immutable after initialization")
		return
	_seed = config.seed
	_strength = config.regional_erosion
	_cache_prefix = _make_cache_prefix(config)
	_configured = true


## Returns this coordinate's hydraulic delta. height_at must be a pure global-
## coordinate analytic source; TerrainSampler layers RegionalErosion underneath
## this delta after the solve.
func modifier(x: int, z: int, height_at: Callable) -> float:
	if _strength <= 0.0 or not height_at.is_valid():
		return 0.0
	var tile_x: int = WorldGenHash.floor_div(x, TILE_SIZE)
	var tile_z: int = WorldGenHash.floor_div(z, TILE_SIZE)
	var local_x: int = WorldGenHash.floor_mod(x, TILE_SIZE)
	var local_z: int = WorldGenHash.floor_mod(z, TILE_SIZE)
	var key: String = "%s|%d|%d" % [_cache_prefix, tile_x, tile_z]

	_cache_mutex.lock()
	_cache_tick += 1
	var cached: CachedTile = _cache.get(key) as CachedTile
	if cached != null:
		cached.last_use = _cache_tick
		var cached_result: float = cached.delta[local_x + local_z * TILE_SIZE]
		_cache_mutex.unlock()
		return cached_result
	_cache_mutex.unlock()

	# The input callback is pure and the tile's droplets are traversed in a fixed
	# global order, making every independent recomputation byte-for-byte identical.
	var solved := _solve_tile(tile_x, tile_z, height_at)
	_cache_mutex.lock()
	_cache_tick += 1
	cached = _cache.get(key) as CachedTile
	if cached == null:
		cached = CachedTile.new(solved, _cache_tick)
		_cache[key] = cached
		_evict_if_needed()
	else:
		cached.last_use = _cache_tick
	var result: float = cached.delta[local_x + local_z * TILE_SIZE]
	_cache_mutex.unlock()
	return result


func _solve_tile(tile_x: int, tile_z: int, height_at: Callable) -> PackedFloat32Array:
	var tile_origin_x: int = tile_x * TILE_SIZE
	var tile_origin_z: int = tile_z * TILE_SIZE
	var sim_origin_x: int = tile_origin_x - HALO
	var sim_origin_z: int = tile_origin_z - HALO
	var base := PackedFloat32Array()
	var height := PackedFloat32Array()
	base.resize(SIM_SIDE * SIM_SIDE)
	height.resize(SIM_SIDE * SIM_SIDE)
	for local_z in SIM_SIDE:
		var world_z: int = sim_origin_z + local_z
		var row: int = local_z * SIM_SIDE
		for local_x in SIM_SIDE:
			var value: float = float(height_at.call(sim_origin_x + local_x, world_z))
			base[row + local_x] = value
			height[row + local_x] = value

	# Global lattice alignment makes the rainfall set for a coordinate independent
	# of its tile and of the order chunks happen to request their tiles.
	var first_x: int = WorldGenHash.floor_div(sim_origin_x, DROPLET_SPACING) * DROPLET_SPACING
	var first_z: int = WorldGenHash.floor_div(sim_origin_z, DROPLET_SPACING) * DROPLET_SPACING
	for world_z in range(first_z, sim_origin_z + SIM_SIDE, DROPLET_SPACING):
		for world_x in range(first_x, sim_origin_x + SIM_SIDE, DROPLET_SPACING):
			if world_x < sim_origin_x or world_z < sim_origin_z:
				continue
			_simulate_droplet(world_x - sim_origin_x, world_z - sim_origin_z, height,
				0.35 + WorldGenHash.float_01_2d(_seed + RAIN_SALT, world_x, world_z) * 0.65)

	var result := PackedFloat32Array()
	result.resize(TILE_SIZE * TILE_SIZE)
	for local_z in TILE_SIZE:
		var sim_row: int = (local_z + HALO) * SIM_SIDE + HALO
		for local_x in TILE_SIZE:
			var edge_distance: float = float(mini(mini(local_x, TILE_SIZE - 1 - local_x), mini(local_z, TILE_SIZE - 1 - local_z)))
			var fade: float = _smoothstep(0.0, EDGE_FADE, edge_distance)
			result[local_x + local_z * TILE_SIZE] = (height[sim_row + local_x] - base[sim_row + local_x]) * fade * _strength
	return result


## One droplet carries sediment across a fixed, bounded number of cardinal
## downslope cells. It erodes when below carrying capacity and deposits when it
## loses capacity or settles; no RNG state or iteration-order-dependent source is used.
func _simulate_droplet(start_x: int, start_z: int, height: PackedFloat32Array, rainfall: float) -> void:
	var cell_x: int = start_x
	var cell_z: int = start_z
	var water: float = rainfall
	var sediment: float = 0.0
	for unused_step in MAX_DROPLET_STEPS:
		var index: int = cell_x + cell_z * SIM_SIDE
		var current: float = height[index]
		var next_x: int = cell_x
		var next_z: int = cell_z
		var lowest: float = current
		# Fixed west/east/north/south tie order keeps plateaus reproducible.
		if cell_x > 0 and height[index - 1] < lowest:
			lowest = height[index - 1]
			next_x -= 1
		if cell_x < SIM_SIDE - 1 and height[index + 1] < lowest:
			lowest = height[index + 1]
			next_x = cell_x + 1
		if cell_z > 0 and height[index - SIM_SIDE] < lowest:
			lowest = height[index - SIM_SIDE]
			next_x = cell_x
			next_z = cell_z - 1
		if cell_z < SIM_SIDE - 1 and height[index + SIM_SIDE] < lowest:
			lowest = height[index + SIM_SIDE]
			next_x = cell_x
			next_z = cell_z + 1
		var drop: float = current - lowest
		if drop <= 0.0001:
			height[index] += sediment
			return
		var capacity: float = maxf(drop * water * 0.32, 0.012)
		if sediment > capacity:
			var deposit: float = (sediment - capacity) * 0.38
			height[index] += deposit
			sediment -= deposit
		else:
			var erode: float = minf((capacity - sediment) * 0.24, 0.075)
			height[index] -= erode
			sediment += erode
		cell_x = next_x
		cell_z = next_z
		water *= 0.94
	height[cell_x + cell_z * SIM_SIDE] += sediment


func _evict_if_needed() -> void:
	if _cache.size() <= MAX_CACHE_TILES:
		return
	var oldest_key: String = ""
	var oldest_use: int = 2147483647
	for key_variant in _cache:
		var key: String = String(key_variant)
		var entry: CachedTile = _cache[key] as CachedTile
		if entry.last_use < oldest_use or (entry.last_use == oldest_use and key < oldest_key):
			oldest_key = key
			oldest_use = entry.last_use
	_cache.erase(oldest_key)


func _make_cache_prefix(config: WorldGenConfig) -> String:
	# Include every validated config value. Cache residency can vary with job order,
	# but this key and the pure tile solve guarantee the returned terrain cannot.
	return "%d|%d|%.9f|%.9f|%d|%.9f|%.9f|%.9f|%.9f|%s|%.9f|%.9f" % [
		config.seed, config.world_type, config.terrain_scale, config.tree_density,
		config.worldgen_version, config.macro_scale, config.river_density,
		config.erosion_strength, config.regional_erosion, str(config.hydraulic_erosion),
		config.cave_density, config.decoration_density,
	]


func _smoothstep(edge0: float, edge1: float, value: float) -> float:
	var t: float = clampf((value - edge0) / (edge1 - edge0), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)
