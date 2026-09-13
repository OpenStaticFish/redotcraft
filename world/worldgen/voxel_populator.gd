## Converts a padded terrain field into deterministic voxel data.
## All work is value-only and safe to run from a chunk worker thread.
class_name VoxelPopulator
extends RefCounted

const ChunkTerrainDataScript = preload("res://world/worldgen/chunk_terrain_data.gd")
const WorldGenConfigScript = preload("res://world/worldgen/world_gen_config.gd")
const BiomeCatalogScript = preload("res://world/worldgen/biome_catalog.gd")
const WorldGenHashScript = preload("res://world/worldgen/world_gen_hash.gd")
const DecorationCatalogScript = preload("res://world/worldgen/decoration_catalog.gd")
const BlockRegistryScript = preload("res://world/block_registry.gd")
const VoxelDefsScript = preload("res://world/voxel_defs.gd")

const SURFACE_CLEARANCE: int = 3
const FEATURE_CELL_SIZE: int = 8
const FEATURE_HALO: int = 6
# Grove candidates are six blocks apart and have a maximum horizontal tree
# footprint of three blocks (jungle/spruce). The three-block halo makes every
# touched chunk evaluate the same global candidate; FEATURE_HALO remains the
# wider bound for legacy feature stamps.
const TREE_CELL_SIZE: int = 6
const TREE_FOOTPRINT_RADIUS: int = 3
const TREE_GROVE_CELL_SIZE: int = 48
const TREE_GROVE_SEARCH_RADIUS: int = 1
const GROUND_COVER_CELL_SIZE: int = 10
const GROUND_COVER_RADIUS: int = 4
const CAVE_CELL_SIZE: int = 24
const ORE_CELL_SIZE: int = 20

var config: WorldGenConfig
var biomes: BiomeCatalog
var decorations: DecorationCatalog
var terrain_sampler: TerrainSampler


func _init(config_value: WorldGenConfig, biomes_value: BiomeCatalog, sampler_value: TerrainSampler = null) -> void:
	config = config_value if config_value != null else WorldGenConfigScript.new()
	biomes = biomes_value if biomes_value != null else BiomeCatalogScript.new()
	terrain_sampler = sampler_value
	decorations = DecorationCatalogScript.new()


## Returns {"data": PackedByteArray, "max_y": int}. Edits deliberately run
## after every generated stage so a saved player block is always authoritative.
func populate(chunk_pos: Vector2i, field: ChunkTerrainData, edits: Dictionary, full_detail: bool = true) -> Dictionary:
	var data := PackedByteArray()
	data.resize(VoxelDefsScript.CHUNK_AREA * VoxelDefsScript.WORLD_HEIGHT)
	var origin_x: int = chunk_pos.x * VoxelDefsScript.CHUNK_SIZE
	var origin_z: int = chunk_pos.y * VoxelDefsScript.CHUNK_SIZE
	var max_y := _fill_base_and_surface(data, field)
	if full_detail and config.world_type != WorldGenConfigScript.WORLD_TYPE_FLAT and config.cave_density > 0.0:
		_carve_worm_caves(data, field, origin_x, origin_z)
		_carve_cave_entrances(data, field, origin_x, origin_z)
		_carve_caverns(data, field, origin_x, origin_z)
		_fill_underground_liquids(data, field, origin_x, origin_z)
		_place_ore_veins(data, origin_x, origin_z)
		_decorate_caves(data, origin_x, origin_z)
	if full_detail and config.decoration_density > 0.0:
		max_y = _decorate(data, field, origin_x, origin_z, max_y)
	max_y = _apply_edits(data, edits, origin_x, origin_z, max_y)
	return {"data": data, "max_y": _actual_max_y(data, max_y)}


## Compact LOD population: the distance mesh only needs each column's top/sub
## block and water surface, so no 192-block data array is allocated and caves,
## ores, and decorations are skipped. Far chunks cost kilobytes instead of
## ~50 KB and stream several times faster. Player edits are intentionally
## ignored here: LOD chunks are beyond interaction range and become full detail
## before the player can reach them.
func populate_lod(chunk_pos: Vector2i, field: ChunkTerrainData) -> Dictionary:
	var solid_y := PackedInt32Array()
	var solid_id := PackedByteArray()
	var sub_id := PackedByteArray()
	var water_y := PackedInt32Array()
	var water_level := PackedByteArray()
	solid_y.resize(VoxelDefsScript.CHUNK_AREA)
	solid_id.resize(VoxelDefsScript.CHUNK_AREA)
	sub_id.resize(VoxelDefsScript.CHUNK_AREA)
	water_y.resize(VoxelDefsScript.CHUNK_AREA)
	water_level.resize(VoxelDefsScript.CHUNK_AREA)
	solid_y.fill(-1)
	water_y.fill(-1)
	var max_y := 0
	for local_z in VoxelDefsScript.CHUNK_SIZE:
		for local_x in VoxelDefsScript.CHUNK_SIZE:
			var field_index: int = ChunkTerrainDataScript.cell_index(local_x, local_z)
			var column: int = local_x + local_z * VoxelDefsScript.DATA_STRIDE_Z
			var surface_y: int = _surface_height(field, field_index)
			var river: float = field.river[field_index]
			var is_river: bool = config.world_type != WorldGenConfigScript.WORLD_TYPE_FLAT \
				and river >= 0.62 and surface_y < VoxelDefsScript.SEA_LEVEL
			var column_water_y := -1
			if surface_y < VoxelDefsScript.SEA_LEVEL:
				column_water_y = VoxelDefsScript.SEA_LEVEL
			var values := _surface_rule_values(field, field_index, surface_y, column_water_y, is_river,
				field.world_x(local_x), field.world_z(local_z))
			solid_y[column] = surface_y
			solid_id[column] = values.x
			sub_id[column] = values.y
			if column_water_y >= 0:
				water_y[column] = column_water_y
				water_level[column] = 8
				max_y = maxi(max_y, column_water_y)
			else:
				max_y = maxi(max_y, surface_y)
	return {
		"solid_y": solid_y,
		"solid_id": solid_id,
		"sub_id": sub_id,
		"water_y": water_y,
		"water_level": water_level,
		"max_y": max_y,
	}


func _fill_base_and_surface(data: PackedByteArray, field: ChunkTerrainData) -> int:
	var max_y := 0
	for local_z in VoxelDefsScript.CHUNK_SIZE:
		for local_x in VoxelDefsScript.CHUNK_SIZE:
			var field_index: int = ChunkTerrainDataScript.cell_index(local_x, local_z)
			var surface_y: int = _surface_height(field, field_index)
			var river: float = field.river[field_index]
			var is_river: bool = config.world_type != WorldGenConfigScript.WORLD_TYPE_FLAT \
				and river >= 0.62 and surface_y < VoxelDefsScript.SEA_LEVEL
			var water_y := -1
			if surface_y < VoxelDefsScript.SEA_LEVEL:
				water_y = VoxelDefsScript.SEA_LEVEL
			for y in range(surface_y + 1):
				var block_id := BlockRegistryScript.BLOCK_STONE
				if y == 0:
					block_id = BlockRegistryScript.BLOCK_BEDROCK
				data[_index(local_x, y, local_z)] = block_id
			_apply_surface_rule(data, field, local_x, local_z, surface_y, water_y, is_river)
			if water_y >= 0:
				for y in range(surface_y + 1, water_y + 1):
					data[_index(local_x, y, local_z)] = BlockRegistryScript.BLOCK_WATER
				max_y = maxi(max_y, water_y)
			else:
				max_y = maxi(max_y, surface_y)
	return max_y


func _apply_surface_rule(data: PackedByteArray, field: ChunkTerrainData, local_x: int, local_z: int, surface_y: int, water_y: int, is_river: bool) -> void:
	var field_index: int = ChunkTerrainDataScript.cell_index(local_x, local_z)
	var world_x := field.world_x(local_x)
	var world_z := field.world_z(local_z)
	var values := _surface_rule_values(field, field_index, surface_y, water_y, is_river, world_x, world_z)
	var biome: int = int(field.biome_id[field_index])
	var top: int = values.x
	var sub: int = values.y
	var depth: int = values.z
	if biome == BiomeCatalogScript.BADLANDS:
		# Horizontal terracotta/red-sand bands keep cliffs recognisable after erosion.
		for y in range(maxi(1, surface_y - depth + 1), surface_y + 1):
			data[_index(local_x, y, local_z)] = _badlands_stratum(world_x, y, world_z)
		return
	for y in range(maxi(1, surface_y - depth + 1), surface_y + 1):
		data[_index(local_x, y, local_z)] = top if y == surface_y else sub


