## Converts a padded terrain field into deterministic voxel data.
## All work is value-only and safe to run from a chunk worker thread.
class_name VoxelPopulator
extends RefCounted

const ChunkTerrainDataScript = preload("res://world/worldgen/chunk_terrain_data.gd")
const WorldGenConfigScript = preload("res://world/worldgen/world_gen_config.gd")
const BiomeCatalogScript = preload("res://world/worldgen/biome_catalog.gd")
const WorldGenHashScript = preload("res://world/worldgen/world_gen_hash.gd")
const DecorationCatalogScript = preload("res://world/worldgen/decoration_catalog.gd")
const OreCatalogScript = preload("res://world/worldgen/ore_catalog.gd")
const StructureCatalogScript = preload("res://world/worldgen/structure_catalog.gd")
const BlockRegistryScript = preload("res://world/block_registry.gd")
const VoxelDefsScript = preload("res://world/voxel_defs.gd")

const SURFACE_CLEARANCE: int = 3
const FEATURE_CELL_SIZE: int = 8
const FEATURE_HALO: int = 6
# All current stamps, including legacy fallen logs and asymmetric acacia,
# remain within three blocks of their anchor. Keep the wider owner enumeration.
const FEATURE_FOOTPRINT_RADIUS: int = 3
# Grove candidates are six blocks apart and have a maximum horizontal tree
# footprint of three blocks (jungle/spruce). The three-block halo makes every
# touched chunk evaluate the same global candidate; FEATURE_HALO remains the
# wider bound for legacy feature stamps.
const TREE_CELL_SIZE: int = 6
const TREE_FOOTPRINT_RADIUS: int = 3
const TREE_GROVE_CELL_SIZE: int = 48
const TREE_GROVE_SEARCH_RADIUS: int = 1
const GROUND_COVER_CELL_SIZE: int = 8
const GROUND_COVER_RADIUS: int = 4
const CAVE_NETWORK_CELL_SIZE: int = 48
const CAVE_NETWORK_HALO: int = 64
const CAVE_NETWORK_BANDS: int = 5
const CAVE_NETWORK_BASE_Y: int = 14
const CAVE_NETWORK_BAND_STEP: int = 18
const ORE_CELL_SIZE: int = 20
# Aquifers are sparse, overlapping global regions. A region is owned by its
# 48-block cell only for candidate enumeration; every column evaluates the same
# nearby candidates from world coordinates, so loading an adjacent chunk cannot
# create or remove a water table at its border.
const AQUIFER_REGION_CELL_SIZE: int = 48
const AQUIFER_REGION_MIN_RADIUS: int = 22
const AQUIFER_REGION_RADIUS_RANGE: int = 8
const AQUIFER_MIN_WATER_LEVEL: int = 15
const AQUIFER_WATER_LEVEL_RANGE: int = 13
const FLAT_VOXEL_SURFACE_Y: int = 4


## Call-owned decoration cache. VoxelPopulator instances are shared by worker
## jobs, so mutable scratch must stay local to one populate() invocation.
class DecorationGroundScratch:
	const CAPACITY := 512
	const SLOT_MASK := CAPACITY - 1
	var occupied := PackedByteArray()
	var world_xs := PackedInt32Array()
	var world_zs := PackedInt32Array()
	var heights := PackedInt32Array()
	var biomes := PackedInt32Array()

	func _init() -> void:
		occupied.resize(CAPACITY)
		world_xs.resize(CAPACITY)
		world_zs.resize(CAPACITY)
		heights.resize(CAPACITY)
		biomes.resize(CAPACITY)

	func find_slot(world_x: int, world_z: int) -> int:
		var slot: int = ((world_x * 73856093) ^ (world_z * 19349663)) & SLOT_MASK
		for _probe in CAPACITY:
			if occupied[slot] == 0:
				return -1
			if world_xs[slot] == world_x and world_zs[slot] == world_z:
				return slot
			slot = (slot + 1) & SLOT_MASK
		return -1

	func insert(world_x: int, world_z: int, value: Vector2i) -> void:
		var slot: int = ((world_x * 73856093) ^ (world_z * 19349663)) & SLOT_MASK
		for _probe in CAPACITY:
			if occupied[slot] == 0 or (world_xs[slot] == world_x and world_zs[slot] == world_z):
				occupied[slot] = 1
				world_xs[slot] = world_x
				world_zs[slot] = world_z
				heights[slot] = value.x
				biomes[slot] = value.y
				return
			slot = (slot + 1) & SLOT_MASK

	func value_at(slot: int) -> Vector2i:
		return Vector2i(heights[slot], biomes[slot])


## Packed struct-of-arrays replacement for one five-Variant Array per tree.
class TreeCandidates:
	var features := PackedInt32Array()
	var world_xs := PackedInt32Array()
	var ground_ys := PackedInt32Array()
	var world_zs := PackedInt32Array()
	var hashes := PackedInt32Array()

	func append(feature: int, world_x: int, ground_y: int, world_z: int, hash_value: int) -> void:
		features.append(feature)
		world_xs.append(world_x)
		ground_ys.append(ground_y)
		world_zs.append(world_z)
		hashes.append(hash_value)

	func size() -> int:
		return features.size()

	func is_empty() -> bool:
		return features.is_empty()

var config: WorldGenConfig
var biomes: BiomeCatalog
var decorations: DecorationCatalog
var _ore_catalog: OreCatalog
var terrain_sampler: TerrainSampler
var _cave_spaghetti_a: FastNoiseLite
var _cave_spaghetti_b: FastNoiseLite
var _cave_cheese: FastNoiseLite


func _init(config_value: WorldGenConfig, biomes_value: BiomeCatalog, sampler_value: TerrainSampler = null) -> void:
	config = config_value if config_value != null else WorldGenConfigScript.new()
	biomes = biomes_value if biomes_value != null else BiomeCatalogScript.new()
	terrain_sampler = sampler_value
	decorations = DecorationCatalogScript.new(config.worldgen_version)
	# V14 changes stage eligibility, not the legacy ore distribution.
	_ore_catalog = OreCatalogScript.new(mini(config.worldgen_version, OreCatalogScript.LEGACY_VERSION_MAX))
	_cave_spaghetti_a = _make_cave_noise(1701, 0.018, 2)
	_cave_spaghetti_b = _make_cave_noise(1877, 0.015, 2)
	_cave_cheese = _make_cave_noise(1999, 0.009, 3)


## Returns {"data": PackedByteArray, "max_y": int}. Edits deliberately run
## after every generated stage so a saved player block is always authoritative.
func populate(chunk_pos: Vector2i, field: ChunkTerrainData, edits: Dictionary, full_detail: bool = true) -> Dictionary:
	var data := PackedByteArray()
	data.resize(VoxelDefsScript.CHUNK_AREA * VoxelDefsScript.WORLD_HEIGHT)
	var origin_x: int = chunk_pos.x * VoxelDefsScript.CHUNK_SIZE
	var origin_z: int = chunk_pos.y * VoxelDefsScript.CHUNK_SIZE
	var max_y := _fill_base_and_surface(data, field)
	if full_detail:
		_decorate_floor_patches(data, field, origin_x, origin_z)
	if full_detail and config.world_type != WorldGenConfigScript.WORLD_TYPE_FLAT and config.cave_density > 0.0:
		_carve_noise_caves(data, field, origin_x, origin_z)
		_carve_cave_network(data, field, origin_x, origin_z)
		_carve_cave_entrances(data, field, origin_x, origin_z)
		_carve_caverns(data, field, origin_x, origin_z)
		_fill_underground_liquids(data, field, origin_x, origin_z)
		_place_ore_veins(data, origin_x, origin_z)
		_place_geodes(data, field, origin_x, origin_z)
		_decorate_caves(data, field, origin_x, origin_z)
	elif full_detail and config.world_type != WorldGenConfigScript.WORLD_TYPE_FLAT \
			and config.worldgen_version >= WorldGenConfigScript.CAVE_INDEPENDENT_ORES_VERSION:
		# Preserve the cave-enabled stage order and pre-v14 cave-free worlds.
		_place_ore_veins(data, origin_x, origin_z)
	if full_detail and config.decoration_density > 0.0:
		var decoration_scratch := DecorationGroundScratch.new()
		max_y = _decorate(data, field, origin_x, origin_z, max_y, decoration_scratch)
		max_y = _decorate_underwater(data, field, origin_x, origin_z, max_y, decoration_scratch)
	max_y = maxi(max_y, _place_region_structures(data, field, origin_x, origin_z))
	max_y = _apply_edits(data, edits, origin_x, origin_z, max_y)
	return {"data": data, "max_y": _actual_max_y(data, max_y)}


## Compact LOD population: the distance mesh only needs each column's top/sub
## block and water surface, so no 192-block data array is allocated; caves,
## buried ores, and ground flora are skipped. Real tree crowns from in-field anchors
## are baked into the compact columns so forests do not vanish past the
## full-detail ring. Far chunks cost kilobytes instead of ~50 KB and stream
## several times faster. Player edits are intentionally ignored here: LOD
## chunks are beyond interaction range and become full detail before the
## player can reach them.
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
	var origin_x: int = chunk_pos.x * VoxelDefsScript.CHUNK_SIZE
	var origin_z: int = chunk_pos.y * VoxelDefsScript.CHUNK_SIZE
	var max_y := 0
	for local_z in VoxelDefsScript.CHUNK_SIZE:
		for local_x in VoxelDefsScript.CHUNK_SIZE:
			var field_index: int = ChunkTerrainDataScript.cell_index(local_x, local_z)
			var column: int = local_x + local_z * VoxelDefsScript.DATA_STRIDE_Z
			var surface_y: int = _surface_height(field, field_index)
			var river: float = field.river[field_index]
			var is_river: bool = config.world_type != WorldGenConfigScript.WORLD_TYPE_FLAT \
				and river >= WorldGenConfigScript.RIVER_CHANNEL_THRESHOLD and surface_y < VoxelDefsScript.SEA_LEVEL
			var column_water_y := _column_water_y(field, field_index, surface_y)
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
	_apply_lod_floor_patches(solid_y, solid_id, field, origin_x, origin_z)
	if config.worldgen_version >= WorldGenConfigScript.CAVE_INDEPENDENT_ORES_VERSION \
			and config.world_type != WorldGenConfigScript.WORLD_TYPE_FLAT:
		_place_ore_veins(PackedByteArray(), origin_x, origin_z, solid_y, solid_id, sub_id)
	var terrain_solid_y: PackedInt32Array = solid_y.duplicate()
	var terrain_solid_id: PackedByteArray = solid_id.duplicate()
	var terrain_sub_id: PackedByteArray = sub_id.duplicate()
	max_y = maxi(max_y, _apply_lod_scrub(solid_y, solid_id, sub_id, water_y, field, origin_x, origin_z))
	max_y = maxi(max_y, _apply_lod_canopies(solid_y, solid_id, sub_id, water_y, field, origin_x, origin_z))
	max_y = maxi(max_y, _apply_lod_region_structures(solid_y, solid_id, sub_id, water_y,
		field, origin_x, origin_z, terrain_solid_y, terrain_solid_id, terrain_sub_id))
	return {
		"solid_y": solid_y,
		"solid_id": solid_id,
		"sub_id": sub_id,
		"water_y": water_y,
		"water_level": water_level,
		"max_y": max_y,
	}


## Bakes real tree crowns into compact columns using only anchors inside the
## padded field, so distance chunks show actual trees. Shapes come from the
## same stamp functions as full chunks; only the expensive site-validity probes
## are relaxed, since they leave the field and re-enter the sampler. The top
## two tree blocks become the column's solid/sub pair so side faces read as
## foliage instead of dirt.
func _apply_lod_canopies(solid_y: PackedInt32Array, solid_id: PackedByteArray, sub_id: PackedByteArray, water_y: PackedInt32Array, field: ChunkTerrainData, origin_x: int, origin_z: int) -> int:
	var trees := _collect_trees(field, origin_x, origin_z, DecorationGroundScratch.new(), true)
	if trees.is_empty():
		return 0
	var buffer := PackedByteArray()
	buffer.resize(VoxelDefsScript.CHUNK_AREA * VoxelDefsScript.WORLD_HEIGHT)
	var tree_max_y := 0
	for tree_index in trees.size():
		tree_max_y = maxi(tree_max_y, _stamp_feature(
			buffer, origin_x, origin_z, trees.world_xs[tree_index], trees.ground_ys[tree_index],
			trees.world_zs[tree_index], trees.features[tree_index], trees.hashes[tree_index]))
	var top_y := PackedInt32Array()
	var top_id := PackedByteArray()
	var second_id := PackedByteArray()
	top_y.resize(VoxelDefsScript.CHUNK_AREA)
	top_id.resize(VoxelDefsScript.CHUNK_AREA)
	second_id.resize(VoxelDefsScript.CHUNK_AREA)
	top_y.fill(-1)
	var stride_y: int = VoxelDefsScript.DATA_STRIDE_Y
	for y in range(tree_max_y + 1):
		var base: int = y * stride_y
		for column in VoxelDefsScript.CHUNK_AREA:
			var block_id: int = buffer[base + column]
			if block_id == BlockRegistryScript.BLOCK_AIR:
				continue
			second_id[column] = top_id[column]
			top_id[column] = block_id
			top_y[column] = y
	var max_y := 0
	for column in VoxelDefsScript.CHUNK_AREA:
		if top_y[column] <= solid_y[column] or top_y[column] <= water_y[column]:
			continue
		solid_y[column] = top_y[column]
		solid_id[column] = top_id[column]
		sub_id[column] = second_id[column] if second_id[column] != BlockRegistryScript.BLOCK_AIR else top_id[column]
		max_y = maxi(max_y, top_y[column])
	return max_y


## Region structures are a separate, sparse feature tier. Each 160-block owner
## cell supplies one candidate; the fixed structure bounding box expands the
## owner range so every overlapping chunk independently makes the same stamp.
## The terrain-only site test deliberately reads the sampler/scratch rather than
## generated data, which avoids generation-order dependence at chunk borders.
func _place_region_structures(data: PackedByteArray, field: ChunkTerrainData, origin_x: int, origin_z: int) -> int:
	var structures := _accepted_region_structures(field, origin_x, origin_z, DecorationGroundScratch.new())
	var max_y := 0
	for entry in structures:
		var candidate: StructureCatalog.Candidate = entry[0]
		var ground_y: int = int(entry[1])
		_clear_structure_volume(data, origin_x, origin_z, candidate.anchor, ground_y)
		for offset_z in range(-StructureCatalogScript.HORIZONTAL_HALO, StructureCatalogScript.HORIZONTAL_HALO + 1):
			for offset_x in range(-StructureCatalogScript.HORIZONTAL_HALO, StructureCatalogScript.HORIZONTAL_HALO + 1):
				for local_y in range(1, StructureCatalogScript.max_height(candidate.kind) + 1):
					var block_id: int = StructureCatalogScript.block_at(candidate.kind, candidate.orientation,
						offset_x, local_y, offset_z)
					if block_id == BlockRegistryScript.BLOCK_AIR:
						continue
					_set_structure_block(data, origin_x, origin_z, candidate.anchor.x + offset_x,
						ground_y + local_y, candidate.anchor.y + offset_z, block_id)
		max_y = maxi(max_y, ground_y + StructureCatalogScript.max_height(candidate.kind))
	return max_y


## Compact chunks carry the exact region-structure top columns. The clearing
## reset is equally important: it removes a pre-existing compact tree canopy
## from a POI footprint just as the full stamp clears its voxel volume.
func _apply_lod_region_structures(solid_y: PackedInt32Array, solid_id: PackedByteArray,
		sub_id: PackedByteArray, water_y: PackedInt32Array, field: ChunkTerrainData,
		origin_x: int, origin_z: int, terrain_solid_y: PackedInt32Array,
		terrain_solid_id: PackedByteArray, terrain_sub_id: PackedByteArray) -> int:
	var structures := _accepted_region_structures(field, origin_x, origin_z, DecorationGroundScratch.new())
	var max_y := 0
	for entry in structures:
		var candidate: StructureCatalog.Candidate = entry[0]
		var ground_y: int = int(entry[1])
		for offset_z in range(-StructureCatalogScript.HORIZONTAL_HALO, StructureCatalogScript.HORIZONTAL_HALO + 1):
			var local_z: int = candidate.anchor.y + offset_z - origin_z
			if local_z < 0 or local_z >= VoxelDefsScript.CHUNK_SIZE:
				continue
			for offset_x in range(-StructureCatalogScript.HORIZONTAL_HALO, StructureCatalogScript.HORIZONTAL_HALO + 1):
				var local_x: int = candidate.anchor.x + offset_x - origin_x
				if local_x < 0 or local_x >= VoxelDefsScript.CHUNK_SIZE:
					continue
				var column: int = local_x + local_z * VoxelDefsScript.DATA_STRIDE_Z
				solid_y[column] = terrain_solid_y[column]
				solid_id[column] = terrain_solid_id[column]
				sub_id[column] = terrain_sub_id[column]
				# Accepted structures are above the water line; leave a deterministic
				# safety reset in case a future terrain rule adds a shallow water cap.
				if water_y[column] > terrain_solid_y[column]:
					water_y[column] = -1
				var top_y: int = -1
				var top_id: int = BlockRegistryScript.BLOCK_AIR
				for local_y in range(1, StructureCatalogScript.max_height(candidate.kind) + 1):
					var block_id: int = StructureCatalogScript.block_at(candidate.kind, candidate.orientation,
						offset_x, local_y, offset_z)
					# Compact columns intentionally omit cross blocks, matching the
					# full-detail LOD scan (a torch is light/decoration, not terrain).
					if block_id != BlockRegistryScript.BLOCK_AIR and block_id != BlockRegistryScript.BLOCK_TORCH:
						top_y = ground_y + local_y
						top_id = block_id
				if top_y < 0:
					continue
				solid_y[column] = top_y
				solid_id[column] = top_id
				var below_id: int = StructureCatalogScript.block_at(candidate.kind, candidate.orientation,
					offset_x, top_y - ground_y - 1, offset_z)
				sub_id[column] = terrain_solid_id[column] if below_id == BlockRegistryScript.BLOCK_AIR else below_id
				max_y = maxi(max_y, top_y)
	return max_y


func _accepted_region_structures(field: ChunkTerrainData, origin_x: int, origin_z: int,
		ground_scratch: DecorationGroundScratch) -> Array:
	var accepted: Array = []
	if not config.region_structures or config.worldgen_version < WorldGenConfigScript.VARIANT_WORLDGEN_VERSION \
			or terrain_sampler == null:
		return accepted
	var first_x: int = WorldGenHashScript.floor_div(origin_x - StructureCatalogScript.HORIZONTAL_HALO,
		StructureCatalogScript.OWNER_CELL_SIZE)
	var last_x: int = WorldGenHashScript.floor_div(origin_x + VoxelDefsScript.CHUNK_SIZE - 1
		+ StructureCatalogScript.HORIZONTAL_HALO, StructureCatalogScript.OWNER_CELL_SIZE)
	var first_z: int = WorldGenHashScript.floor_div(origin_z - StructureCatalogScript.HORIZONTAL_HALO,
		StructureCatalogScript.OWNER_CELL_SIZE)
	var last_z: int = WorldGenHashScript.floor_div(origin_z + VoxelDefsScript.CHUNK_SIZE - 1
		+ StructureCatalogScript.HORIZONTAL_HALO, StructureCatalogScript.OWNER_CELL_SIZE)
	for owner_z in range(first_z, last_z + 1):
		for owner_x in range(first_x, last_x + 1):
			var candidate: StructureCatalog.Candidate = StructureCatalogScript.candidate_for(config.seed, owner_x, owner_z)
			if candidate == null:
				continue
			if not _footprint_intersects_chunk(candidate.anchor.x, candidate.anchor.y,
					StructureCatalogScript.HORIZONTAL_HALO, origin_x, origin_z):
				continue
			var ground := _cached_decoration_ground(field, candidate.anchor.x, candidate.anchor.y, ground_scratch)
			if _region_structure_site_is_valid(field, ground_scratch, candidate, ground.x):
				accepted.append([candidate, ground.x])
	return accepted


func _region_structure_site_is_valid(field: ChunkTerrainData, ground_scratch: DecorationGroundScratch,
		candidate: StructureCatalog.Candidate, ground_y: int) -> bool:
	if ground_y <= VoxelDefsScript.SEA_LEVEL + 2 \
			or ground_y + StructureCatalogScript.CLEAR_HEIGHT >= VoxelDefsScript.WORLD_HEIGHT:
		return false
	var radius: int = StructureCatalogScript.clear_radius(candidate.kind)
	for offset_z in range(-radius, radius + 1):
		for offset_x in range(-radius, radius + 1):
			var sample := _cached_decoration_ground(field, candidate.anchor.x + offset_x,
				candidate.anchor.y + offset_z, ground_scratch)
			if sample.x != ground_y or biomes.is_ocean_biome(sample.y) \
					or sample.y == BiomeCatalogScript.RIVER or sample.y == BiomeCatalogScript.SWAMP:
				return false
			# Entrances are the one cave stage allowed to reach the surface. Reject
			# their small immutable exclusion so a structure foundation never spans
			# an entrance and full/compact columns retain the same support.
			if _tree_root_is_near_cave_entrance(candidate.anchor.x + offset_x,
					candidate.anchor.y + offset_z):
				return false
	return true


func _clear_structure_volume(data: PackedByteArray, origin_x: int, origin_z: int,
		anchor: Vector2i, ground_y: int) -> void:
	for offset_z in range(-StructureCatalogScript.HORIZONTAL_HALO, StructureCatalogScript.HORIZONTAL_HALO + 1):
		var local_z: int = anchor.y + offset_z - origin_z
		if local_z < 0 or local_z >= VoxelDefsScript.CHUNK_SIZE:
			continue
		for offset_x in range(-StructureCatalogScript.HORIZONTAL_HALO, StructureCatalogScript.HORIZONTAL_HALO + 1):
			var local_x: int = anchor.x + offset_x - origin_x
			if local_x < 0 or local_x >= VoxelDefsScript.CHUNK_SIZE:
				continue
			for y in range(ground_y + 1, ground_y + StructureCatalogScript.CLEAR_HEIGHT + 1):
				data[_index(local_x, y, local_z)] = BlockRegistryScript.BLOCK_AIR


func _set_structure_block(data: PackedByteArray, origin_x: int, origin_z: int,
		world_x: int, y: int, world_z: int, block_id: int) -> void:
	var local_x: int = world_x - origin_x
	var local_z: int = world_z - origin_z
	if local_x < 0 or local_x >= VoxelDefsScript.CHUNK_SIZE or local_z < 0 \
			or local_z >= VoxelDefsScript.CHUNK_SIZE or y < 0 or y >= VoxelDefsScript.WORLD_HEIGHT:
		return
	data[_index(local_x, y, local_z)] = block_id


func _fill_base_and_surface(data: PackedByteArray, field: ChunkTerrainData) -> int:
	var max_y := 0
	for local_z in VoxelDefsScript.CHUNK_SIZE:
		for local_x in VoxelDefsScript.CHUNK_SIZE:
			var field_index: int = ChunkTerrainDataScript.cell_index(local_x, local_z)
			var surface_y: int = _surface_height(field, field_index)
			var river: float = field.river[field_index]
			var is_river: bool = config.world_type != WorldGenConfigScript.WORLD_TYPE_FLAT \
				and river >= WorldGenConfigScript.RIVER_CHANNEL_THRESHOLD and surface_y < VoxelDefsScript.SEA_LEVEL
			var water_y := _column_water_y(field, field_index, surface_y)
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


func _column_water_y(field: ChunkTerrainData, field_index: int, surface_y: int) -> int:
	# Flat voxel terrain sits below sea level but must remain dry.
	if config.world_type == WorldGenConfigScript.WORLD_TYPE_FLAT:
		return -1
	var inland_water: int = field.inland_water_y[field_index]
	if inland_water > surface_y:
		return inland_water
	return VoxelDefsScript.SEA_LEVEL if surface_y < VoxelDefsScript.SEA_LEVEL else -1