## Surface blankets must be coherent. Per-column biome dithering is useful for
## vegetation variety, but creates checkerboards of snow/sand/grass. Shared by
## the full fill and the compact LOD path so both place identical blocks.
func _surface_rule_values(field: ChunkTerrainData, field_index: int, surface_y: int, water_y: int, is_river: bool, world_x: int, world_z: int) -> Vector3i:
	var biome: int = int(field.biome_id[field_index])
	var slope: float = field.slope[field_index]
	var top: int = biomes.surface_block(biome)
	var sub: int = biomes.subsurface_block(biome)
	var depth: int = biomes.soil_depth(biome)
	var underwater: bool = water_y >= 0
	var beach: bool = underwater or (not is_river and abs(surface_y - VoxelDefsScript.SEA_LEVEL) <= 1)
	var snow_band: bool = biome == BiomeCatalogScript.SNOW or (surface_y >= 104 and field.temperature[field_index] < 0.25)
	var cliff: bool = slope >= 4.0 and surface_y > VoxelDefsScript.SEA_LEVEL + 3
	if underwater:
		var water_depth: int = water_y - surface_y
		top = biomes.seabed_block(biome, water_depth)
		sub = top
		depth = biomes.seabed_depth(water_depth)
	elif beach:
		top = BlockRegistryScript.BLOCK_SAND
		sub = BlockRegistryScript.BLOCK_SAND
		depth = 3
	elif cliff:
		top = BlockRegistryScript.BLOCK_STONE
		sub = BlockRegistryScript.BLOCK_STONE
		depth = 2
	elif snow_band:
		top = BlockRegistryScript.BLOCK_SNOW
		if surface_y >= 104:
			sub = BlockRegistryScript.BLOCK_STONE
	if biome == BiomeCatalogScript.BADLANDS:
		top = _badlands_stratum(world_x, surface_y, world_z)
		sub = _badlands_stratum(world_x, maxi(1, surface_y - 1), world_z)
	return Vector3i(top, sub, depth)


func _badlands_stratum(world_x: int, y: int, world_z: int) -> int:
	var band: int = WorldGenHashScript.positive_mod(y + WorldGenHashScript.hash_2d(config.seed + 401, world_x >> 4, world_z >> 4), 9)
	return BlockRegistryScript.BLOCK_RED_SAND if band < 3 else BlockRegistryScript.BLOCK_TERRACOTTA


## A handful of connected, cell-anchored segments are substantially cheaper
## than sampling a hash/noise function for every underground voxel.
func _carve_worm_caves(data: PackedByteArray, field: ChunkTerrainData, origin_x: int, origin_z: int) -> void:
	var first_x: int = WorldGenHashScript.floor_div(origin_x - 24, CAVE_CELL_SIZE)
	var last_x: int = WorldGenHashScript.floor_div(origin_x + VoxelDefsScript.CHUNK_SIZE + 24, CAVE_CELL_SIZE)
	var first_z: int = WorldGenHashScript.floor_div(origin_z - 24, CAVE_CELL_SIZE)
	var last_z: int = WorldGenHashScript.floor_div(origin_z + VoxelDefsScript.CHUNK_SIZE + 24, CAVE_CELL_SIZE)
	for cell_z in range(first_z, last_z + 1):
		for cell_x in range(first_x, last_x + 1):
			for cell_y in range(0, 5):
				var anchor_hash: int = WorldGenHashScript.hash_3d(config.seed + 701, cell_x, cell_y, cell_z)
				var chance: float = float(anchor_hash % 1000) / 1000.0
				if chance >= minf(0.66, 0.20 * config.cave_density):
					continue
				var point := Vector3i(
					cell_x * CAVE_CELL_SIZE + 2 + anchor_hash % (CAVE_CELL_SIZE - 4),
					cell_y * CAVE_CELL_SIZE + 5 + (anchor_hash / 11) % 14,
					cell_z * CAVE_CELL_SIZE + 2 + (anchor_hash / 97) % (CAVE_CELL_SIZE - 4)
				)
				var segment_count: int = 2 + anchor_hash % 3
				for segment in range(segment_count):
					var step_hash: int = WorldGenHashScript.hash_3d(config.seed + 719 + segment, cell_x, cell_y, cell_z)
					var next := point + Vector3i((step_hash % 13) - 6, ((step_hash / 17) % 9) - 4, ((step_hash / 241) % 13) - 6)
					next.y = clampi(next.y, 4, VoxelDefsScript.SEA_LEVEL + 44)
					_stamp_tunnel(data, field, point, next, 2 + step_hash % 2)
					point = next


func _stamp_tunnel(data: PackedByteArray, field: ChunkTerrainData, start: Vector3i, finish: Vector3i, radius: int) -> void:
	var distance: int = maxi(maxi(absi(finish.x - start.x), absi(finish.y - start.y)), absi(finish.z - start.z))
	for step in range(distance + 1):
		var point := Vector3i(
			start.x + (finish.x - start.x) * step / maxi(1, distance),
			start.y + (finish.y - start.y) * step / maxi(1, distance),
			start.z + (finish.z - start.z) * step / maxi(1, distance)
		)
		_carve_ellipsoid(data, field, point, radius, radius, radius)


## Sparse global-cell entrances descend diagonally into the worm band. Every
## neighboring chunk evaluates the same origin and clips the same tunnel, so an
## opening crossing a border never depends on generation order.
func _carve_cave_entrances(data: PackedByteArray, field: ChunkTerrainData, origin_x: int, origin_z: int) -> void:
	if terrain_sampler == null:
		return
	const entrance_cell_size := 64
	const entrance_halo := 24
	var first_x := WorldGenHashScript.floor_div(origin_x - entrance_halo, entrance_cell_size)
	var last_x := WorldGenHashScript.floor_div(origin_x + VoxelDefsScript.CHUNK_SIZE - 1 + entrance_halo, entrance_cell_size)
	var first_z := WorldGenHashScript.floor_div(origin_z - entrance_halo, entrance_cell_size)
	var last_z := WorldGenHashScript.floor_div(origin_z + VoxelDefsScript.CHUNK_SIZE - 1 + entrance_halo, entrance_cell_size)
	for cell_z in range(first_z, last_z + 1):
		for cell_x in range(first_x, last_x + 1):
			var hash_value := WorldGenHashScript.hash_2d(config.seed + 773, cell_x, cell_z)
			if float(hash_value % 1000) / 1000.0 >= minf(0.12, 0.04 * config.cave_density):
				continue
			var world_x := cell_x * entrance_cell_size + 8 + hash_value % 48
			var world_z := cell_z * entrance_cell_size + 8 + (hash_value / 53) % 48
			var ground := terrain_sampler.sample_decoration_ground(world_x, world_z)
			if ground.y in [BiomeCatalogScript.OCEAN, BiomeCatalogScript.DEEP_OCEAN, BiomeCatalogScript.BEACH, BiomeCatalogScript.RIVER, BiomeCatalogScript.SWAMP]:
				continue
			var direction_x := -1 if ((hash_value / 101) & 1) == 0 else 1
			var direction_z := -1 if ((hash_value / 211) & 1) == 0 else 1
			var start := Vector3i(world_x, ground.x + 1, world_z)
			var finish := Vector3i(world_x + direction_x * 8, ground.x - 12, world_z + direction_z * 8)
			_stamp_entrance_tunnel(data, field, start, finish)


func _stamp_entrance_tunnel(data: PackedByteArray, field: ChunkTerrainData, start: Vector3i, finish: Vector3i) -> void:
	var distance := maxi(maxi(absi(finish.x - start.x), absi(finish.y - start.y)), absi(finish.z - start.z))
	for step in range(distance + 1):
		var point := Vector3i(
			start.x + (finish.x - start.x) * step / maxi(1, distance),
			start.y + (finish.y - start.y) * step / maxi(1, distance),
			start.z + (finish.z - start.z) * step / maxi(1, distance))
		_carve_ellipsoid(data, field, point, 2, 2, 2, true)


func _carve_caverns(data: PackedByteArray, field: ChunkTerrainData, origin_x: int, origin_z: int) -> void:
	var first_x: int = WorldGenHashScript.floor_div(origin_x - 14, 40)
	var last_x: int = WorldGenHashScript.floor_div(origin_x + VoxelDefsScript.CHUNK_SIZE + 14, 40)
	var first_z: int = WorldGenHashScript.floor_div(origin_z - 14, 40)
	var last_z: int = WorldGenHashScript.floor_div(origin_z + VoxelDefsScript.CHUNK_SIZE + 14, 40)
	for cell_z in range(first_z, last_z + 1):
		for cell_x in range(first_x, last_x + 1):
			var hash_value: int = WorldGenHashScript.hash_2d(config.seed + 809, cell_x, cell_z)
			if float(hash_value % 1000) / 1000.0 < minf(0.26, 0.065 * config.cave_density):
				var band_y: int = 12 + (hash_value / 13) % 42
				var center := Vector3i(cell_x * 40 + 5 + hash_value % 30, band_y, cell_z * 40 + 5 + (hash_value / 37) % 30)
				_carve_ellipsoid(data, field, center, 4 + hash_value % 4, 2 + (hash_value / 7) % 3, 4 + (hash_value / 17) % 4)
	# Rare, warped-cell mega caves. Two offset lobes avoid a perfectly round room.
	var mega_first_x: int = WorldGenHashScript.floor_div(origin_x - 24, 80)
	var mega_last_x: int = WorldGenHashScript.floor_div(origin_x + VoxelDefsScript.CHUNK_SIZE + 24, 80)
	var mega_first_z: int = WorldGenHashScript.floor_div(origin_z - 24, 80)
	var mega_last_z: int = WorldGenHashScript.floor_div(origin_z + VoxelDefsScript.CHUNK_SIZE + 24, 80)
	for cell_z in range(mega_first_z, mega_last_z + 1):
		for cell_x in range(mega_first_x, mega_last_x + 1):
			var mega_hash: int = WorldGenHashScript.hash_2d(config.seed + 863, cell_x, cell_z)
			if float(mega_hash % 10000) / 10000.0 >= minf(0.035, 0.009 * config.cave_density):
				continue
			var warped := Vector3i(cell_x * 80 + 15 + mega_hash % 50, 18 + (mega_hash / 19) % 28, cell_z * 80 + 15 + (mega_hash / 59) % 50)
			_carve_ellipsoid(data, field, warped, 10 + mega_hash % 6, 5 + (mega_hash / 5) % 4, 9 + (mega_hash / 11) % 7)
			_carve_ellipsoid(data, field, warped + Vector3i(5, 1, -4), 7, 4, 8)


func _carve_ellipsoid(data: PackedByteArray, field: ChunkTerrainData, center: Vector3i, radius_x: int, radius_y: int, radius_z: int, allow_surface: bool = false) -> void:
	var chunk_origin_x := field.chunk_x * VoxelDefsScript.CHUNK_SIZE
	var chunk_origin_z := field.chunk_z * VoxelDefsScript.CHUNK_SIZE
	var first_world_x := maxi(center.x - radius_x, chunk_origin_x)
	var last_world_x := mini(center.x + radius_x, chunk_origin_x + VoxelDefsScript.CHUNK_SIZE - 1)
	var first_world_z := maxi(center.z - radius_z, chunk_origin_z)
	var last_world_z := mini(center.z + radius_z, chunk_origin_z + VoxelDefsScript.CHUNK_SIZE - 1)
	var base_y := maxi(3, center.y - radius_y)
	var last_y := mini(VoxelDefsScript.WORLD_HEIGHT - 1, center.y + radius_y)
	for world_z in range(first_world_z, last_world_z + 1):
		var local_z := world_z - chunk_origin_z
		var dz := float(world_z - center.z) / float(radius_z)
		var dz_squared := dz * dz
		for world_x in range(first_world_x, last_world_x + 1):
			var local_x := world_x - chunk_origin_x
			var dx := float(world_x - center.x) / float(radius_x)
			var horizontal_squared := dx * dx + dz_squared
			if horizontal_squared > 1.0:
				continue
			var field_index := ChunkTerrainDataScript.cell_index(local_x, local_z)
			var column_last_y := mini(last_y, _surface_height(field, field_index) + (1 if allow_surface else -SURFACE_CLEARANCE - 1))
			if field.river[field_index] >= 0.62:
				column_last_y = mini(column_last_y, VoxelDefsScript.SEA_LEVEL - 3)
			for y in range(base_y, column_last_y + 1):
				var dy := float(y - center.y) / float(radius_y)
				if horizontal_squared + dy * dy > 1.0:
					continue
				var voxel_index: int = _index(local_x, y, local_z)
				var block_id := data[voxel_index]
				if block_id == BlockRegistryScript.BLOCK_STONE or block_id == BlockRegistryScript.BLOCK_COBBLESTONE or (allow_surface and block_id in [
					BlockRegistryScript.BLOCK_GRASS, BlockRegistryScript.BLOCK_DIRT, BlockRegistryScript.BLOCK_SAND,
					BlockRegistryScript.BLOCK_SNOW, BlockRegistryScript.BLOCK_GRAVEL, BlockRegistryScript.BLOCK_CLAY,
					BlockRegistryScript.BLOCK_MUD, BlockRegistryScript.BLOCK_RED_SAND, BlockRegistryScript.BLOCK_TERRACOTTA,
					BlockRegistryScript.BLOCK_MYCELIUM]):
					data[voxel_index] = BlockRegistryScript.BLOCK_AIR


func _fill_underground_liquids(data: PackedByteArray, field: ChunkTerrainData, origin_x: int, origin_z: int) -> void:
	var aquifer_cell_x := WorldGenHashScript.floor_div(origin_x, VoxelDefsScript.CHUNK_SIZE)
	var aquifer_cell_z := WorldGenHashScript.floor_div(origin_z, VoxelDefsScript.CHUNK_SIZE)
	var aquifer_hash := WorldGenHashScript.hash_2d(config.seed + 907, aquifer_cell_x, aquifer_cell_z)
	if aquifer_hash % 11 == 0:
		var water_level := 15 + (aquifer_hash / 31) % 13
		for local_z in VoxelDefsScript.CHUNK_SIZE:
			for local_x in VoxelDefsScript.CHUNK_SIZE:
				var field_index: int = ChunkTerrainDataScript.cell_index(local_x, local_z)
				var top: int = _surface_height(field, field_index)
				for y in range(4, mini(water_level, top - SURFACE_CLEARANCE) + 1):
					var voxel_index: int = _index(local_x, y, local_z)
					if data[voxel_index] == BlockRegistryScript.BLOCK_AIR:
						data[voxel_index] = BlockRegistryScript.BLOCK_WATER
	# Deep lake cells only fill air, so lava never burns through solid terrain.
	var lava_first_x: int = WorldGenHashScript.floor_div(origin_x - 8, 32)
	var lava_last_x: int = WorldGenHashScript.floor_div(origin_x + VoxelDefsScript.CHUNK_SIZE + 8, 32)
	var lava_first_z: int = WorldGenHashScript.floor_div(origin_z - 8, 32)
	var lava_last_z: int = WorldGenHashScript.floor_div(origin_z + VoxelDefsScript.CHUNK_SIZE + 8, 32)
	for cell_z in range(lava_first_z, lava_last_z + 1):
		for cell_x in range(lava_first_x, lava_last_x + 1):
			var lava_hash: int = WorldGenHashScript.hash_2d(config.seed + 941, cell_x, cell_z)
			if lava_hash % 29 != 0:
				continue
			_fill_lava_lake(data, field, Vector3i(cell_x * 32 + 5 + lava_hash % 22, 5 + (lava_hash / 7) % 6, cell_z * 32 + 5 + (lava_hash / 43) % 22), 4 + lava_hash % 3)