func _apply_surface_rule(data: PackedByteArray, field: ChunkTerrainData, local_x: int, local_z: int, surface_y: int, water_y: int, is_river: bool) -> void:
	var field_index: int = ChunkTerrainDataScript.cell_index(local_x, local_z)
	var world_x := field.world_x(local_x)
	var world_z := field.world_z(local_z)
	var values := _surface_rule_values(field, field_index, surface_y, water_y, is_river, world_x, world_z)
	var biome: int = int(field.dominant_biome[field_index])
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


## Surface blankets stay coherent: the sampler's dominant biome changes only in
## broad ecotone patches, never from a per-column hash. Shared by full and LOD.
func _surface_rule_values(field: ChunkTerrainData, field_index: int, surface_y: int, water_y: int, is_river: bool, world_x: int, world_z: int) -> Vector3i:
	var biome: int = int(field.dominant_biome[field_index])
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
		sub = biomes.seabed_subsurface(biome, water_depth)
		depth = biomes.seabed_depth(water_depth)
		# Abyssal ooze is interrupted by exposed gravel banks so the deep floor
		# does not read as one flat sheet.
		if biome == BiomeCatalogScript.DEEP_OCEAN and depth > 6 \
				and WorldGenHashScript.hash_2d(config.seed + 1409, world_x, world_z) % 6 == 0:
			top = BlockRegistryScript.BLOCK_GRAVEL
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


## Minecraft-style noise caves: the intersection of two continuous 3D ridges
## forms spaghetti tunnels that do not have feature endpoints or chunk seams.
## A lower-frequency "cheese" field opens occasional broad chambers. This is
## deliberately combined with the graph below: the field supplies organic
## local complexity while the graph guarantees routes that continue forever.
func _carve_noise_caves(data: PackedByteArray, field: ChunkTerrainData, origin_x: int, origin_z: int) -> void:
	var tunnel_width := clampf(0.055 + 0.035 * config.cave_density, 0.04, 0.16)
	var chamber_threshold := clampf(0.62 - 0.07 * config.cave_density, 0.44, 0.62)
	var tunnel_limits := PackedFloat64Array()
	var chamber_limits := PackedFloat64Array()
	tunnel_limits.resize(VoxelDefsScript.SEA_LEVEL + 53)
	chamber_limits.resize(VoxelDefsScript.SEA_LEVEL + 53)
	for y in range(4, tunnel_limits.size()):
		tunnel_limits[y] = tunnel_width * clampf(float(VoxelDefsScript.SEA_LEVEL + 52 - y) / 24.0, 0.35, 1.0)
		chamber_limits[y] = chamber_threshold + clampf(float(y - 12) / 72.0, 0.0, 1.0) * 0.10
	for local_z in VoxelDefsScript.CHUNK_SIZE:
		var world_z := origin_z + local_z
		for local_x in VoxelDefsScript.CHUNK_SIZE:
			var field_index := ChunkTerrainDataScript.cell_index(local_x, local_z)
			var surface_limit := _surface_height(field, field_index) - SURFACE_CLEARANCE - 1
			if field.river[field_index] >= WorldGenConfigScript.RIVER_CHANNEL_THRESHOLD:
				surface_limit = mini(surface_limit,
					VoxelDefsScript.SEA_LEVEL - WorldGenConfigScript.RIVER_UNDERGROUND_CLEARANCE)
			var last_y := mini(surface_limit, VoxelDefsScript.SEA_LEVEL + 52)
			if last_y < 4:
				continue
			var world_x := origin_x + local_x
			for y in range(4, last_y + 1):
				var voxel_index := _index(local_x, y, local_z)
				if not _is_carvable_stone(data[voxel_index]):
					continue
				var ridge_a := absf(_cave_spaghetti_a.get_noise_3d(world_x, y, world_z))
				# Noise is immutable: skip the second ridge when the first already
				# rejects the tunnel, and skip cheese when a tunnel already carves.
				var spaghetti := ridge_a < tunnel_limits[y] \
					and absf(_cave_spaghetti_b.get_noise_3d(world_x, y, world_z)) < tunnel_limits[y]
				if spaghetti or _cave_cheese.get_noise_3d(world_x, y, world_z) > chamber_limits[y]:
					data[voxel_index] = BlockRegistryScript.BLOCK_AIR


## A deterministic global graph supplies the long-distance structure missing
## from pure random walks. Every node owns one east/south edge, so following a
## trunk can never reach a dead end; optional cross-links, vertical connectors,
## curved midpoints, and node chambers keep the lattice from reading as a grid.
func _carve_cave_network(data: PackedByteArray, field: ChunkTerrainData, origin_x: int, origin_z: int) -> void:
	var first_x := WorldGenHashScript.floor_div(origin_x - CAVE_NETWORK_HALO, CAVE_NETWORK_CELL_SIZE)
	var last_x := WorldGenHashScript.floor_div(origin_x + VoxelDefsScript.CHUNK_SIZE - 1 + CAVE_NETWORK_HALO, CAVE_NETWORK_CELL_SIZE)
	var first_z := WorldGenHashScript.floor_div(origin_z - CAVE_NETWORK_HALO, CAVE_NETWORK_CELL_SIZE)
	var last_z := WorldGenHashScript.floor_div(origin_z + VoxelDefsScript.CHUNK_SIZE - 1 + CAVE_NETWORK_HALO, CAVE_NETWORK_CELL_SIZE)
	for cell_z in range(first_z, last_z + 1):
		for cell_x in range(first_x, last_x + 1):
			for band in CAVE_NETWORK_BANDS:
				var node := _cave_network_node(cell_x, band, cell_z)
				var route_hash := WorldGenHashScript.hash_3d(config.seed + 719, cell_x, band, cell_z)
				var primary_offset := _cave_primary_offset(cell_x, band, cell_z)
				_stamp_cave_network_edge(data, field, node,
					_cave_network_node(cell_x + primary_offset.x, band, cell_z + primary_offset.y), route_hash)
				if float(route_hash % 1000) / 1000.0 < minf(0.72, 0.24 * config.cave_density):
					var branch_offset := Vector2i(0, 1) if primary_offset.x != 0 else Vector2i(1, 0)
					_stamp_cave_network_edge(data, field, node,
						_cave_network_node(cell_x + branch_offset.x, band, cell_z + branch_offset.y), route_hash + 43)
				var connector_band := WorldGenHashScript.hash_2d(config.seed + 757, cell_x, cell_z) % (CAVE_NETWORK_BANDS - 1)
				if band == connector_band:
					_stamp_cave_network_edge(data, field, node, _cave_network_node(cell_x, band + 1, cell_z), route_hash + 89)
				if float((route_hash / 97) % 1000) / 1000.0 < minf(0.30, 0.10 * config.cave_density):
					_carve_ellipsoid(data, field, node, 6 + route_hash % 5, 3 + (route_hash / 7) % 4, 6 + (route_hash / 17) % 5)


func _cave_network_node(cell_x: int, band: int, cell_z: int) -> Vector3i:
	var node_hash := WorldGenHashScript.hash_3d(config.seed + 701, cell_x, band, cell_z)
	return Vector3i(
		cell_x * CAVE_NETWORK_CELL_SIZE + 8 + node_hash % (CAVE_NETWORK_CELL_SIZE - 16),
		clampi(CAVE_NETWORK_BASE_Y + band * CAVE_NETWORK_BAND_STEP + ((node_hash / 47) % 11) - 5, 5, VoxelDefsScript.SEA_LEVEL + 58),
		cell_z * CAVE_NETWORK_CELL_SIZE + 8 + (node_hash / 131) % (CAVE_NETWORK_CELL_SIZE - 16))


func _cave_primary_offset(cell_x: int, band: int, cell_z: int) -> Vector2i:
	var route_hash := WorldGenHashScript.hash_3d(config.seed + 719, cell_x, band, cell_z)
	return Vector2i(1, 0) if (route_hash & 1) == 0 else Vector2i(0, 1)


func _stamp_cave_network_edge(data: PackedByteArray, field: ChunkTerrainData, start: Vector3i, finish: Vector3i, route_hash: int) -> void:
	var midpoint := Vector3i((start.x + finish.x) / 2, (start.y + finish.y) / 2, (start.z + finish.z) / 2)
	var bend := ((route_hash / 13) % 19) - 9
	if absi(finish.x - start.x) >= absi(finish.z - start.z):
		midpoint.z += bend
	else:
		midpoint.x += bend
	midpoint.y = clampi(midpoint.y + ((route_hash / 251) % 11) - 5, 5, VoxelDefsScript.SEA_LEVEL + 58)
	var base_radius := 1 if config.cave_density < 0.6 else (3 if config.cave_density > 1.75 else 2)
	var radius := base_radius + route_hash % 2
	_stamp_tunnel(data, field, start, midpoint, radius)
	_stamp_tunnel(data, field, midpoint, finish, base_radius + (route_hash / 17) % 2)


func _make_cave_noise(seed_salt: int, frequency: float, octaves: int) -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = frequency
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = octaves
	noise.fractal_lacunarity = 2.0
	noise.fractal_gain = 0.5
	noise.seed = WorldGenHashScript.hash_1d(config.seed, seed_salt)
	return noise


func _is_carvable_stone(block_id: int) -> bool:
	return block_id == BlockRegistryScript.BLOCK_STONE or block_id == BlockRegistryScript.BLOCK_COBBLESTONE


func _stamp_tunnel(data: PackedByteArray, field: ChunkTerrainData, start: Vector3i, finish: Vector3i, radius: int) -> void:
	var distance: int = maxi(maxi(absi(finish.x - start.x), absi(finish.y - start.y)), absi(finish.z - start.z))
	for step in range(distance + 1):
		var point := Vector3i(
			start.x + (finish.x - start.x) * step / maxi(1, distance),
			start.y + (finish.y - start.y) * step / maxi(1, distance),
			start.z + (finish.z - start.z) * step / maxi(1, distance)
		)
		_carve_ellipsoid(data, field, point, radius, radius, radius)


## Sparse global-cell entrances descend into a canonical graph node. The mouth
## alone may cut surface blocks; its continuation uses normal cave clearance.
## Every touched chunk reproduces the route, independent of generation order.
func _carve_cave_entrances(data: PackedByteArray, field: ChunkTerrainData, origin_x: int, origin_z: int) -> void:
	if terrain_sampler == null:
		return
	const entrance_cell_size := 64
	const entrance_halo := CAVE_NETWORK_HALO
	var first_x := WorldGenHashScript.floor_div(origin_x - entrance_halo, entrance_cell_size)
	var last_x := WorldGenHashScript.floor_div(origin_x + VoxelDefsScript.CHUNK_SIZE - 1 + entrance_halo, entrance_cell_size)
	var first_z := WorldGenHashScript.floor_div(origin_z - entrance_halo, entrance_cell_size)
	var last_z := WorldGenHashScript.floor_div(origin_z + VoxelDefsScript.CHUNK_SIZE - 1 + entrance_halo, entrance_cell_size)
	for cell_z in range(first_z, last_z + 1):
		for cell_x in range(first_x, last_x + 1):
			var hash_value := WorldGenHashScript.hash_2d(config.seed + 773, cell_x, cell_z)
			if float(hash_value % 1000) / 1000.0 >= minf(0.45, 0.18 * config.cave_density):
				continue
			var world_x := cell_x * entrance_cell_size + 8 + hash_value % 48
			var world_z := cell_z * entrance_cell_size + 8 + (hash_value / 53) % 48
			var ground := terrain_sampler.sample_decoration_ground(world_x, world_z)
			if biomes.is_ocean_biome(ground.y) or ground.y in [BiomeCatalogScript.BEACH, BiomeCatalogScript.RIVER, BiomeCatalogScript.SWAMP]:
				continue
			var direction_x := -1 if ((hash_value / 101) & 1) == 0 else 1
			var direction_z := -1 if ((hash_value / 211) & 1) == 0 else 1
			var start := Vector3i(world_x, ground.x + 1, world_z)
			var mouth_finish := Vector3i(world_x + direction_x * 8, ground.x - 12, world_z + direction_z * 8)
			_stamp_entrance_tunnel(data, field, start, mouth_finish)
			var network_cell_x := WorldGenHashScript.floor_div(mouth_finish.x, CAVE_NETWORK_CELL_SIZE)
			var network_cell_z := WorldGenHashScript.floor_div(mouth_finish.z, CAVE_NETWORK_CELL_SIZE)
			var target_band := clampi(WorldGenHashScript.floor_div(ground.x - 26 - CAVE_NETWORK_BASE_Y, CAVE_NETWORK_BAND_STEP), 0, CAVE_NETWORK_BANDS - 1)
			var network_node := _cave_network_node(network_cell_x, target_band, network_cell_z)
			_stamp_tunnel(data, field, mouth_finish, network_node, 2 + hash_value % 2)


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
			if field.river[field_index] >= WorldGenConfigScript.RIVER_CHANNEL_THRESHOLD:
				column_last_y = mini(column_last_y,
					VoxelDefsScript.SEA_LEVEL - WorldGenConfigScript.RIVER_UNDERGROUND_CLEARANCE)
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
	if config.worldgen_version <= 10:
		_fill_legacy_aquifer(data, field, origin_x, origin_z)
	else:
		for local_z in VoxelDefsScript.CHUNK_SIZE:
			var world_z: int = origin_z + local_z
			for local_x in VoxelDefsScript.CHUNK_SIZE:
				var world_x: int = origin_x + local_x
				var water_level: int = _aquifer_water_level_at(world_x, world_z)
				if water_level < 4:
					continue
				var field_index: int = ChunkTerrainDataScript.cell_index(local_x, local_z)
				var top: int = _surface_height(field, field_index)
				# Keep the existing underground clearance and match cave carving's
				# river ceiling, so an aquifer can never turn a protected channel or
				# its banks into a generated surface-water source.
				var protected_ceiling: int = top - SURFACE_CLEARANCE
				if field.river[field_index] >= WorldGenConfigScript.RIVER_CHANNEL_THRESHOLD:
					protected_ceiling = mini(protected_ceiling,
						VoxelDefsScript.SEA_LEVEL - WorldGenConfigScript.RIVER_UNDERGROUND_CLEARANCE)
				for y in range(4, mini(water_level, protected_ceiling) + 1):
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