func _fill_lava_lake(data: PackedByteArray, field: ChunkTerrainData, center: Vector3i, radius: int) -> void:
	for world_z in range(center.z - radius, center.z + radius + 1):
		var local_z: int = world_z - field.chunk_z * VoxelDefsScript.CHUNK_SIZE
		if local_z < 0 or local_z >= VoxelDefsScript.CHUNK_SIZE:
			continue
		for world_x in range(center.x - radius, center.x + radius + 1):
			var local_x: int = world_x - field.chunk_x * VoxelDefsScript.CHUNK_SIZE
			if local_x < 0 or local_x >= VoxelDefsScript.CHUNK_SIZE:
				continue
			var dx: int = world_x - center.x
			var dz: int = world_z - center.z
			if dx * dx + dz * dz > radius * radius:
				continue
			var voxel_index: int = _index(local_x, center.y, local_z)
			if data[voxel_index] == BlockRegistryScript.BLOCK_AIR:
				data[voxel_index] = BlockRegistryScript.BLOCK_LAVA


func _place_ore_veins(data: PackedByteArray, origin_x: int, origin_z: int) -> void:
	var first_x: int = WorldGenHashScript.floor_div(origin_x - 8, ORE_CELL_SIZE)
	var last_x: int = WorldGenHashScript.floor_div(origin_x + VoxelDefsScript.CHUNK_SIZE + 8, ORE_CELL_SIZE)
	var first_z: int = WorldGenHashScript.floor_div(origin_z - 8, ORE_CELL_SIZE)
	var last_z: int = WorldGenHashScript.floor_div(origin_z + VoxelDefsScript.CHUNK_SIZE + 8, ORE_CELL_SIZE)
	for cell_z in range(first_z, last_z + 1):
		for cell_x in range(first_x, last_x + 1):
			for cell_y in range(0, 7):
				var hash_value: int = WorldGenHashScript.hash_3d(config.seed + 1009, cell_x, cell_y, cell_z)
				var ore: int = _ore_for_anchor(hash_value, cell_y * ORE_CELL_SIZE)
				if ore == BlockRegistryScript.BLOCK_AIR:
					continue
				var start := Vector3i(cell_x * ORE_CELL_SIZE + 2 + hash_value % 16, cell_y * ORE_CELL_SIZE + 2 + (hash_value / 17) % 16, cell_z * ORE_CELL_SIZE + 2 + (hash_value / 73) % 16)
				var finish := start + Vector3i((hash_value / 7) % 7 - 3, (hash_value / 131) % 5 - 2, (hash_value / 251) % 7 - 3)
				_stamp_ore_segment(data, origin_x, origin_z, start, finish, ore)


## Sparse deterministic cave details: damp floor patches plus stone teeth on
## cave ceilings/floors. Anchors use global cells, so formations cross chunk
## boundaries without depending on generation order.
func _decorate_caves(data: PackedByteArray, origin_x: int, origin_z: int) -> void:
	for local_z in range(2, VoxelDefsScript.CHUNK_SIZE, 4):
		for local_x in range(2, VoxelDefsScript.CHUNK_SIZE, 4):
			var world_x := origin_x + local_x
			var world_z := origin_z + local_z
			for y in range(6, VoxelDefsScript.SEA_LEVEL + 32, 5):
				var air_index := _index(local_x, y, local_z)
				if data[air_index] != BlockRegistryScript.BLOCK_AIR:
					continue
				var hash_value := WorldGenHashScript.hash_3d(config.seed + 1061, world_x, y, world_z)
				if data[_index(local_x, y - 1, local_z)] == BlockRegistryScript.BLOCK_STONE and hash_value % 9 == 0:
					data[_index(local_x, y - 1, local_z)] = BlockRegistryScript.BLOCK_MYCELIUM if hash_value % 3 == 0 else BlockRegistryScript.BLOCK_MUD
				if data[_index(local_x, y + 1, local_z)] == BlockRegistryScript.BLOCK_STONE and hash_value % 13 == 0:
					var length := 1 + hash_value % 3
					for offset in range(length):
						var target_y := y - offset
						if target_y <= 2 or data[_index(local_x, target_y, local_z)] != BlockRegistryScript.BLOCK_AIR:
							break
						data[_index(local_x, target_y, local_z)] = BlockRegistryScript.BLOCK_TERRACOTTA


func _ore_for_anchor(hash_value: int, y: int) -> int:
	var roll: int = hash_value % 100
	if y < 32 and roll < 17:
		return BlockRegistryScript.BLOCK_GOLD_ORE
	if y < 58 and roll < 34:
		return BlockRegistryScript.BLOCK_IRON_ORE
	if y < 90 and roll < 57:
		return BlockRegistryScript.BLOCK_COAL_ORE
	return BlockRegistryScript.BLOCK_AIR


func _stamp_ore_segment(data: PackedByteArray, origin_x: int, origin_z: int, start: Vector3i, finish: Vector3i, ore: int) -> void:
	var distance: int = maxi(maxi(absi(finish.x - start.x), absi(finish.y - start.y)), absi(finish.z - start.z))
	for step in range(distance + 1):
		var center := Vector3i(start.x + (finish.x - start.x) * step / maxi(1, distance), start.y + (finish.y - start.y) * step / maxi(1, distance), start.z + (finish.z - start.z) * step / maxi(1, distance))
		for z in range(center.z - 1, center.z + 2):
			var local_z: int = z - origin_z
			if local_z < 0 or local_z >= VoxelDefsScript.CHUNK_SIZE:
				continue
			for x in range(center.x - 1, center.x + 2):
				var local_x: int = x - origin_x
				if local_x < 0 or local_x >= VoxelDefsScript.CHUNK_SIZE:
					continue
				for y in range(center.y - 1, center.y + 2):
					if y < 1 or y >= VoxelDefsScript.WORLD_HEIGHT:
						continue
					if data[_index(local_x, y, local_z)] == BlockRegistryScript.BLOCK_STONE:
						data[_index(local_x, y, local_z)] = ore


func _decorate(data: PackedByteArray, field: ChunkTerrainData, origin_x: int, origin_z: int, max_y: int) -> int:
	# This cache is strictly per populate() call. It avoids repeatedly resolving
	# expensive immutable sampler queries without introducing worker-shared state.
	var tree_ground_cache: Dictionary = {}
	# Dense-biome trees have a dedicated clustered pass. Ground flora and sparse
	# biome trees use the regular deterministic feature lattice below.
	max_y = maxi(max_y, _decorate_tree_groves(data, field, origin_x, origin_z, tree_ground_cache))
	var first_x: int = WorldGenHashScript.floor_div(origin_x - FEATURE_HALO, FEATURE_CELL_SIZE)
	var last_x: int = WorldGenHashScript.floor_div(origin_x + VoxelDefsScript.CHUNK_SIZE - 1 + FEATURE_HALO, FEATURE_CELL_SIZE)
	var first_z: int = WorldGenHashScript.floor_div(origin_z - FEATURE_HALO, FEATURE_CELL_SIZE)
	var last_z: int = WorldGenHashScript.floor_div(origin_z + VoxelDefsScript.CHUNK_SIZE - 1 + FEATURE_HALO, FEATURE_CELL_SIZE)
	for cell_z in range(first_z, last_z + 1):
		for cell_x in range(first_x, last_x + 1):
			var hash_value: int = WorldGenHashScript.hash_2d(config.seed + 1103, cell_x, cell_z)
			var world_x: int = cell_x * FEATURE_CELL_SIZE + 1 + hash_value % (FEATURE_CELL_SIZE - 2)
			var world_z: int = cell_z * FEATURE_CELL_SIZE + 1 + (hash_value / 31) % (FEATURE_CELL_SIZE - 2)
			var ground := _cached_decoration_ground(field, world_x, world_z, tree_ground_cache)
			if ground.x < 0:
				continue
			var biome: int = ground.y
			var decoration_set: int = biomes.decoration_set(biome)
			var selector: float = WorldGenHashScript.float_01_2d(config.seed + 1117, cell_x, cell_z)
			var entry: Array = decorations.choose_non_tree(decoration_set, selector) if _uses_grove_trees(decoration_set) else decorations.choose(decoration_set, selector)
			if entry.is_empty():
				continue
			var feature: int = int(entry[0])
			var flags: int = int(entry[3])
			var probability: float = float(entry[2]) * config.decoration_density
			if (flags & DecorationCatalog.FLAG_TREE) != 0:
				probability *= config.tree_density
			if WorldGenHashScript.float_01_2d(config.seed + 1129, cell_x, cell_z) >= minf(0.94, probability):
				continue
			if not _feature_site_is_valid(field, tree_ground_cache, world_x, ground.x, world_z, flags):
				continue
			if (flags & DecorationCatalog.FLAG_TREE) != 0 and feature != DecorationCatalog.FEATURE_MANGROVE:
				if not _tree_site_is_safe(field, tree_ground_cache, world_x, ground.x, world_z, _tree_footprint_for(feature), _tree_top_offset_for(feature, hash_value)):
					continue
			max_y = maxi(max_y, _stamp_feature(data, origin_x, origin_z, world_x, ground.x, world_z, feature, hash_value))
	max_y = maxi(max_y, _decorate_ground_cover(data, field, origin_x, origin_z))
	return max_y


## Forest, taiga, and jungle trees use a separate global lattice rather than
## the one-decoration-per-cell lottery. Broad, hash-anchored discs create dense
## groves with genuine clearings, and every query is based solely on immutable
## world coordinates (never on resident chunks or feature placement order).
func _decorate_tree_groves(data: PackedByteArray, field: ChunkTerrainData, origin_x: int, origin_z: int, ground_cache: Dictionary) -> int:
	if config.tree_density <= 0.0 or config.decoration_density <= 0.0:
		return 0
	var max_y := 0
	var first_x: int = WorldGenHashScript.floor_div(origin_x - TREE_FOOTPRINT_RADIUS, TREE_CELL_SIZE)
	var last_x: int = WorldGenHashScript.floor_div(origin_x + VoxelDefsScript.CHUNK_SIZE - 1 + TREE_FOOTPRINT_RADIUS, TREE_CELL_SIZE)
	var first_z: int = WorldGenHashScript.floor_div(origin_z - TREE_FOOTPRINT_RADIUS, TREE_CELL_SIZE)
	var last_z: int = WorldGenHashScript.floor_div(origin_z + VoxelDefsScript.CHUNK_SIZE - 1 + TREE_FOOTPRINT_RADIUS, TREE_CELL_SIZE)
	for cell_z in range(first_z, last_z + 1):
		for cell_x in range(first_x, last_x + 1):
			var anchor_hash: int = WorldGenHashScript.hash_2d(config.seed + 1223, cell_x, cell_z)
			# Keep anchors at least five blocks apart, even across cell boundaries.
			# This permits overlapping crowns but prevents one candidate's foliage
			# from occupying another candidate's root/trunk volume.
			var world_x: int = cell_x * TREE_CELL_SIZE + 2 + anchor_hash % 2
			var world_z: int = cell_z * TREE_CELL_SIZE + 2 + (anchor_hash / 23) % 2
			var ground := _cached_decoration_ground(field, world_x, world_z, ground_cache)
			if ground.x < VoxelDefsScript.SEA_LEVEL - 3:
				continue
			var decoration_set: int = biomes.decoration_set(ground.y)
			if not _uses_grove_trees(decoration_set):
				continue
			var grove_strength: float = _tree_grove_strength(world_x, world_z)
			var probability: float = _grove_tree_probability(decoration_set, grove_strength)
			if WorldGenHashScript.float_01_2d(config.seed + 1237, cell_x, cell_z) >= probability:
				continue
			var feature_hash: int = WorldGenHashScript.hash_2d(config.seed + 1249, cell_x, cell_z)
			var entry: Array = decorations.choose_tree(decoration_set, WorldGenHashScript.float_01_2d(config.seed + 1261, cell_x, cell_z))
			if entry.is_empty():
				continue
			var feature: int = int(entry[0])
			var footprint: int = _tree_footprint_for(feature)
			var top_offset: int = _tree_top_offset_for(feature, feature_hash)
			var flags: int = int(entry[3])
			if not _feature_site_is_valid(field, ground_cache, world_x, ground.x, world_z, flags):
				continue
			if feature != DecorationCatalog.FEATURE_MANGROVE:
				if not _tree_site_is_safe(field, ground_cache, world_x, ground.x, world_z, footprint, top_offset):
					continue
			max_y = maxi(max_y, _stamp_feature(data, origin_x, origin_z, world_x, ground.x, world_z, feature, feature_hash))
	return max_y


func _uses_grove_trees(decoration_set: int) -> bool:
	return decoration_set == BiomeCatalogScript.DECORATION_FOREST \
		or decoration_set == BiomeCatalogScript.DECORATION_TAIGA \
		or decoration_set == BiomeCatalogScript.DECORATION_TROPICAL \
		or decoration_set == BiomeCatalogScript.DECORATION_SWAMP


## A nearby accepted grove cell contributes a rounded density field. Searching
## the fixed 3x3 neighborhood prevents square grid artifacts while retaining
## bounded, repeatable work for every tree candidate.
func _tree_grove_strength(world_x: int, world_z: int) -> float:
	var cell_x: int = WorldGenHashScript.floor_div(world_x, TREE_GROVE_CELL_SIZE)
	var cell_z: int = WorldGenHashScript.floor_div(world_z, TREE_GROVE_CELL_SIZE)
	var strongest := 0.0
	for grove_z in range(cell_z - TREE_GROVE_SEARCH_RADIUS, cell_z + TREE_GROVE_SEARCH_RADIUS + 1):
		for grove_x in range(cell_x - TREE_GROVE_SEARCH_RADIUS, cell_x + TREE_GROVE_SEARCH_RADIUS + 1):
			var grove_hash: int = WorldGenHashScript.hash_2d(config.seed + 1277, grove_x, grove_z)
			if float(grove_hash % 1000) / 1000.0 >= 0.80:
				continue
			var center_x: int = grove_x * TREE_GROVE_CELL_SIZE + 10 + grove_hash % 29
			var center_z: int = grove_z * TREE_GROVE_CELL_SIZE + 10 + (grove_hash / 37) % 29
			var radius: float = float(22 + (grove_hash / 73) % 9)
			var dx: float = float(world_x - center_x)
			var dz: float = float(world_z - center_z)
			var distance: float = sqrt(dx * dx + dz * dz)
			var normalized: float = distance / radius
			var strength: float = 1.0 - _smoothstep(0.62, 1.0, normalized)
			strongest = maxf(strongest, strength)
	return strongest


func _grove_tree_probability(decoration_set: int, grove_strength: float) -> float:
	var base := 0.0
	match decoration_set:
		BiomeCatalogScript.DECORATION_FOREST:
			base = 0.94
		BiomeCatalogScript.DECORATION_TAIGA:
			base = 0.90
		BiomeCatalogScript.DECORATION_TROPICAL:
			base = 0.96
		BiomeCatalogScript.DECORATION_SWAMP:
			base = 0.86
	return minf(0.96, base * grove_strength * config.tree_density * config.decoration_density)


## Placement flags are evaluated from immutable terrain samples so every chunk
## touching a cross-border feature reaches the same ecological decision.
func _feature_site_is_valid(field: ChunkTerrainData, ground_cache: Dictionary, world_x: int, ground_y: int, world_z: int, flags: int) -> bool:
	if ground_y < 1 or ground_y + 1 >= VoxelDefsScript.WORLD_HEIGHT:
		return false
	var site_biome: int = _cached_decoration_ground(field, world_x, world_z, ground_cache).y
	if (flags & DecorationCatalog.FLAG_DRY_GROUND) != 0:
		var surface_block: int = biomes.surface_block(site_biome)
		if surface_block != BlockRegistryScript.BLOCK_SAND and surface_block != BlockRegistryScript.BLOCK_RED_SAND:
			return false
	if (flags & DecorationCatalog.FLAG_WATER_EDGE) != 0:
		var max_water_edge_y := VoxelDefsScript.SEA_LEVEL + (5 if site_biome == BiomeCatalogScript.SWAMP else 2)
		var near_water := ground_y < VoxelDefsScript.SEA_LEVEL \
			or (site_biome == BiomeCatalogScript.SWAMP and ground_y <= max_water_edge_y)
		for direction in VoxelDefsScript.DIRS_4:
			var neighbor := _cached_decoration_ground(
				field, world_x + direction.x * 2, world_z + direction.y * 2, ground_cache)
			if neighbor.x < VoxelDefsScript.SEA_LEVEL:
				near_water = true
				break
		if not near_water or ground_y > max_water_edge_y:
			return false
	if (flags & DecorationCatalog.FLAG_SHADE) != 0:
		if _tree_grove_strength(world_x, world_z) < 0.18:
			return false
	return true