## V1-v10 worlds used one independently-selected aquifer per chunk. Preserve
## that exact layout because untouched saved chunks regenerate from their
## persisted worldgen version.
func _fill_legacy_aquifer(data: PackedByteArray, field: ChunkTerrainData,
		origin_x: int, origin_z: int) -> void:
	var aquifer_cell_x := WorldGenHashScript.floor_div(origin_x, VoxelDefsScript.CHUNK_SIZE)
	var aquifer_cell_z := WorldGenHashScript.floor_div(origin_z, VoxelDefsScript.CHUNK_SIZE)
	var aquifer_hash := WorldGenHashScript.hash_2d(config.seed + 907, aquifer_cell_x, aquifer_cell_z)
	if aquifer_hash % 11 != 0:
		return
	var water_level := 15 + (aquifer_hash / 31) % 13
	for local_z in VoxelDefsScript.CHUNK_SIZE:
		for local_x in VoxelDefsScript.CHUNK_SIZE:
			var field_index: int = ChunkTerrainDataScript.cell_index(local_x, local_z)
			var top: int = _surface_height(field, field_index)
			for y in range(4, mini(water_level, top - SURFACE_CLEARANCE) + 1):
				var voxel_index: int = _index(local_x, y, local_z)
				if data[voxel_index] == BlockRegistryScript.BLOCK_AIR:
					data[voxel_index] = BlockRegistryScript.BLOCK_WATER


## Returns the table for the strongest nearby global aquifer region, or -1.
## The lookup deliberately has no chunk coordinate: regions are independently
## reproduced by every chunk they overlap, regardless of worker timing/order.
func _aquifer_water_level_at(world_x: int, world_z: int) -> int:
	var owner_x: int = WorldGenHashScript.floor_div(world_x, AQUIFER_REGION_CELL_SIZE)
	var owner_z: int = WorldGenHashScript.floor_div(world_z, AQUIFER_REGION_CELL_SIZE)
	var water_level := -1
	for cell_z in range(owner_z - 1, owner_z + 2):
		for cell_x in range(owner_x - 1, owner_x + 2):
			var region_hash: int = WorldGenHashScript.hash_2d(config.seed + 907, cell_x, cell_z)
			if region_hash % 11 != 0:
				continue
			var center_x: int = cell_x * AQUIFER_REGION_CELL_SIZE + 8 + region_hash % 32
			var center_z: int = cell_z * AQUIFER_REGION_CELL_SIZE + 8 + (region_hash / 31) % 32
			var radius: int = AQUIFER_REGION_MIN_RADIUS + (region_hash / 61) % AQUIFER_REGION_RADIUS_RANGE
			var dx: int = world_x - center_x
			var dz: int = world_z - center_z
			if dx * dx + dz * dz > radius * radius:
				continue
			water_level = maxi(water_level, AQUIFER_MIN_WATER_LEVEL + (region_hash / 97) % AQUIFER_WATER_LEVEL_RANGE)
	return water_level


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
			if config.worldgen_version <= 10:
				var legacy_index: int = _index(local_x, center.y, local_z)
				if data[legacy_index] == BlockRegistryScript.BLOCK_AIR:
					data[legacy_index] = BlockRegistryScript.BLOCK_LAVA
				continue
			# V11 lakes are shallow supported basins rather than one-voxel discs.
			# Their surface stays level while the interior gains up to three cells
			# of depth; a solid floor is mandatory so lava never floats in a cavern.
			var radial: float = sqrt(float(dx * dx + dz * dz)) / float(maxi(radius, 1))
			var depth: int = 1 + roundi((1.0 - clampf(radial, 0.0, 1.0)) * 2.0)
			var bottom_y: int = center.y - depth + 1
			if bottom_y <= 1:
				continue
			var support: int = data[_index(local_x, bottom_y - 1, local_z)]
			if support == BlockRegistryScript.BLOCK_AIR or support == BlockRegistryScript.BLOCK_WATER:
				continue
			var basin_clear := true
			for y in range(bottom_y, center.y + 1):
				if data[_index(local_x, y, local_z)] != BlockRegistryScript.BLOCK_AIR:
					basin_clear = false
					break
			if not basin_clear:
				continue
			for y in range(bottom_y, center.y + 1):
				data[_index(local_x, y, local_z)] = BlockRegistryScript.BLOCK_LAVA


func _place_ore_veins(data: PackedByteArray, origin_x: int, origin_z: int,
		solid_y: PackedInt32Array = PackedInt32Array(), solid_id: PackedByteArray = PackedByteArray(),
		sub_id: PackedByteArray = PackedByteArray()) -> void:
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
				_stamp_ore_segment(data, origin_x, origin_z, start, finish, ore, solid_y, solid_id, sub_id)


## Sparse deterministic cave details. A global four-block lattice samples open
## chambers instead of scanning every underground voxel. The nearest floor and
## ceiling drive paired dripstone, columns, biome materials/vegetation, and
## shallow pools; all writes remain inside the current chunk-owned array.
func _decorate_caves(data: PackedByteArray, field: ChunkTerrainData, origin_x: int, origin_z: int) -> void:
	for local_z in range(2, VoxelDefsScript.CHUNK_SIZE, 4):
		for local_x in range(2, VoxelDefsScript.CHUNK_SIZE, 4):
			var world_x := origin_x + local_x
			var world_z := origin_z + local_z
			var field_index := ChunkTerrainDataScript.cell_index(local_x, local_z)
			# Cave dressing must remain below the protected surface band. Without
			# this guard, an outdoor air sample can find the terrain (or ocean
			# water) beneath it and mistake that one-sided boundary for a cavern,
			# producing lattice rows of moss and dripstone across the landscape.
			var underground_limit := _surface_height(field, field_index) - SURFACE_CLEARANCE - 1
			for y in range(6, VoxelDefsScript.SEA_LEVEL + 32, 4):
				if y > underground_limit:
					continue
				var air_index := _index(local_x, y, local_z)
				if data[air_index] != BlockRegistryScript.BLOCK_AIR:
					continue
				var hash_value := WorldGenHashScript.hash_3d(config.seed + 1061, world_x, y, world_z)
				var floor_y := _cave_solid_y(data, local_x, y, local_z, -1, 8)
				var ceiling_y := _cave_solid_y(data, local_x, y, local_z, 1, 10)
				if floor_y < 1 and ceiling_y < 1:
					continue
				var cave_biome := BiomeCatalogScript.cave_biome_at(
					config.seed, world_x, y, world_z, config.worldgen_version)
				if floor_y >= 1 and _is_cave_stone(data[_index(local_x, floor_y, local_z)]):
					if cave_biome != BiomeCatalogScript.CAVE_BIOME_NONE and hash_value % 3 != 0:
						_paint_cave_floor_patch(data, local_x, floor_y, local_z, cave_biome, hash_value)
					elif hash_value % 11 == 0:
						data[_index(local_x, floor_y, local_z)] = BlockRegistryScript.BLOCK_MYCELIUM if hash_value % 2 == 0 else BlockRegistryScript.BLOCK_MUD
				if cave_biome == BiomeCatalogScript.LUSH_CAVES:
					_decorate_lush_cave(data, local_x, local_z, floor_y, ceiling_y, hash_value)
				elif cave_biome == BiomeCatalogScript.DEEP_DARK:
					_decorate_deep_dark(data, local_x, local_z, floor_y, ceiling_y, hash_value)
				var dripstone_divisor := 3 if cave_biome == BiomeCatalogScript.DRIPSTONE_CAVES else 13
				if (floor_y >= 1 or ceiling_y >= 1) and hash_value % dripstone_divisor == 0:
					_stamp_dripstone(data, local_x, local_z, floor_y, ceiling_y, hash_value)
				if floor_y >= 4 and local_x >= 2 and local_x <= VoxelDefsScript.CHUNK_SIZE - 3 \
						and local_z >= 2 and local_z <= VoxelDefsScript.CHUNK_SIZE - 3 and hash_value % 41 == 0:
					_stamp_small_pool(data, local_x, floor_y + 1, local_z, hash_value)


func _cave_solid_y(data: PackedByteArray, local_x: int, start_y: int, local_z: int, direction: int, reach: int) -> int:
	for distance in range(1, reach + 1):
		var y := start_y + distance * direction
		if y <= 1 or y >= VoxelDefsScript.WORLD_HEIGHT - 1:
			break
		if data[_index(local_x, y, local_z)] != BlockRegistryScript.BLOCK_AIR:
			return y
	return -1


func _is_cave_stone(block_id: int) -> bool:
	return block_id in [BlockRegistryScript.BLOCK_STONE, BlockRegistryScript.BLOCK_DEEPSTONE,
		BlockRegistryScript.BLOCK_MOSS, BlockRegistryScript.BLOCK_SCULK]


## Five-wide patches turn the four-block cave lattice into readable material
## regions rather than isolated checkerboard pixels. Each neighboring column
## independently finds a floor within one block of the anchor, preserving
## slopes and never filling cave air.
func _paint_cave_floor_patch(data: PackedByteArray, center_x: int, floor_y: int, center_z: int, cave_biome: int, hash_value: int) -> void:
	for z in range(maxi(center_z - 2, 0), mini(center_z + 2, VoxelDefsScript.CHUNK_SIZE - 1) + 1):
		for x in range(maxi(center_x - 2, 0), mini(center_x + 2, VoxelDefsScript.CHUNK_SIZE - 1) + 1):
			for y_offset in [0, -1, 1]:
				var target_y: int = floor_y + int(y_offset)
				if target_y <= 1 or target_y + 1 >= VoxelDefsScript.WORLD_HEIGHT:
					continue
				var index := _index(x, target_y, z)
				if not _is_cave_stone(data[index]) or data[_index(x, target_y + 1, z)] != BlockRegistryScript.BLOCK_AIR:
					continue
				var selector := WorldGenHashScript.hash_3d(config.seed + 1073 + hash_value, x, target_y, z)
				data[index] = BiomeCatalogScript.cave_surface_block(cave_biome, selector)
				break