func _tree_footprint_for(feature: int) -> int:
	match feature:
		DecorationCatalog.FEATURE_JUNGLE, DecorationCatalog.FEATURE_SPRUCE:
			return 3
		_:
			return 2


func _tree_top_offset_for(feature: int, hash_value: int) -> int:
	match feature:
		DecorationCatalog.FEATURE_OAK:
			return 4 + hash_value % 3 + 2
		DecorationCatalog.FEATURE_BIRCH:
			return 5 + hash_value % 3 + 2
		DecorationCatalog.FEATURE_SPRUCE:
			return 6 + hash_value % 4 + 1
		DecorationCatalog.FEATURE_JUNGLE:
			return 7 + hash_value % 4 + 2
	return 0


## This acceptance decision deliberately reads no generated voxel data. Every
## chunk that intersects a tree must reach the same answer, including chunks
## which only contain the canopy. Base/snow/cliff surface rules always produce
## a solid top above sea level; the profile probes reject steep/embedded sites,
## and the only cave stage allowed to reach that surface (an entrance) is
## reproduced below as a shared immutable exclusion.
func _tree_site_is_safe(field: ChunkTerrainData, ground_cache: Dictionary, world_x: int, ground_y: int, world_z: int, footprint: int, top_offset: int) -> bool:
	if ground_y <= VoxelDefsScript.SEA_LEVEL + 1 or ground_y + top_offset >= VoxelDefsScript.WORLD_HEIGHT:
		return false
	if _tree_root_is_near_cave_entrance(world_x, world_z):
		return false
	# Cardinal and diagonal edge probes catch the slope changes that would bury
	# the low canopy. Nine fixed probes (root plus this ring) replace the former
	# 29 point-query footprint scan; results are cached per chunk job.
	for direction in VoxelDefsScript.DIRS_8:
		var nearby_ground := _cached_decoration_ground(field, world_x + direction.x * footprint, world_z + direction.y * footprint, ground_cache)
		if nearby_ground.x < 0 or nearby_ground.x > ground_y + 1 or nearby_ground.x < ground_y - 3:
			return false
	return true


func _cached_decoration_ground(field: ChunkTerrainData, world_x: int, world_z: int, ground_cache: Dictionary) -> Vector2i:
	var position := Vector2i(world_x, world_z)
	if ground_cache.has(position):
		return ground_cache[position]
	var ground := _decoration_ground(field, world_x, world_z)
	ground_cache[position] = ground
	return ground


## Worm caves retain a surface clearance. Entrances are the only cave stage
## allowed to touch the ground, so reproduce their tiny global anchor test here
## to keep chunks other than the root owner from stamping orphaned leaf pieces.
func _tree_root_is_near_cave_entrance(world_x: int, world_z: int) -> bool:
	if config.cave_density <= 0.0:
		return false
	const entrance_cell_size := 64
	var first_x: int = WorldGenHashScript.floor_div(world_x - 12, entrance_cell_size)
	var last_x: int = WorldGenHashScript.floor_div(world_x + 12, entrance_cell_size)
	var first_z: int = WorldGenHashScript.floor_div(world_z - 12, entrance_cell_size)
	var last_z: int = WorldGenHashScript.floor_div(world_z + 12, entrance_cell_size)
	for cell_z in range(first_z, last_z + 1):
		for cell_x in range(first_x, last_x + 1):
			var hash_value: int = WorldGenHashScript.hash_2d(config.seed + 773, cell_x, cell_z)
			if float(hash_value % 1000) / 1000.0 >= minf(0.12, 0.04 * config.cave_density):
				continue
			var start_x: int = cell_x * entrance_cell_size + 8 + hash_value % 48
			var start_z: int = cell_z * entrance_cell_size + 8 + (hash_value / 53) % 48
			var direction_x: int = -1 if ((hash_value / 101) & 1) == 0 else 1
			var direction_z: int = -1 if ((hash_value / 211) & 1) == 0 else 1
			for step in range(9):
				var dx: int = world_x - (start_x + direction_x * step)
				var dz: int = world_z - (start_z + direction_z * step)
				if dx * dx + dz * dz <= 9:
					return true
	return false


## Global tuft anchors are evaluated with a halo, so a target near a chunk edge
## is selected from exactly the same seed/cell regardless of generation order.
## This is deliberately separate from the tree/feature lottery above.
func _decorate_ground_cover(data: PackedByteArray, field: ChunkTerrainData, origin_x: int, origin_z: int) -> int:
	var max_y := 0
	var first_x: int = WorldGenHashScript.floor_div(origin_x - GROUND_COVER_RADIUS, GROUND_COVER_CELL_SIZE)
	var last_x: int = WorldGenHashScript.floor_div(origin_x + VoxelDefsScript.CHUNK_SIZE - 1 + GROUND_COVER_RADIUS, GROUND_COVER_CELL_SIZE)
	var first_z: int = WorldGenHashScript.floor_div(origin_z - GROUND_COVER_RADIUS, GROUND_COVER_CELL_SIZE)
	var last_z: int = WorldGenHashScript.floor_div(origin_z + VoxelDefsScript.CHUNK_SIZE - 1 + GROUND_COVER_RADIUS, GROUND_COVER_CELL_SIZE)
	for cell_z in range(first_z, last_z + 1):
		for cell_x in range(first_x, last_x + 1):
			var anchor_hash: int = WorldGenHashScript.hash_2d(config.seed + 1181, cell_x, cell_z)
			var center_x: int = cell_x * GROUND_COVER_CELL_SIZE + 2 + anchor_hash % (GROUND_COVER_CELL_SIZE - 4)
			var center_z: int = cell_z * GROUND_COVER_CELL_SIZE + 2 + (anchor_hash / 29) % (GROUND_COVER_CELL_SIZE - 4)
			var ground := _decoration_ground(field, center_x, center_z)
			if ground.x <= VoxelDefsScript.SEA_LEVEL + 1:
				continue
			var chance: float = decorations.ground_cover_chance(biomes.decoration_set(ground.y)) * config.decoration_density
			if chance <= 0.0 or WorldGenHashScript.float_01_2d(config.seed + 1193, cell_x, cell_z) >= minf(0.92, chance):
				continue
			var tuft_count: int = 2 + (anchor_hash / 71) % 3
			for tuft_index in tuft_count:
				var tuft_hash: int = WorldGenHashScript.hash_3d(config.seed + 1201, cell_x, tuft_index, cell_z)
				var world_x: int = center_x + (tuft_hash % 5) - 2
				var world_z: int = center_z + ((tuft_hash / 13) % 5) - 2
				max_y = maxi(max_y, _place_ground_cover(data, field, origin_x, origin_z, world_x, world_z))
	return max_y


## Validate against the generated voxel data after caves and regular features:
## grass never floats over a carved entrance, overwrites a feature, or appears
## on water/sand. Grass surface blocks are opaque, dry soil by definition.
func _place_ground_cover(data: PackedByteArray, field: ChunkTerrainData, origin_x: int, origin_z: int, world_x: int, world_z: int) -> int:
	var local_x: int = world_x - origin_x
	var local_z: int = world_z - origin_z
	if local_x < 0 or local_x >= VoxelDefsScript.CHUNK_SIZE or local_z < 0 or local_z >= VoxelDefsScript.CHUNK_SIZE:
		return -1
	var ground := _decoration_ground(field, world_x, world_z)
	var ground_y: int = ground.x
	if ground_y <= VoxelDefsScript.SEA_LEVEL + 1 or ground_y + 1 >= VoxelDefsScript.WORLD_HEIGHT:
		return -1
	if data[_index(local_x, ground_y, local_z)] != BlockRegistryScript.BLOCK_GRASS:
		return -1
	if data[_index(local_x, ground_y + 1, local_z)] != BlockRegistryScript.BLOCK_AIR:
		return -1
	data[_index(local_x, ground_y + 1, local_z)] = BlockRegistryScript.BLOCK_TALL_GRASS
	return ground_y + 1


## The field handles the immediate border; farther feature-cell origins query
## the same immutable global sampler so large decorations agree across chunks.
func _decoration_ground(field: ChunkTerrainData, world_x: int, world_z: int) -> Vector2i:
	var local_x: int = world_x - field.chunk_x * VoxelDefsScript.CHUNK_SIZE
	var local_z: int = world_z - field.chunk_z * VoxelDefsScript.CHUNK_SIZE
	if ChunkTerrainDataScript.is_valid_local(local_x, local_z):
		var field_index: int = ChunkTerrainDataScript.cell_index(local_x, local_z)
		return Vector2i(_surface_height(field, field_index), int(field.dominant_biome[field_index]))
	if terrain_sampler == null:
		return Vector2i(-1, -1)
	return terrain_sampler.sample_decoration_ground(world_x, world_z)


func _stamp_feature(data: PackedByteArray, origin_x: int, origin_z: int, world_x: int, ground_y: int, world_z: int, feature: int, hash_value: int) -> int:
	match feature:
		DecorationCatalog.FEATURE_OAK:
			return _stamp_tree(data, origin_x, origin_z, world_x, ground_y, world_z, BlockRegistryScript.BLOCK_LOG, BlockRegistryScript.BLOCK_LEAVES, 4 + hash_value % 3, 2, hash_value)
		DecorationCatalog.FEATURE_BIRCH:
			return _stamp_tree(data, origin_x, origin_z, world_x, ground_y, world_z, BlockRegistryScript.BLOCK_BIRCH_LOG, BlockRegistryScript.BLOCK_BIRCH_LEAVES, 5 + hash_value % 3, 2, hash_value)
		DecorationCatalog.FEATURE_SPRUCE:
			return _stamp_spruce(data, origin_x, origin_z, world_x, ground_y, world_z, 6 + hash_value % 4, hash_value)
		DecorationCatalog.FEATURE_ACACIA:
			return _stamp_acacia(data, origin_x, origin_z, world_x, ground_y, world_z, hash_value)
		DecorationCatalog.FEATURE_JUNGLE:
			return _stamp_tree(data, origin_x, origin_z, world_x, ground_y, world_z, BlockRegistryScript.BLOCK_JUNGLE_LOG, BlockRegistryScript.BLOCK_JUNGLE_LEAVES, 7 + hash_value % 4, 3, hash_value)
		DecorationCatalog.FEATURE_MANGROVE:
			return _stamp_mangrove(data, origin_x, origin_z, world_x, ground_y, world_z)
		DecorationCatalog.FEATURE_CACTUS:
			return _stamp_vertical(data, origin_x, origin_z, world_x, ground_y + 1, world_z, BlockRegistryScript.BLOCK_CACTUS, 2 + hash_value % 3)
		DecorationCatalog.FEATURE_BAMBOO:
			return _stamp_vertical(data, origin_x, origin_z, world_x, ground_y + 1, world_z, BlockRegistryScript.BLOCK_BAMBOO, 3 + hash_value % 5)
		DecorationCatalog.FEATURE_VINE:
			return _stamp_vertical(data, origin_x, origin_z, world_x, ground_y + 1, world_z, BlockRegistryScript.BLOCK_VINE, 2 + hash_value % 4)
		DecorationCatalog.FEATURE_BOULDER:
			return _stamp_boulder(data, origin_x, origin_z, world_x, ground_y, world_z, hash_value)
		DecorationCatalog.FEATURE_FALLEN_LOG:
			return _stamp_fallen_log(data, origin_x, origin_z, world_x, ground_y, world_z, hash_value)
		DecorationCatalog.FEATURE_MELON:
			return _place(data, origin_x, origin_z, world_x, ground_y + 1, world_z, BlockRegistryScript.BLOCK_MELON) + 1
		DecorationCatalog.FEATURE_RED_FLOWER:
			return _place(data, origin_x, origin_z, world_x, ground_y + 1, world_z, BlockRegistryScript.BLOCK_RED_FLOWER) + 1
		DecorationCatalog.FEATURE_YELLOW_FLOWER:
			return _place(data, origin_x, origin_z, world_x, ground_y + 1, world_z, BlockRegistryScript.BLOCK_YELLOW_FLOWER) + 1
		DecorationCatalog.FEATURE_DEAD_BUSH:
			return _place(data, origin_x, origin_z, world_x, ground_y + 1, world_z, BlockRegistryScript.BLOCK_DEAD_BUSH) + 1
		DecorationCatalog.FEATURE_BROWN_MUSHROOM:
			return _place(data, origin_x, origin_z, world_x, ground_y + 1, world_z, BlockRegistryScript.BLOCK_BROWN_MUSHROOM) + 1
		DecorationCatalog.FEATURE_RED_MUSHROOM:
			return _place(data, origin_x, origin_z, world_x, ground_y + 1, world_z, BlockRegistryScript.BLOCK_RED_MUSHROOM) + 1
		DecorationCatalog.FEATURE_REEDS:
			return _stamp_vertical(data, origin_x, origin_z, world_x, maxi(ground_y + 1, VoxelDefsScript.SEA_LEVEL + 1), world_z, BlockRegistryScript.BLOCK_TALL_GRASS, 2 + hash_value % 2)
		_:
			return _place(data, origin_x, origin_z, world_x, ground_y + 1, world_z, BlockRegistryScript.BLOCK_TALL_GRASS) + 1


func _stamp_tree(data: PackedByteArray, origin_x: int, origin_z: int, world_x: int, ground_y: int, world_z: int, log_id: int, leaf_id: int, trunk_height: int, radius: int, hash_value: int) -> int:
	for y in range(1, trunk_height + 1):
		_place(data, origin_x, origin_z, world_x, ground_y + y, world_z, log_id)
	# One-block limbs add modest seeded variation, but always sit inside the
	# second-fullest canopy tier. Their ends therefore meet foliage instead of
	# reading as exposed, disconnected log stubs.
	var directions: Array = VoxelDefsScript.DIRS_8
	var limb_count: int = 1 + (hash_value / 7) % 2
	for limb in range(limb_count):
		var direction: Vector2i = directions[(hash_value / (19 + limb * 17) + limb * 3) % directions.size()]
		_place(data, origin_x, origin_z, world_x + direction.x, ground_y + trunk_height - 1, world_z + direction.y, log_id)
	# Five overlapping discs form a compact rounded volume rather than a thin,
	# irregular slab. No outer-leaf pruning is used: isolated scraps are much
	# more noticeable than the small amount of silhouette variation they add.
	for layer in range(-2, 3):
		var leaf_y: int = ground_y + trunk_height + layer
		var layer_radius: int = radius
		if layer == -2 or layer == 1:
			layer_radius = maxi(1, radius - 1)
		elif layer == 2:
			layer_radius = 0 if radius <= 2 else 1
		for dz in range(-layer_radius, layer_radius + 1):
			for dx in range(-layer_radius, layer_radius + 1):
				var distance_squared: int = dx * dx + dz * dz
				if distance_squared > layer_radius * layer_radius:
					continue
				_place(data, origin_x, origin_z, world_x + dx, leaf_y, world_z + dz, leaf_id)
	return ground_y + trunk_height + 2