func _decorate_lush_cave(data: PackedByteArray, local_x: int, local_z: int, floor_y: int, ceiling_y: int, hash_value: int) -> void:
	if floor_y >= 1:
		var plant_y := floor_y + 1
		if plant_y < VoxelDefsScript.WORLD_HEIGHT and data[_index(local_x, plant_y, local_z)] == BlockRegistryScript.BLOCK_AIR and hash_value % 3 == 0:
			data[_index(local_x, plant_y, local_z)] = BlockRegistryScript.BLOCK_CAVE_MOSS
	if ceiling_y >= 1 and hash_value % 5 == 0:
		var hanging_y := ceiling_y - 1
		if data[_index(local_x, hanging_y, local_z)] == BlockRegistryScript.BLOCK_AIR:
			data[_index(local_x, hanging_y, local_z)] = BlockRegistryScript.BLOCK_CAVE_MOSS


func _decorate_deep_dark(data: PackedByteArray, local_x: int, local_z: int, floor_y: int, ceiling_y: int, hash_value: int) -> void:
	for surface_y in [floor_y, ceiling_y]:
		if surface_y >= 1 and _is_cave_stone(data[_index(local_x, surface_y, local_z)]) and hash_value % 4 != 0:
			data[_index(local_x, surface_y, local_z)] = BlockRegistryScript.BLOCK_SCULK if hash_value % 2 == 0 else BlockRegistryScript.BLOCK_DEEPSTONE


func _stamp_dripstone(data: PackedByteArray, local_x: int, local_z: int, floor_y: int, ceiling_y: int, hash_value: int) -> void:
	var gap := ceiling_y - floor_y - 1 if floor_y >= 1 and ceiling_y >= 1 else 10
	var ceiling_length := mini(1 + hash_value % 4, gap) if ceiling_y >= 1 else 0
	var floor_length := mini(1 + (hash_value / 7) % 3, maxi(gap - ceiling_length, 0)) if floor_y >= 1 else 0
	if floor_y >= 1 and ceiling_y >= 1 and gap <= 7 and hash_value % 3 == 0:
		ceiling_length = gap
		floor_length = 0
	for offset in ceiling_length:
		var y := ceiling_y - 1 - offset
		if data[_index(local_x, y, local_z)] != BlockRegistryScript.BLOCK_AIR:
			break
		data[_index(local_x, y, local_z)] = BlockRegistryScript.BLOCK_DRIPSTONE
	for offset in floor_length:
		var y := floor_y + 1 + offset
		if data[_index(local_x, y, local_z)] != BlockRegistryScript.BLOCK_AIR:
			break
		data[_index(local_x, y, local_z)] = BlockRegistryScript.BLOCK_DRIPSTONE


func _stamp_small_pool(data: PackedByteArray, center_x: int, water_y: int, center_z: int, hash_value: int) -> void:
	var radius := 1 + hash_value % 2
	for z in range(center_z - radius, center_z + radius + 1):
		for x in range(center_x - radius, center_x + radius + 1):
			if (x - center_x) * (x - center_x) + (z - center_z) * (z - center_z) > radius * radius:
				continue
			if data[_index(x, water_y, z)] == BlockRegistryScript.BLOCK_AIR \
					and data[_index(x, water_y - 1, z)] != BlockRegistryScript.BLOCK_AIR:
				data[_index(x, water_y, z)] = BlockRegistryScript.BLOCK_WATER


## Rare global-cell geodes are evaluated with a radius halo, so the same sphere
## is clipped consistently by every touched chunk. A dark shell encloses a pale
## calcite lining, amethyst deposits, a hollow center, and emissive crystal buds.
func _place_geodes(data: PackedByteArray, field: ChunkTerrainData, origin_x: int, origin_z: int) -> void:
	const cell_size := 72
	const halo := 11
	var first_x := WorldGenHashScript.floor_div(origin_x - halo, cell_size)
	var last_x := WorldGenHashScript.floor_div(origin_x + VoxelDefsScript.CHUNK_SIZE - 1 + halo, cell_size)
	var first_z := WorldGenHashScript.floor_div(origin_z - halo, cell_size)
	var last_z := WorldGenHashScript.floor_div(origin_z + VoxelDefsScript.CHUNK_SIZE - 1 + halo, cell_size)
	for cell_z in range(first_z, last_z + 1):
		for cell_x in range(first_x, last_x + 1):
			var hash_value := WorldGenHashScript.hash_2d(config.seed + 1327, cell_x, cell_z)
			if hash_value % 13 != 0:
				continue
			var center := Vector3i(cell_x * cell_size + 12 + hash_value % 48,
				10 + (hash_value / 29) % 31, cell_z * cell_size + 12 + (hash_value / 71) % 48)
			_stamp_geode(data, field, center, 6 + hash_value % 4, hash_value)


func _stamp_geode(data: PackedByteArray, field: ChunkTerrainData, center: Vector3i, radius: int, seed_hash: int) -> void:
	var origin_x := field.chunk_x * VoxelDefsScript.CHUNK_SIZE
	var origin_z := field.chunk_z * VoxelDefsScript.CHUNK_SIZE
	for world_z in range(maxi(center.z - radius, origin_z), mini(center.z + radius, origin_z + VoxelDefsScript.CHUNK_SIZE - 1) + 1):
		var local_z := world_z - origin_z
		for world_x in range(maxi(center.x - radius, origin_x), mini(center.x + radius, origin_x + VoxelDefsScript.CHUNK_SIZE - 1) + 1):
			var local_x := world_x - origin_x
			var field_index := ChunkTerrainDataScript.cell_index(local_x, local_z)
			var max_geode_y := _surface_height(field, field_index) - SURFACE_CLEARANCE - 2
			for y in range(maxi(2, center.y - radius), mini(center.y + radius, max_geode_y) + 1):
				var offset := Vector3(float(world_x - center.x), float(y - center.y), float(world_z - center.z))
				var distance := offset.length() / float(radius)
				if distance > 1.0:
					continue
				var index := _index(local_x, y, local_z)
				var existing := data[index]
				if distance >= 0.82:
					if existing == BlockRegistryScript.BLOCK_STONE:
						data[index] = BlockRegistryScript.BLOCK_GEODE_SHELL
				elif distance >= 0.66:
					if existing != BlockRegistryScript.BLOCK_BEDROCK:
						var crystal_hash := WorldGenHashScript.hash_3d(config.seed + 1361 + seed_hash, world_x, y, world_z)
						data[index] = BlockRegistryScript.BLOCK_AMETHYST if crystal_hash % 5 == 0 else BlockRegistryScript.BLOCK_CALCITE
				elif existing != BlockRegistryScript.BLOCK_BEDROCK:
					data[index] = BlockRegistryScript.BLOCK_AIR
	# Buds occupy hollow cells adjacent to the crystalline lining.
	for world_z in range(maxi(center.z - radius + 2, origin_z), mini(center.z + radius - 2, origin_z + VoxelDefsScript.CHUNK_SIZE - 1) + 1):
		var local_z := world_z - origin_z
		for world_x in range(maxi(center.x - radius + 2, origin_x), mini(center.x + radius - 2, origin_x + VoxelDefsScript.CHUNK_SIZE - 1) + 1):
			var local_x := world_x - origin_x
			for y in range(maxi(3, center.y - radius + 2), mini(VoxelDefsScript.WORLD_HEIGHT - 2, center.y + radius - 2) + 1):
				var index := _index(local_x, y, local_z)
				if data[index] != BlockRegistryScript.BLOCK_AIR or WorldGenHashScript.hash_3d(config.seed + 1399, world_x, y, world_z) % 17 != 0:
					continue
				for direction in [Vector3i.UP, Vector3i.DOWN, Vector3i.LEFT, Vector3i.RIGHT, Vector3i.FORWARD, Vector3i.BACK]:
					var neighbor: Vector3i = Vector3i(local_x, y, local_z) + Vector3i(direction)
					if neighbor.x < 0 or neighbor.x >= VoxelDefsScript.CHUNK_SIZE or neighbor.z < 0 or neighbor.z >= VoxelDefsScript.CHUNK_SIZE:
						continue
					if data[_index(neighbor.x, neighbor.y, neighbor.z)] == BlockRegistryScript.BLOCK_AMETHYST:
						data[index] = BlockRegistryScript.BLOCK_CRYSTAL_BUD
						break


func _ore_for_anchor(hash_value: int, y: int) -> int:
	return _ore_catalog.select(hash_value, y)


func _stamp_ore_segment(data: PackedByteArray, origin_x: int, origin_z: int, start: Vector3i, finish: Vector3i, ore: int,
		solid_y: PackedInt32Array = PackedInt32Array(), solid_id: PackedByteArray = PackedByteArray(),
		sub_id: PackedByteArray = PackedByteArray()) -> void:
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
				if not solid_y.is_empty():
					# Same ordered stamps and stone-only replacement as full detail,
					# but intersect just the two exposed cells, never a voxel volume.
					var column: int = local_x + local_z * VoxelDefsScript.DATA_STRIDE_Z
					var top_y: int = solid_y[column]
					if top_y >= 1 and top_y < VoxelDefsScript.WORLD_HEIGHT \
							and absi(top_y - center.y) <= 1 and solid_id[column] == BlockRegistryScript.BLOCK_STONE:
						solid_id[column] = ore
					if top_y > 1 and top_y <= VoxelDefsScript.WORLD_HEIGHT \
							and absi(top_y - 1 - center.y) <= 1 and sub_id[column] == BlockRegistryScript.BLOCK_STONE:
						sub_id[column] = ore
					continue
				for y in range(center.y - 1, center.y + 2):
					if y < 1 or y >= VoxelDefsScript.WORLD_HEIGHT:
						continue
					if data[_index(local_x, y, local_z)] == BlockRegistryScript.BLOCK_STONE:
						data[_index(local_x, y, local_z)] = ore


func _decorate(data: PackedByteArray, field: ChunkTerrainData, origin_x: int, origin_z: int,
		max_y: int, ground_scratch: DecorationGroundScratch) -> int:
	# Dense-biome groves plus the sparse tree lottery are collected once; the
	# lattice pass below then only has to place non-tree features.
	var trees := _collect_trees(field, origin_x, origin_z, ground_scratch)
	for tree_index in trees.size():
		max_y = maxi(max_y, _stamp_feature(data, origin_x, origin_z,
			trees.world_xs[tree_index], trees.ground_ys[tree_index], trees.world_zs[tree_index],
			trees.features[tree_index], trees.hashes[tree_index]))
	var first_x: int = WorldGenHashScript.floor_div(origin_x - FEATURE_HALO, FEATURE_CELL_SIZE)
	var last_x: int = WorldGenHashScript.floor_div(origin_x + VoxelDefsScript.CHUNK_SIZE - 1 + FEATURE_HALO, FEATURE_CELL_SIZE)
	var first_z: int = WorldGenHashScript.floor_div(origin_z - FEATURE_HALO, FEATURE_CELL_SIZE)
	var last_z: int = WorldGenHashScript.floor_div(origin_z + VoxelDefsScript.CHUNK_SIZE - 1 + FEATURE_HALO, FEATURE_CELL_SIZE)
	for cell_z in range(first_z, last_z + 1):
		for cell_x in range(first_x, last_x + 1):
			var hash_value: int = WorldGenHashScript.hash_2d(config.seed + 1103, cell_x, cell_z)
			var world_x: int = cell_x * FEATURE_CELL_SIZE + 1 + hash_value % (FEATURE_CELL_SIZE - 2)
			var world_z: int = cell_z * FEATURE_CELL_SIZE + 1 + (hash_value / 31) % (FEATURE_CELL_SIZE - 2)
			if not _footprint_intersects_chunk(world_x, world_z, FEATURE_FOOTPRINT_RADIUS, origin_x, origin_z):
				continue
			var ground := _cached_decoration_ground(field, world_x, world_z, ground_scratch)
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
			# Trees were already stamped by the shared pass above.
			if (flags & DecorationCatalog.FLAG_TREE) != 0:
				continue
			var probability: float = float(entry[2]) * config.decoration_density
			if WorldGenHashScript.float_01_2d(config.seed + 1129, cell_x, cell_z) >= minf(0.94, probability):
				continue
			if not _feature_site_is_valid(field, ground_scratch, world_x, ground.x, world_z, flags):
				continue
			max_y = maxi(max_y, _stamp_feature(data, origin_x, origin_z, world_x, ground.x, world_z, feature, hash_value))
	max_y = maxi(max_y, _decorate_ground_cover(data, field, origin_x, origin_z))
	return max_y


## Single acceptance pass for every tree: dense-biome groves (forest, taiga,
## jungle, swamp) plus the sparse non-grove tree lottery. Each entry is
## [feature, world_x, ground_y, world_z, hash_value]. In `lod` mode the pass
## only considers anchors inside the padded field and skips site-validity
## probes: those probes leave the field and cost nearly a full population, and
## a distant crown on an occasional rejected site is invisible at that range.
func _collect_trees(field: ChunkTerrainData, origin_x: int, origin_z: int,
		ground_scratch: DecorationGroundScratch, lod: bool = false) -> TreeCandidates:
	var trees := TreeCandidates.new()
	if config.tree_density <= 0.0 or config.decoration_density <= 0.0:
		return trees
	var first_grove_x: int = WorldGenHashScript.floor_div(origin_x - TREE_FOOTPRINT_RADIUS, TREE_CELL_SIZE)
	var last_grove_x: int = WorldGenHashScript.floor_div(origin_x + VoxelDefsScript.CHUNK_SIZE - 1 + TREE_FOOTPRINT_RADIUS, TREE_CELL_SIZE)
	var first_grove_z: int = WorldGenHashScript.floor_div(origin_z - TREE_FOOTPRINT_RADIUS, TREE_CELL_SIZE)
	var last_grove_z: int = WorldGenHashScript.floor_div(origin_z + VoxelDefsScript.CHUNK_SIZE - 1 + TREE_FOOTPRINT_RADIUS, TREE_CELL_SIZE)
	for cell_z in range(first_grove_z, last_grove_z + 1):
		for cell_x in range(first_grove_x, last_grove_x + 1):
			var anchor_hash: int = WorldGenHashScript.hash_2d(config.seed + 1223, cell_x, cell_z)
			# Keep anchors at least five blocks apart, even across cell boundaries.
			# This permits overlapping crowns but prevents one candidate's foliage
			# from occupying another candidate's root/trunk volume.
			var world_x: int = cell_x * TREE_CELL_SIZE + 2 + anchor_hash % 2
			var world_z: int = cell_z * TREE_CELL_SIZE + 2 + (anchor_hash / 23) % 2
			if not _footprint_intersects_chunk(world_x, world_z, TREE_FOOTPRINT_RADIUS, origin_x, origin_z):
				continue
			if lod and not ChunkTerrainDataScript.is_valid_local(world_x - origin_x, world_z - origin_z):
				continue
			var ground := _cached_decoration_ground(field, world_x, world_z, ground_scratch)
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
			# Deep forest cores grow ancient trees so the interior reads as old
			# growth instead of the same crown mix as the edges.
			if decoration_set == BiomeCatalogScript.DECORATION_FOREST and grove_strength > 0.75 and anchor_hash % 3 == 0:
				feature = DecorationCatalog.FEATURE_ANCIENT_TREE
			if not lod:
				if not _feature_site_is_valid(field, ground_scratch, world_x, ground.x, world_z, int(entry[3])):
					continue
				if feature != DecorationCatalog.FEATURE_MANGROVE:
					if not _tree_site_is_safe(field, ground_scratch, world_x, ground.x, world_z, _tree_footprint_for(feature), _tree_top_offset_for(feature, feature_hash)):
						continue
			trees.append(feature, world_x, ground.x, world_z, feature_hash)
	# Sparse tree lottery for biomes without grove trees (plains oak, savanna
	# acacia, cold spruce, ...). Grove biomes use choose_non_tree above, so the
	# two sources never overlap.
	var first_x: int = WorldGenHashScript.floor_div(origin_x - FEATURE_HALO, FEATURE_CELL_SIZE)
	var last_x: int = WorldGenHashScript.floor_div(origin_x + VoxelDefsScript.CHUNK_SIZE - 1 + FEATURE_HALO, FEATURE_CELL_SIZE)
	var first_z: int = WorldGenHashScript.floor_div(origin_z - FEATURE_HALO, FEATURE_CELL_SIZE)
	var last_z: int = WorldGenHashScript.floor_div(origin_z + VoxelDefsScript.CHUNK_SIZE - 1 + FEATURE_HALO, FEATURE_CELL_SIZE)
	for cell_z in range(first_z, last_z + 1):
		for cell_x in range(first_x, last_x + 1):
			var hash_value: int = WorldGenHashScript.hash_2d(config.seed + 1103, cell_x, cell_z)
			var world_x: int = cell_x * FEATURE_CELL_SIZE + 1 + hash_value % (FEATURE_CELL_SIZE - 2)
			var world_z: int = cell_z * FEATURE_CELL_SIZE + 1 + (hash_value / 31) % (FEATURE_CELL_SIZE - 2)
			if not _footprint_intersects_chunk(world_x, world_z, FEATURE_FOOTPRINT_RADIUS, origin_x, origin_z):
				continue
			if lod and not ChunkTerrainDataScript.is_valid_local(world_x - origin_x, world_z - origin_z):
				continue
			var ground := _cached_decoration_ground(field, world_x, world_z, ground_scratch)
			if ground.x < 0:
				continue
			var decoration_set: int = biomes.decoration_set(ground.y)
			var selector: float = WorldGenHashScript.float_01_2d(config.seed + 1117, cell_x, cell_z)
			var entry: Array = decorations.choose_non_tree(decoration_set, selector) if _uses_grove_trees(decoration_set) else decorations.choose(decoration_set, selector)
			if entry.is_empty():
				continue
			var feature: int = int(entry[0])
			var flags: int = int(entry[3])
			if (flags & DecorationCatalog.FLAG_TREE) == 0:
				continue
			var probability: float = float(entry[2]) * config.decoration_density * config.tree_density
			if WorldGenHashScript.float_01_2d(config.seed + 1129, cell_x, cell_z) >= minf(0.94, probability):
				continue
			if not lod:
				if not _feature_site_is_valid(field, ground_scratch, world_x, ground.x, world_z, flags):
					continue
				if feature != DecorationCatalog.FEATURE_MANGROVE:
					if not _tree_site_is_safe(field, ground_scratch, world_x, ground.x, world_z, _tree_footprint_for(feature), _tree_top_offset_for(feature, hash_value)):
						continue
			trees.append(feature, world_x, ground.x, world_z, hash_value)
	return trees


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
			if float(grove_hash % 1000) / 1000.0 >= 0.90:
				continue
			var center_x: int = grove_x * TREE_GROVE_CELL_SIZE + 10 + grove_hash % 33
			var center_z: int = grove_z * TREE_GROVE_CELL_SIZE + 10 + (grove_hash / 37) % 33
			var radius: float = float(30 + (grove_hash / 73) % 13)
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
			base = 0.97
		BiomeCatalogScript.DECORATION_TAIGA:
			base = 0.95
		BiomeCatalogScript.DECORATION_TROPICAL:
			base = 0.985
		BiomeCatalogScript.DECORATION_SWAMP:
			base = 0.92
	return minf(0.98, base * grove_strength * config.tree_density * config.decoration_density)


## Placement flags are evaluated from immutable terrain samples so every chunk
## touching a cross-border feature reaches the same ecological decision.
func _feature_site_is_valid(field: ChunkTerrainData, ground_scratch: DecorationGroundScratch,
		world_x: int, ground_y: int, world_z: int, flags: int) -> bool:
	if ground_y < 1 or ground_y + 1 >= VoxelDefsScript.WORLD_HEIGHT:
		return false
	var site_biome: int = _cached_decoration_ground(field, world_x, world_z, ground_scratch).y
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
				field, world_x + direction.x * 2, world_z + direction.y * 2, ground_scratch)
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
		DecorationCatalog.FEATURE_JUNGLE, DecorationCatalog.FEATURE_SPRUCE, DecorationCatalog.FEATURE_ANCIENT_TREE:
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
		DecorationCatalog.FEATURE_ANCIENT_TREE:
			return 8 + hash_value % 4 + 2
	return 0


## This acceptance decision deliberately reads no generated voxel data. Every
## chunk that intersects a tree must reach the same answer, including chunks
## which only contain the canopy. Base/snow/cliff surface rules always produce
## a solid top above sea level; the profile probes reject steep/embedded sites,
## and the only cave stage allowed to reach that surface (an entrance) is
## reproduced below as a shared immutable exclusion.
func _tree_site_is_safe(field: ChunkTerrainData, ground_scratch: DecorationGroundScratch,
		world_x: int, ground_y: int, world_z: int, footprint: int, top_offset: int) -> bool:
	if ground_y <= VoxelDefsScript.SEA_LEVEL + 1 or ground_y + top_offset >= VoxelDefsScript.WORLD_HEIGHT:
		return false
	if _tree_root_is_near_cave_entrance(world_x, world_z):
		return false
	# Cardinal and diagonal edge probes catch the slope changes that would bury
	# the low canopy. Nine fixed probes (root plus this ring) replace the former
	# 29 point-query footprint scan; results are cached per chunk job.
	for direction in VoxelDefsScript.DIRS_8:
		var nearby_ground := _cached_decoration_ground(field, world_x + direction.x * footprint,
			world_z + direction.y * footprint, ground_scratch)
		if nearby_ground.x < 0 or nearby_ground.x > ground_y + 1 or nearby_ground.x < ground_y - 3:
			return false
	return true


func _cached_decoration_ground(field: ChunkTerrainData, world_x: int, world_z: int,
		ground_scratch: DecorationGroundScratch) -> Vector2i:
	var slot := ground_scratch.find_slot(world_x, world_z)
	if slot >= 0:
		return ground_scratch.value_at(slot)
	var ground := _decoration_ground(field, world_x, world_z)
	ground_scratch.insert(world_x, world_z, ground)
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
			if float(hash_value % 1000) / 1000.0 >= minf(0.45, 0.18 * config.cave_density):
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
			# Tufts spread two blocks from the anchor; excluded anchors cannot
			# write any voxel here, regardless of their terrain/biome decision.
			if not _footprint_intersects_chunk(center_x, center_z, 2, origin_x, origin_z):
				continue
			var ground := _decoration_ground(field, center_x, center_z)
			if ground.x <= VoxelDefsScript.SEA_LEVEL + 1:
				continue
			var decoration_set: int = biomes.decoration_set(ground.y)
			# Grove interiors get a full, layered understory instead of clearings.
			var deep_forest: bool = _uses_grove_trees(decoration_set) and _tree_grove_strength(center_x, center_z) > 0.70
			var chance: float = 1.0 if deep_forest else decorations.ground_cover_chance(decoration_set) * config.decoration_density
			if chance <= 0.0 or WorldGenHashScript.float_01_2d(config.seed + 1193, cell_x, cell_z) >= minf(0.95, chance):
				continue
			var tuft_count: int = 3 + (anchor_hash / 71) % 4 + (2 if deep_forest else 0)
			for tuft_index in tuft_count:
				var tuft_hash: int = WorldGenHashScript.hash_3d(config.seed + 1201, cell_x, tuft_index, cell_z)
				var world_x: int = center_x + (tuft_hash % 5) - 2
				var world_z: int = center_z + ((tuft_hash / 13) % 5) - 2
				max_y = maxi(max_y, _place_ground_cover(data, field, origin_x, origin_z, world_x, world_z, decoration_set, tuft_hash))
	return max_y


## Validate against the generated voxel data after caves and regular features:
## grass never floats over a carved entrance, overwrites a feature, or appears
## on water/sand. Grass surface blocks are opaque, dry soil by definition.
func _place_ground_cover(data: PackedByteArray, field: ChunkTerrainData, origin_x: int, origin_z: int, world_x: int, world_z: int, decoration_set: int, hash_value: int) -> int:
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
	data[_index(local_x, ground_y + 1, local_z)] = _ground_cover_block(decoration_set, hash_value)
	return ground_y + 1