func _stamp_spruce(data: PackedByteArray, origin_x: int, origin_z: int, world_x: int, ground_y: int, world_z: int, trunk_height: int, hash_value: int) -> int:
	for y in range(1, trunk_height + 1):
		_place(data, origin_x, origin_z, world_x, ground_y + y, world_z, BlockRegistryScript.BLOCK_SPRUCE_LOG)
	# Keep two trunk blocks exposed, then build discrete whorls from radius 3
	# down to a single-leaf tip. This avoids the old upper 3x3 leaf tower and
	# remains safely inside FEATURE_HALO (maximum horizontal reach is three).
	var canopy_layers: int = trunk_height - 1
	for offset in range(3, trunk_height + 2):
		var canopy_layer: int = offset - 3
		var radius: int = 0
		if canopy_layer < 2:
			radius = 3
		elif canopy_layer < canopy_layers - 2:
			radius = 2
		elif canopy_layer < canopy_layers - 1:
			radius = 1
		for dz in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				var distance_squared: int = dx * dx + dz * dz
				if distance_squared > radius * radius:
					continue
				# Prune a few outer needles deterministically so each whorl is not a
				# perfectly repeated disc, while preserving its tier radius.
				if radius >= 2 and distance_squared == radius * radius and (hash_value / 31 + dx * 11 + dz * 23 + canopy_layer * 41) % 7 == 0:
					continue
				_place(data, origin_x, origin_z, world_x + dx, ground_y + offset, world_z + dz, BlockRegistryScript.BLOCK_SPRUCE_LEAVES)
	return ground_y + trunk_height + 1


func _stamp_acacia(data: PackedByteArray, origin_x: int, origin_z: int, world_x: int, ground_y: int, world_z: int, hash_value: int) -> int:
	var height: int = 4 + hash_value % 3
	var direction := Vector2i(1, 0) if hash_value % 2 == 0 else Vector2i(0, 1)
	for y in range(1, height + 1):
		_place(data, origin_x, origin_z, world_x, ground_y + y, world_z, BlockRegistryScript.BLOCK_ACACIA_LOG)
	_place(data, origin_x, origin_z, world_x + direction.x, ground_y + height, world_z + direction.y, BlockRegistryScript.BLOCK_ACACIA_LOG)
	for dz in range(-2, 3):
		for dx in range(-2, 3):
			if dx * dx + dz * dz <= 5:
				_place(data, origin_x, origin_z, world_x + direction.x + dx, ground_y + height + 1, world_z + direction.y + dz, BlockRegistryScript.BLOCK_ACACIA_LEAVES)
	return ground_y + height + 1


func _stamp_mangrove(data: PackedByteArray, origin_x: int, origin_z: int, world_x: int, ground_y: int, world_z: int) -> int:
	var base_y := maxi(ground_y, VoxelDefsScript.SEA_LEVEL - 1)
	_place_replaceable(data, origin_x, origin_z, world_x, base_y + 1, world_z, BlockRegistryScript.BLOCK_MANGROVE_ROOTS)
	for direction in VoxelDefsScript.DIRS_4:
		_place_replaceable(data, origin_x, origin_z, world_x + direction.x, base_y + 1, world_z + direction.y, BlockRegistryScript.BLOCK_MANGROVE_ROOTS)
	for y in range(2, 7):
		_place_replaceable(data, origin_x, origin_z, world_x, base_y + y, world_z, BlockRegistryScript.BLOCK_MANGROVE_LOG)
	for dz in range(-2, 3):
		for dx in range(-2, 3):
			if dx * dx + dz * dz <= 5:
				_place(data, origin_x, origin_z, world_x + dx, base_y + 7, world_z + dz, BlockRegistryScript.BLOCK_MANGROVE_LEAVES)
	return base_y + 7


func _stamp_vertical(data: PackedByteArray, origin_x: int, origin_z: int, world_x: int, start_y: int, world_z: int, block_id: int, height: int) -> int:
	for y in range(height):
		_place(data, origin_x, origin_z, world_x, start_y + y, world_z, block_id)
	return start_y + height - 1


func _stamp_boulder(data: PackedByteArray, origin_x: int, origin_z: int, world_x: int, ground_y: int, world_z: int, hash_value: int) -> int:
	var radius: int = 1 + hash_value % 2
	for dz in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			if dx * dx + dz * dz <= radius * radius:
				_place(data, origin_x, origin_z, world_x + dx, ground_y + 1, world_z + dz, BlockRegistryScript.BLOCK_COBBLESTONE)
	return ground_y + 1


func _stamp_fallen_log(data: PackedByteArray, origin_x: int, origin_z: int, world_x: int, ground_y: int, world_z: int, hash_value: int) -> int:
	var direction := Vector2i(1, 0) if hash_value % 2 == 0 else Vector2i(0, 1)
	for step in range(3 + hash_value % 2):
		_place(data, origin_x, origin_z, world_x + direction.x * step, ground_y + 1, world_z + direction.y * step, BlockRegistryScript.BLOCK_LOG)
	return ground_y + 1


## Decoration placement never overwrites terrain, caves, liquids, or another
## feature. Returning the placed y lets callers cheaply retain a valid max_y.
func _place(data: PackedByteArray, origin_x: int, origin_z: int, world_x: int, y: int, world_z: int, block_id: int) -> int:
	var local_x: int = world_x - origin_x
	var local_z: int = world_z - origin_z
	if local_x < 0 or local_x >= VoxelDefsScript.CHUNK_SIZE or local_z < 0 or local_z >= VoxelDefsScript.CHUNK_SIZE or y < 0 or y >= VoxelDefsScript.WORLD_HEIGHT:
		return -1
	var voxel_index: int = _index(local_x, y, local_z)
	if data[voxel_index] == BlockRegistryScript.BLOCK_AIR:
		data[voxel_index] = block_id
		return y
	return -1


func _place_replaceable(data: PackedByteArray, origin_x: int, origin_z: int, world_x: int, y: int, world_z: int, block_id: int) -> int:
	var local_x: int = world_x - origin_x
	var local_z: int = world_z - origin_z
	if local_x < 0 or local_x >= VoxelDefsScript.CHUNK_SIZE or local_z < 0 or local_z >= VoxelDefsScript.CHUNK_SIZE or y < 0 or y >= VoxelDefsScript.WORLD_HEIGHT:
		return -1
	var voxel_index: int = _index(local_x, y, local_z)
	var current: int = data[voxel_index]
	var water: bool = current == BlockRegistryScript.BLOCK_WATER \
		or (current >= BlockRegistryScript.BLOCK_WATER_FLOW_7 and current <= BlockRegistryScript.BLOCK_WATER_FLOW_1)
	if current == BlockRegistryScript.BLOCK_AIR or water:
		data[voxel_index] = block_id
		return y
	return -1


func _apply_edits(data: PackedByteArray, edits: Dictionary, origin_x: int, origin_z: int, max_y: int) -> int:
	for key in edits:
		if not key is Vector3i:
			continue
		var position: Vector3i = key
		var local_x: int = position.x - origin_x
		var local_z: int = position.z - origin_z
		if local_x < 0 or local_x >= VoxelDefsScript.CHUNK_SIZE or local_z < 0 or local_z >= VoxelDefsScript.CHUNK_SIZE or position.y < 0 or position.y >= VoxelDefsScript.WORLD_HEIGHT:
			continue
		var id: int = int(edits[key])
		data[_index(local_x, position.y, local_z)] = id
		if id != BlockRegistryScript.BLOCK_AIR:
			max_y = maxi(max_y, position.y)
	return max_y


func _actual_max_y(data: PackedByteArray, hinted_max_y: int) -> int:
	var start_y: int = clampi(hinted_max_y, 0, VoxelDefsScript.WORLD_HEIGHT - 1)
	for y in range(start_y, -1, -1):
		for local_z in VoxelDefsScript.CHUNK_SIZE:
			for local_x in VoxelDefsScript.CHUNK_SIZE:
				if data[_index(local_x, y, local_z)] != BlockRegistryScript.BLOCK_AIR:
					return y
	return 0


func _surface_height(field: ChunkTerrainData, field_index: int) -> int:
	if config.world_type == WorldGenConfigScript.WORLD_TYPE_FLAT:
		return 4
	return clampi(roundi(field.final_height[field_index]), 2, VoxelDefsScript.WORLD_HEIGHT - 2)


func _index(local_x: int, y: int, local_z: int) -> int:
	return local_x + local_z * VoxelDefsScript.DATA_STRIDE_Z + y * VoxelDefsScript.DATA_STRIDE_Y


func _smoothstep(edge0: float, edge1: float, value: float) -> float:
	var t: float = clampf((value - edge0) / (edge1 - edge0), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)