## Grassland ground cover mixes wildflowers into the tufts so fields read as a
## layered meadow instead of a uniform grass carpet.
func _ground_cover_block(decoration_set: int, hash_value: int) -> int:
	match decoration_set:
		BiomeCatalogScript.DECORATION_PLAINS, BiomeCatalogScript.DECORATION_MEADOW, BiomeCatalogScript.DECORATION_RIVERBANK:
			if hash_value % 100 < 22:
				return BlockRegistryScript.BLOCK_YELLOW_FLOWER if hash_value % 2 == 0 else BlockRegistryScript.BLOCK_RED_FLOWER
		BiomeCatalogScript.DECORATION_FOREST:
			if hash_value % 100 < 16:
				return BlockRegistryScript.BLOCK_YELLOW_FLOWER if hash_value % 2 == 0 else BlockRegistryScript.BLOCK_RED_FLOWER
	return BlockRegistryScript.BLOCK_TALL_GRASS


## Seabed vegetation. Like land decoration, anchors come from a global lattice
## with a halo so adjacent chunks reach the same decision, and plants replace
## water cells only: they can never overwrite terrain, caves, or other
## features. Plant height is bounded by the local water depth, so nothing
## reaches the surface. Distance chunks skip this pass (LOD keeps only the
## compact top columns), which is invisible past the full-detail ring.
const UNDERWATER_CELL_SIZE: int = 6
const UNDERWATER_HALO: int = 4
const UNDERWATER_TUFT_RADIUS: int = 2

func _decorate_underwater(data: PackedByteArray, field: ChunkTerrainData, origin_x: int, origin_z: int,
		max_y: int, ground_scratch: DecorationGroundScratch) -> int:
	var first_x: int = WorldGenHashScript.floor_div(origin_x - UNDERWATER_HALO, UNDERWATER_CELL_SIZE)
	var last_x: int = WorldGenHashScript.floor_div(origin_x + VoxelDefsScript.CHUNK_SIZE - 1 + UNDERWATER_HALO, UNDERWATER_CELL_SIZE)
	var first_z: int = WorldGenHashScript.floor_div(origin_z - UNDERWATER_HALO, UNDERWATER_CELL_SIZE)
	var last_z: int = WorldGenHashScript.floor_div(origin_z + VoxelDefsScript.CHUNK_SIZE - 1 + UNDERWATER_HALO, UNDERWATER_CELL_SIZE)
	for cell_z in range(first_z, last_z + 1):
		for cell_x in range(first_x, last_x + 1):
			var anchor_hash: int = WorldGenHashScript.hash_2d(config.seed + 1423, cell_x, cell_z)
			var center_x: int = cell_x * UNDERWATER_CELL_SIZE + 2 + anchor_hash % (UNDERWATER_CELL_SIZE - 4)
			var center_z: int = cell_z * UNDERWATER_CELL_SIZE + 2 + (anchor_hash / 29) % (UNDERWATER_CELL_SIZE - 4)
			if not _footprint_intersects_chunk(center_x, center_z, UNDERWATER_TUFT_RADIUS, origin_x, origin_z):
				continue
			var ground := _cached_decoration_ground(field, center_x, center_z, ground_scratch)
			if ground.x < 0 or not biomes.is_ocean_biome(ground.y):
				continue
			var set_id: int = biomes.decoration_set(ground.y)
			var density: Vector3 = decorations.underwater_density(set_id)
			if density.x <= 0.0:
				continue
			var chance: float = density.x * config.decoration_density
			if WorldGenHashScript.float_01_2d(config.seed + 1447, cell_x, cell_z) >= minf(0.95, chance):
				continue
			var tuft_span: int = maxi(int(density.z) - int(density.y) + 1, 1)
			var tuft_count: int = int(density.y) + (anchor_hash / 71) % tuft_span
			for tuft_index in tuft_count:
				var tuft_hash: int = WorldGenHashScript.hash_3d(config.seed + 1451, cell_x, tuft_index, cell_z)
				var world_x: int = center_x + (tuft_hash % (UNDERWATER_TUFT_RADIUS * 2 + 1)) - UNDERWATER_TUFT_RADIUS
				var world_z: int = center_z + ((tuft_hash / 13) % (UNDERWATER_TUFT_RADIUS * 2 + 1)) - UNDERWATER_TUFT_RADIUS
				if not _footprint_intersects_chunk(world_x, world_z, 0, origin_x, origin_z):
					continue
				var tuft_ground := _cached_decoration_ground(field, world_x, world_z, ground_scratch)
				if tuft_ground.x < 0 or not biomes.is_ocean_biome(tuft_ground.y):
					continue
				var depth: int = VoxelDefsScript.SEA_LEVEL - tuft_ground.x
				if depth < 2:
					continue
				var entry: Array = decorations.choose_underwater(set_id, WorldGenHashScript.float_01_2d(
					config.seed + 1459, cell_x * 31 + tuft_index, cell_z))
				if entry.is_empty():
					continue
				if WorldGenHashScript.float_01_2d(config.seed + 1461, cell_x + tuft_index * 7, cell_z) >= float(entry[2]):
					continue
				max_y = maxi(max_y, _stamp_underwater_plant(
					data, origin_x, origin_z, world_x, tuft_ground.x, world_z, int(entry[0]), tuft_hash, depth))
	return max_y


## Plants only ever fill water cells, and a multi-block stalk stops early when
## the cell above is occupied, so kelp never floats on a shorter neighbor.
func _stamp_underwater_plant(data: PackedByteArray, origin_x: int, origin_z: int, world_x: int, ground_y: int, world_z: int, species: int, hash_value: int, depth: int) -> int:
	var block_id: int = BlockRegistryScript.BLOCK_SEAGRASS
	var height: int = 1 + (hash_value / 17) % 2
	match species:
		DecorationCatalog.FEATURE_KELP:
			block_id = BlockRegistryScript.BLOCK_KELP
			height = 3 + (hash_value / 7) % 5
		DecorationCatalog.FEATURE_CORAL_FAN:
			block_id = BlockRegistryScript.BLOCK_CORAL_FAN
			height = 1 + (hash_value / 11) % 2
		DecorationCatalog.FEATURE_CORAL_BRANCH:
			block_id = BlockRegistryScript.BLOCK_CORAL_BRANCH
			height = 1 + (hash_value / 13) % 2
		DecorationCatalog.FEATURE_SPONGE:
			block_id = BlockRegistryScript.BLOCK_SPONGE
		DecorationCatalog.FEATURE_ANEMONE:
			block_id = BlockRegistryScript.BLOCK_ANEMONE
	height = clampi(height, 1, maxi(depth - 1, 1))
	var last := -1
	for y in range(1, height + 1):
		var placed := _place_underwater(data, origin_x, origin_z, world_x, ground_y + y, world_z, block_id)
		if placed < 0:
			break
		last = placed
	return last


func _place_underwater(data: PackedByteArray, origin_x: int, origin_z: int, world_x: int, y: int, world_z: int, block_id: int) -> int:
	var local_x: int = world_x - origin_x
	var local_z: int = world_z - origin_z
	if local_x < 0 or local_x >= VoxelDefsScript.CHUNK_SIZE or local_z < 0 or local_z >= VoxelDefsScript.CHUNK_SIZE or y < 0 or y >= VoxelDefsScript.WORLD_HEIGHT:
		return -1
	var voxel_index: int = _index(local_x, y, local_z)
	if not _is_water(data[voxel_index]):
		return -1
	data[voxel_index] = block_id
	return y


func _is_water(block_id: int) -> bool:
	return block_id == BlockRegistryScript.BLOCK_WATER \
		or (block_id >= BlockRegistryScript.BLOCK_WATER_FLOW_7 and block_id <= BlockRegistryScript.BLOCK_WATER_FLOW_1)


## Worn ground patches: dirt scars in grasslands and forests, mud in wetlands,
## gravel on rocky or shore biomes. Replaces only the biome's own surface block,
## so it can never carve into props, ores, or player edits.
const FLOOR_PATCH_CELL: int = 32
const FLOOR_PATCH_HALO: int = 5
const FLOOR_PATCH_CHANCE: float = 0.30

func _decorate_floor_patches(data: PackedByteArray, field: ChunkTerrainData, origin_x: int, origin_z: int) -> void:
	for cell_z in range(WorldGenHashScript.floor_div(origin_z - FLOOR_PATCH_HALO, FLOOR_PATCH_CELL), WorldGenHashScript.floor_div(origin_z + VoxelDefsScript.CHUNK_SIZE - 1 + FLOOR_PATCH_HALO, FLOOR_PATCH_CELL) + 1):
		for cell_x in range(WorldGenHashScript.floor_div(origin_x - FLOOR_PATCH_HALO, FLOOR_PATCH_CELL), WorldGenHashScript.floor_div(origin_x + VoxelDefsScript.CHUNK_SIZE - 1 + FLOOR_PATCH_HALO, FLOOR_PATCH_CELL) + 1):
			var hash_value: int = WorldGenHashScript.hash_2d(config.seed + 1321, cell_x, cell_z)
			if float(hash_value % 1000) / 1000.0 >= FLOOR_PATCH_CHANCE:
				continue
			var center_x: int = cell_x * FLOOR_PATCH_CELL + 6 + (hash_value / 7) % 20
			var center_z: int = cell_z * FLOOR_PATCH_CELL + 6 + (hash_value / 53) % 20
			var radius: int = 1 + (hash_value / 101) % 3
			for dz in range(-radius, radius + 1):
				for dx in range(-radius, radius + 1):
					if dx * dx + dz * dz > radius * radius:
						continue
					var local_x: int = center_x + dx - origin_x
					var local_z: int = center_z + dz - origin_z
					if local_x < 0 or local_x >= VoxelDefsScript.CHUNK_SIZE or local_z < 0 or local_z >= VoxelDefsScript.CHUNK_SIZE:
						continue
					var field_index: int = ChunkTerrainDataScript.cell_index(local_x, local_z)
					var biome: int = int(field.dominant_biome[field_index])
					var patch_block: int = _floor_patch_block(biomes.decoration_set(biome))
					if patch_block == BlockRegistryScript.BLOCK_AIR:
						continue
					var surface_y: int = _surface_height(field, field_index)
					var voxel_index: int = _index(local_x, surface_y, local_z)
					if data[voxel_index] != biomes.surface_block(biome):
						continue
					data[voxel_index] = patch_block


## Mirrors the full-detail patch pass by swapping the compact top id, so the
## same scars are visible from a distance without any extra geometry.
func _apply_lod_floor_patches(solid_y: PackedInt32Array, solid_id: PackedByteArray, field: ChunkTerrainData, origin_x: int, origin_z: int) -> void:
	for cell_z in range(WorldGenHashScript.floor_div(origin_z - FLOOR_PATCH_HALO, FLOOR_PATCH_CELL), WorldGenHashScript.floor_div(origin_z + VoxelDefsScript.CHUNK_SIZE - 1 + FLOOR_PATCH_HALO, FLOOR_PATCH_CELL) + 1):
		for cell_x in range(WorldGenHashScript.floor_div(origin_x - FLOOR_PATCH_HALO, FLOOR_PATCH_CELL), WorldGenHashScript.floor_div(origin_x + VoxelDefsScript.CHUNK_SIZE - 1 + FLOOR_PATCH_HALO, FLOOR_PATCH_CELL) + 1):
			var hash_value: int = WorldGenHashScript.hash_2d(config.seed + 1321, cell_x, cell_z)
			if float(hash_value % 1000) / 1000.0 >= FLOOR_PATCH_CHANCE:
				continue
			var center_x: int = cell_x * FLOOR_PATCH_CELL + 6 + (hash_value / 7) % 20
			var center_z: int = cell_z * FLOOR_PATCH_CELL + 6 + (hash_value / 53) % 20
			var radius: int = 1 + (hash_value / 101) % 3
			for dz in range(-radius, radius + 1):
				for dx in range(-radius, radius + 1):
					if dx * dx + dz * dz > radius * radius:
						continue
					var local_x: int = center_x + dx - origin_x
					var local_z: int = center_z + dz - origin_z
					if local_x < 0 or local_x >= VoxelDefsScript.CHUNK_SIZE or local_z < 0 or local_z >= VoxelDefsScript.CHUNK_SIZE:
						continue
					var column: int = local_x + local_z * VoxelDefsScript.DATA_STRIDE_Z
					if solid_y[column] < 0:
						continue
					var field_index: int = ChunkTerrainDataScript.cell_index(local_x, local_z)
					var biome: int = int(field.dominant_biome[field_index])
					var patch_block: int = _floor_patch_block(biomes.decoration_set(biome))
					if patch_block == BlockRegistryScript.BLOCK_AIR:
						continue
					if solid_id[column] != biomes.surface_block(biome):
						continue
					solid_id[column] = patch_block


func _floor_patch_block(decoration_set: int) -> int:
	match decoration_set:
		BiomeCatalogScript.DECORATION_PLAINS, BiomeCatalogScript.DECORATION_MEADOW, \
		BiomeCatalogScript.DECORATION_SAVANNA, BiomeCatalogScript.DECORATION_FOREST, \
		BiomeCatalogScript.DECORATION_TAIGA, BiomeCatalogScript.DECORATION_TROPICAL:
			return BlockRegistryScript.BLOCK_DIRT
		BiomeCatalogScript.DECORATION_SWAMP:
			return BlockRegistryScript.BLOCK_MUD
		BiomeCatalogScript.DECORATION_RIVERBANK, BiomeCatalogScript.DECORATION_BEACH, \
		BiomeCatalogScript.DECORATION_ALPINE, BiomeCatalogScript.DECORATION_SNOWFIELD, \
		BiomeCatalogScript.DECORATION_BADLANDS:
			return BlockRegistryScript.BLOCK_GRAVEL
	return BlockRegistryScript.BLOCK_AIR


## Low scrub bumps on the edges and clearings of groves. Grove strength is
## sampled on a coarse lattice because resolving it per column costs ~5 ms.
const LOD_COVER_STRIDE: int = 8

func _apply_lod_scrub(solid_y: PackedInt32Array, solid_id: PackedByteArray, sub_id: PackedByteArray, water_y: PackedInt32Array, field: ChunkTerrainData, origin_x: int, origin_z: int) -> int:
	if config.tree_density <= 0.0 or config.decoration_density <= 0.0:
		return 0
	var side: int = VoxelDefsScript.CHUNK_SIZE / LOD_COVER_STRIDE + 1
	var strengths := PackedFloat32Array()
	strengths.resize(side * side)
	for sample_z in side:
		for sample_x in side:
			strengths[sample_x + sample_z * side] = _tree_grove_strength(
				origin_x + sample_x * LOD_COVER_STRIDE, origin_z + sample_z * LOD_COVER_STRIDE)
	var max_y := 0
	for local_z in VoxelDefsScript.CHUNK_SIZE:
		for local_x in VoxelDefsScript.CHUNK_SIZE:
			var column: int = local_x + local_z * VoxelDefsScript.DATA_STRIDE_Z
			if solid_y[column] <= VoxelDefsScript.SEA_LEVEL or water_y[column] >= 0:
				continue
			var strength: float = _sample_scrub_strength(strengths, side, local_x, local_z)
			if strength < 0.45 or strength > 0.85:
				continue
			if WorldGenHashScript.hash_2d(config.seed + 1301, origin_x + local_x, origin_z + local_z) % 100 >= 12:
				continue
			var field_index: int = ChunkTerrainDataScript.cell_index(local_x, local_z)
			var leaf_id: int = _grove_leaf_block(biomes.decoration_set(int(field.dominant_biome[field_index])))
			if leaf_id == BlockRegistryScript.BLOCK_AIR:
				continue
			solid_y[column] += 1
			solid_id[column] = leaf_id
			sub_id[column] = leaf_id
			max_y = maxi(max_y, solid_y[column])
	return max_y


func _sample_scrub_strength(strengths: PackedFloat32Array, side: int, local_x: int, local_z: int) -> float:
	var fx: float = float(local_x) / float(LOD_COVER_STRIDE)
	var fz: float = float(local_z) / float(LOD_COVER_STRIDE)
	var x0: int = clampi(floori(fx), 0, side - 1)
	var z0: int = clampi(floori(fz), 0, side - 1)
	var x1: int = mini(x0 + 1, side - 1)
	var z1: int = mini(z0 + 1, side - 1)
	var tx: float = clampf(fx - float(x0), 0.0, 1.0)
	var tz: float = clampf(fz - float(z0), 0.0, 1.0)
	var north := lerpf(strengths[x0 + z0 * side], strengths[x1 + z0 * side], tx)
	var south := lerpf(strengths[x0 + z1 * side], strengths[x1 + z1 * side], tx)
	return lerpf(north, south, tz)


func _grove_leaf_block(decoration_set: int) -> int:
	match decoration_set:
		BiomeCatalogScript.DECORATION_FOREST:
			return BlockRegistryScript.BLOCK_LEAVES
		BiomeCatalogScript.DECORATION_TAIGA:
			return BlockRegistryScript.BLOCK_SPRUCE_LEAVES
		BiomeCatalogScript.DECORATION_TROPICAL:
			return BlockRegistryScript.BLOCK_JUNGLE_LEAVES
		BiomeCatalogScript.DECORATION_SWAMP:
			return BlockRegistryScript.BLOCK_MANGROVE_LEAVES
	return BlockRegistryScript.BLOCK_AIR


## Reject only footprints that cannot touch this chunk. Terrain/site decisions
## for every overlapping candidate remain global and generation-order independent.
func _footprint_intersects_chunk(world_x: int, world_z: int, radius: int, origin_x: int, origin_z: int) -> bool:
	return world_x + radius >= origin_x and world_z + radius >= origin_z \
		and world_x - radius < origin_x + VoxelDefsScript.CHUNK_SIZE \
		and world_z - radius < origin_z + VoxelDefsScript.CHUNK_SIZE


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
		DecorationCatalog.FEATURE_BUSH:
			return _stamp_bush(data, origin_x, origin_z, world_x, ground_y, world_z, hash_value)
		DecorationCatalog.FEATURE_PEBBLE:
			return _stamp_pebble(data, origin_x, origin_z, world_x, ground_y, world_z, hash_value)
		DecorationCatalog.FEATURE_ROCK_OUTCROP:
			return _stamp_rock_outcrop(data, origin_x, origin_z, world_x, ground_y, world_z, hash_value)
		DecorationCatalog.FEATURE_STUMP:
			return _stamp_stump(data, origin_x, origin_z, world_x, ground_y, world_z, hash_value)
		DecorationCatalog.FEATURE_DEAD_TREE:
			return _stamp_dead_tree(data, origin_x, origin_z, world_x, ground_y, world_z, hash_value)
		DecorationCatalog.FEATURE_LARGE_TREE:
			return _stamp_tree(data, origin_x, origin_z, world_x, ground_y, world_z, BlockRegistryScript.BLOCK_LOG, BlockRegistryScript.BLOCK_LEAVES, 6 + hash_value % 3, 3, hash_value)
		DecorationCatalog.FEATURE_ANCIENT_TREE:
			return _stamp_tree(data, origin_x, origin_z, world_x, ground_y, world_z, BlockRegistryScript.BLOCK_LOG, BlockRegistryScript.BLOCK_LEAVES, 8 + hash_value % 4, 3, hash_value)
		DecorationCatalog.FEATURE_DRIFTWOOD:
			return _stamp_fallen_log(data, origin_x, origin_z, world_x, ground_y, world_z, hash_value)
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


## One or two loose cobbles. A single block reads as a stone in the grass; a
## second block extends it along one axis instead of forming a symmetric cross.
func _stamp_pebble(data: PackedByteArray, origin_x: int, origin_z: int, world_x: int, ground_y: int, world_z: int, hash_value: int) -> int:
	_place(data, origin_x, origin_z, world_x, ground_y + 1, world_z, BlockRegistryScript.BLOCK_STONE)
	if hash_value % 2 == 0:
		var direction: Vector2i = VoxelDefsScript.DIRS_4[(hash_value / 13) % 4]
		_place(data, origin_x, origin_z, world_x + direction.x, ground_y + 1, world_z + direction.y, BlockRegistryScript.BLOCK_STONE)
	return ground_y + 1


## An irregular cobble boulder for rocky biomes: a short base along one or two
## axes with one raised cap. Single-material and asymmetric so it reads as a
## natural rock instead of a built cross.
func _stamp_rock_outcrop(data: PackedByteArray, origin_x: int, origin_z: int, world_x: int, ground_y: int, world_z: int, hash_value: int) -> int:
	var block_id: int = BlockRegistryScript.BLOCK_COBBLESTONE
	var first: Vector2i = VoxelDefsScript.DIRS_4[hash_value % 4]
	var second: Vector2i = VoxelDefsScript.DIRS_4[(hash_value / 7) % 4]
	_place(data, origin_x, origin_z, world_x, ground_y + 1, world_z, block_id)
	_place(data, origin_x, origin_z, world_x + first.x, ground_y + 1, world_z + first.y, block_id)
	if second != first and hash_value % 2 == 0:
		_place(data, origin_x, origin_z, world_x + second.x, ground_y + 1, world_z + second.y, block_id)
	var cap_x := world_x + (first.x if hash_value % 3 != 0 else 0)
	var cap_z := world_z + (first.y if hash_value % 3 != 0 else 0)
	var top := _place(data, origin_x, origin_z, cap_x, ground_y + 2, cap_z, block_id)
	return top if top >= 0 else ground_y + 1


## A cut trunk with a root nub: the leftover of a felled tree.
func _stamp_stump(data: PackedByteArray, origin_x: int, origin_z: int, world_x: int, ground_y: int, world_z: int, hash_value: int) -> int:
	var height: int = 1 + (hash_value / 7) % 2
	for y in range(1, height + 1):
		_place(data, origin_x, origin_z, world_x, ground_y + y, world_z, BlockRegistryScript.BLOCK_LOG)
	var direction: Vector2i = VoxelDefsScript.DIRS_4[hash_value % 4]
	_place(data, origin_x, origin_z, world_x + direction.x, ground_y + 1, world_z + direction.y, BlockRegistryScript.BLOCK_MANGROVE_ROOTS)
	return ground_y + height


## A bare trunk with one or two branches and no canopy.
func _stamp_dead_tree(data: PackedByteArray, origin_x: int, origin_z: int, world_x: int, ground_y: int, world_z: int, hash_value: int) -> int:
	var height: int = 4 + hash_value % 3
	for y in range(1, height + 1):
		_place(data, origin_x, origin_z, world_x, ground_y + y, world_z, BlockRegistryScript.BLOCK_LOG)
	var branches: int = 1 + (hash_value / 11) % 2
	for branch in branches:
		var direction: Vector2i = VoxelDefsScript.DIRS_4[(hash_value / (17 + branch * 7)) % 4]
		var branch_y: int = ground_y + height - 1 - branch
		_place(data, origin_x, origin_z, world_x + direction.x, branch_y, world_z + direction.y, BlockRegistryScript.BLOCK_LOG)
		if hash_value % 2 == 0:
			_place(data, origin_x, origin_z, world_x + direction.x * 2, branch_y, world_z + direction.y * 2, BlockRegistryScript.BLOCK_LOG)
	return ground_y + height


## Short leaf cluster between ground cover and trees: one core column plus an
## optional side leaf keeps the footprint tiny and never collides with a trunk.
func _stamp_bush(data: PackedByteArray, origin_x: int, origin_z: int, world_x: int, ground_y: int, world_z: int, hash_value: int) -> int:
	var height: int = 1 + hash_value % 2
	for y in range(1, height + 1):
		_place(data, origin_x, origin_z, world_x, ground_y + y, world_z, BlockRegistryScript.BLOCK_LEAVES)
	if height > 1 and hash_value % 3 != 0:
		var direction: Vector2i = VoxelDefsScript.DIRS_4[hash_value % 4]
		_place(data, origin_x, origin_z, world_x + direction.x, ground_y + height, world_z + direction.y, BlockRegistryScript.BLOCK_LEAVES)
	return ground_y + height


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
		return FLAT_VOXEL_SURFACE_Y
	return clampi(roundi(field.final_height[field_index]), 2, VoxelDefsScript.WORLD_HEIGHT - 2)


func _index(local_x: int, y: int, local_z: int) -> int:
	return local_x + local_z * VoxelDefsScript.DATA_STRIDE_Z + y * VoxelDefsScript.DATA_STRIDE_Y


func _smoothstep(edge0: float, edge1: float, value: float) -> float:
	var t: float = clampf((value - edge0) / (edge1 - edge0), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)
