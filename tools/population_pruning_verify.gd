## Focused regression coverage for population candidate pruning.  It deliberately
## exercises private stamp/population helpers: a candidate whose footprint cannot
## touch a chunk must not reach the terrain sampler, while every candidate that
## can touch it must retain its original clipped output.
extends SceneTree

const VoxelPopulatorScript = preload("res://world/worldgen/voxel_populator.gd")
const WorldGenConfigScript = preload("res://world/worldgen/world_gen_config.gd")
const BiomeCatalogScript = preload("res://world/worldgen/biome_catalog.gd")
const ChunkTerrainDataScript = preload("res://world/worldgen/chunk_terrain_data.gd")
const DecorationCatalogScript = preload("res://world/worldgen/decoration_catalog.gd")
const StructureCatalogScript = preload("res://world/worldgen/structure_catalog.gd")
const TerrainSamplerScript = preload("res://world/worldgen/terrain_sampler.gd")
const WorldGenHashScript = preload("res://world/worldgen/world_gen_hash.gd")
const BlockRegistryScript = preload("res://world/block_registry.gd")
const VoxelDefsScript = preload("res://world/voxel_defs.gd")

const HASHES: Array[int] = [0, 1, 2, 7, 31, 127, 1023, 918273]
const LAND_FEATURES: Array[int] = [
	DecorationCatalogScript.FEATURE_OAK, DecorationCatalogScript.FEATURE_BIRCH,
	DecorationCatalogScript.FEATURE_SPRUCE, DecorationCatalogScript.FEATURE_ACACIA,
	DecorationCatalogScript.FEATURE_JUNGLE, DecorationCatalogScript.FEATURE_MANGROVE,
	DecorationCatalogScript.FEATURE_CACTUS, DecorationCatalogScript.FEATURE_TALL_GRASS,
	DecorationCatalogScript.FEATURE_YELLOW_FLOWER, DecorationCatalogScript.FEATURE_RED_FLOWER,
	DecorationCatalogScript.FEATURE_DEAD_BUSH, DecorationCatalogScript.FEATURE_BAMBOO,
	DecorationCatalogScript.FEATURE_VINE, DecorationCatalogScript.FEATURE_BOULDER,
	DecorationCatalogScript.FEATURE_FALLEN_LOG, DecorationCatalogScript.FEATURE_MELON,
	DecorationCatalogScript.FEATURE_BROWN_MUSHROOM, DecorationCatalogScript.FEATURE_RED_MUSHROOM,
	DecorationCatalogScript.FEATURE_REEDS, DecorationCatalogScript.FEATURE_BUSH,
	DecorationCatalogScript.FEATURE_PEBBLE, DecorationCatalogScript.FEATURE_ROCK_OUTCROP,
	DecorationCatalogScript.FEATURE_STUMP, DecorationCatalogScript.FEATURE_DEAD_TREE,
	DecorationCatalogScript.FEATURE_LARGE_TREE, DecorationCatalogScript.FEATURE_DRIFTWOOD,
	DecorationCatalogScript.FEATURE_ANCIENT_TREE,
]

var _failures := PackedStringArray()


class CountingTerrainSampler:
	extends TerrainSamplerScript

	var ground := Vector2i(72, BiomeCatalogScript.FOREST)
	var calls := {}

	func sample_decoration_ground(x: int, z: int) -> Vector2i:
		var position := Vector2i(x, z)
		calls[position] = int(calls.get(position, 0)) + 1
		return ground


func _initialize() -> void:
	_verify_inclusive_bounds()
	_verify_land_feature_footprints_and_heights()
	_verify_underwater_species_footprints_and_heights()
	_verify_structure_clear_halo()
	_verify_versioned_catalog_coverage()
	_verify_land_candidate_pruning()
	_verify_tree_candidate_pruning()
	_verify_underwater_candidate_pruning()
	_verify_population_max_y()
	if _failures.is_empty():
		print("POPULATION PRUNING VERIFY: PASS")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("POPULATION PRUNING VERIFY: FAIL (", _failures.size(), ")")
	quit(1)


func _verify_inclusive_bounds() -> void:
	var populator := _populator()
	# Chunk coverage is [origin, origin + size - 1].  A radius touching either
	# endpoint must be kept, including in negative coordinate space.
	for origin in [Vector2i(0, 0), Vector2i(-32, -48)]:
		var end_x: int = origin.x + VoxelDefsScript.CHUNK_SIZE - 1
		var end_z: int = origin.y + VoxelDefsScript.CHUNK_SIZE - 1
		_expect(populator._footprint_intersects_chunk(origin.x - 3, origin.y - 3, 3, origin.x, origin.y),
			"lower inclusive footprint edge was rejected at %s" % origin)
		_expect(populator._footprint_intersects_chunk(end_x + 3, end_z + 3, 3, origin.x, origin.y),
			"upper inclusive footprint edge was rejected at %s" % origin)
		_expect(not populator._footprint_intersects_chunk(origin.x - 4, origin.y, 3, origin.x, origin.y),
			"lower non-overlap footprint was retained at %s" % origin)
		_expect(not populator._footprint_intersects_chunk(end_x + 4, end_z, 3, origin.x, origin.y),
			"upper non-overlap footprint was retained at %s" % origin)
		_expect(populator._footprint_intersects_chunk(origin.x, origin.y, 0, origin.x, origin.y),
			"point at chunk origin was rejected at %s" % origin)
		_expect(populator._footprint_intersects_chunk(end_x, end_z, 0, origin.x, origin.y),
			"point at chunk end was rejected at %s" % origin)
		_expect(not populator._footprint_intersects_chunk(end_x + 1, end_z, 0, origin.x, origin.y),
			"point beyond chunk end was retained at %s" % origin)


func _verify_land_feature_footprints_and_heights() -> void:
	var populator := _populator()
	for feature in LAND_FEATURES:
		for hash_value in HASHES:
			var blocks := _collect_land_stamp(populator, feature, hash_value)
			_expect(not blocks.is_empty(), "feature %d hash %d stamped nothing" % [feature, hash_value])
			for position: Vector3i in blocks:
				_expect(maxi(absi(position.x - 8), absi(position.z - 8)) <= VoxelPopulatorScript.FEATURE_FOOTPRINT_RADIUS,
					"feature %d hash %d exceeded FEATURE_FOOTPRINT_RADIUS at %s" % [feature, hash_value, position])
			var central := _empty_data()
			var reported: int = populator._stamp_feature(central, 0, 0, 8, 72, 8, feature, hash_value)
			# A few one-cell feature branches intentionally return an inexpensive
			# conservative hint. populate() subsequently canonicalizes it through
			# _actual_max_y; never permit a hint below the real stamp.
			_expect(reported >= _max_y(central), "feature %d hash %d underreported max_y %d < %d" % [feature, hash_value, reported, _max_y(central)])


func _verify_underwater_species_footprints_and_heights() -> void:
	var populator := _populator()
	var species: Array[int] = [
		DecorationCatalogScript.FEATURE_SEAGRASS, DecorationCatalogScript.FEATURE_KELP,
		DecorationCatalogScript.FEATURE_CORAL_FAN, DecorationCatalogScript.FEATURE_CORAL_BRANCH,
		DecorationCatalogScript.FEATURE_SPONGE, DecorationCatalogScript.FEATURE_ANEMONE,
	]
	for feature in species:
		for hash_value in HASHES:
			var data := _water_data()
			var reported: int = populator._stamp_underwater_plant(data, 0, 0, 8, 28, 8, feature, hash_value, 20)
			var actual: int = _max_non_water_y(data)
			_expect(reported == actual, "underwater feature %d hash %d returned max_y %d, wrote %d" % [feature, hash_value, reported, actual])
			for position: Vector3i in _blocks_except(data, 0, 0, BlockRegistryScript.BLOCK_WATER):
				_expect(position.x == 8 and position.z == 8,
					"underwater feature %d hash %d exceeded its point stamp at %s" % [feature, hash_value, position])


func _verify_structure_clear_halo() -> void:
	var populator := _populator()
	var anchor := Vector2i(16, -16)
	var ground_y := 72
	for origin in [Vector2i(0, -32), Vector2i(16, -16), Vector2i(32, 0)]:
		var data := _filled_data(BlockRegistryScript.BLOCK_TALL_GRASS)
		populator._clear_structure_volume(data, origin.x, origin.y, anchor, ground_y)
		for local_z in VoxelDefsScript.CHUNK_SIZE:
			for local_x in VoxelDefsScript.CHUNK_SIZE:
				var world_x: int = origin.x + local_x
				var world_z: int = origin.y + local_z
				var in_halo: bool = absi(world_x - anchor.x) <= StructureCatalogScript.HORIZONTAL_HALO \
					and absi(world_z - anchor.y) <= StructureCatalogScript.HORIZONTAL_HALO
				for y in range(ground_y + 1, ground_y + StructureCatalogScript.CLEAR_HEIGHT + 1):
					var cleared: bool = data[_index(local_x, y, local_z)] == BlockRegistryScript.BLOCK_AIR
					_expect(cleared == in_halo, "structure clear halo mismatch at (%d, %d, %d)" % [world_x, y, world_z])
	for kind in [StructureCatalogScript.TYPE_ABANDONED_CAMP, StructureCatalogScript.TYPE_STONE_WATCHTOWER]:
		for orientation in range(4):
			for offset_z in range(-StructureCatalogScript.HORIZONTAL_HALO - 2, StructureCatalogScript.HORIZONTAL_HALO + 3):
				for offset_x in range(-StructureCatalogScript.HORIZONTAL_HALO - 2, StructureCatalogScript.HORIZONTAL_HALO + 3):
					for local_y in range(1, StructureCatalogScript.max_height(kind) + 1):
						if StructureCatalogScript.block_at(kind, orientation, offset_x, local_y, offset_z) != BlockRegistryScript.BLOCK_AIR:
							_expect(absi(offset_x) <= StructureCatalogScript.HORIZONTAL_HALO and absi(offset_z) <= StructureCatalogScript.HORIZONTAL_HALO,
								"structure kind %d orientation %d escaped clear halo" % [kind, orientation])


func _verify_versioned_catalog_coverage() -> void:
	for version in range(1, 15):
		var catalog := DecorationCatalogScript.new(version)
		var seen := {}
		for set_id in [BiomeCatalogScript.DECORATION_PLAINS, BiomeCatalogScript.DECORATION_MEADOW,
			BiomeCatalogScript.DECORATION_SAVANNA, BiomeCatalogScript.DECORATION_FOREST,
			BiomeCatalogScript.DECORATION_DESERT, BiomeCatalogScript.DECORATION_SWAMP,
			BiomeCatalogScript.DECORATION_RIVERBANK, BiomeCatalogScript.DECORATION_BEACH,
			BiomeCatalogScript.DECORATION_TROPICAL, BiomeCatalogScript.DECORATION_TAIGA,
			BiomeCatalogScript.DECORATION_SNOWFIELD, BiomeCatalogScript.DECORATION_BADLANDS,
			BiomeCatalogScript.DECORATION_ALPINE]:
			for entry in catalog.entries_for_set(set_id):
				seen[int(entry[0])] = true
		for feature in seen:
			_expect(LAND_FEATURES.has(feature), "v%d catalog exposes an untested land feature %d" % [version, feature])
		# V1-v10 use legacy aquifers and v11-v14 use global regions, but neither
		# changes a surface stamp's footprint.  Keep every legacy catalog row in
		# this verifier so pruning cannot silently drop old saved-world output.
		_expect(not seen.is_empty(), "v%d decoration catalog is unexpectedly empty" % version)


func _verify_land_candidate_pruning() -> void:
	var sampler := CountingTerrainSampler.new()
	var populator := _populator(sampler, 1.0, 0.0)
	var origin := Vector2i(0, 0)
	var field := _field(0, 0, 72, BiomeCatalogScript.PLAINS)
	populator._decorate(_empty_data(), field, origin.x, origin.y, 72, VoxelPopulatorScript.DecorationGroundScratch.new())
	var excluded := _feature_anchors(origin, VoxelPopulatorScript.FEATURE_HALO, VoxelPopulatorScript.FEATURE_FOOTPRINT_RADIUS, false)
	_expect(not excluded.is_empty(), "feature-pruning fixture found no non-overlapping anchors")
	for anchor: Vector2i in excluded:
		_expect(not sampler.calls.has(anchor), "non-overlapping feature candidate queried terrain at %s" % anchor)
	_expect(not sampler.calls.is_empty(), "overlapping land candidates no longer queried terrain")


func _verify_tree_candidate_pruning() -> void:
	var sampler := CountingTerrainSampler.new()
	var populator := _populator(sampler)
	var origin := Vector2i(-32, -32)
	var field := _field(-2, -2, 72, BiomeCatalogScript.SAVANNA)
	populator._collect_trees(field, origin.x, origin.y, VoxelPopulatorScript.DecorationGroundScratch.new())
	# The grove lattice is already enumerated at its exact radius. Sparse trees
	# retain the wider legacy feature owner range, where pruning has work to do.
	var excluded := _feature_anchors(origin, VoxelPopulatorScript.FEATURE_HALO, VoxelPopulatorScript.FEATURE_FOOTPRINT_RADIUS, false)
	_expect(not excluded.is_empty(), "tree-pruning fixture found no non-overlapping anchors")
	for anchor: Vector2i in excluded:
		_expect(not sampler.calls.has(anchor), "non-overlapping tree candidate queried terrain at %s" % anchor)
	_expect(not sampler.calls.is_empty(), "overlapping tree candidates no longer queried terrain")


func _verify_underwater_candidate_pruning() -> void:
	var sampler := CountingTerrainSampler.new()
	sampler.ground = Vector2i(30, BiomeCatalogScript.KELP_FOREST)
	var populator := _populator(sampler)
	var origin := Vector2i(0, -32)
	var field := _field(0, -2, 30, BiomeCatalogScript.KELP_FOREST)
	populator._decorate_underwater(_water_data(), field, origin.x, origin.y, 48, VoxelPopulatorScript.DecorationGroundScratch.new())
	var excluded := _underwater_anchors(origin, false)
	_expect(not excluded.is_empty(), "underwater-pruning fixture found no non-overlapping anchors")
	for anchor: Vector2i in excluded:
		_expect(not sampler.calls.has(anchor), "non-overlapping underwater center queried terrain at %s" % anchor)
	_expect(not sampler.calls.is_empty(), "overlapping underwater candidates no longer queried terrain")


func _verify_population_max_y() -> void:
	for version in range(1, 15):
		var populator := _populator(null, 1.0, 1.0, version)
		var field := _field(0, 0, 72, BiomeCatalogScript.FOREST)
		var full: Dictionary = populator.populate(Vector2i.ZERO, field, {}, true)
		_expect(int(full.max_y) == _max_y(full.data), "v%d full population max_y is stale" % version)
		var lod: Dictionary = populator.populate_lod(Vector2i.ZERO, field)
		var compact_max := -1
		for column in VoxelDefsScript.CHUNK_AREA:
			compact_max = maxi(compact_max, maxi(int(lod.solid_y[column]), int(lod.water_y[column])))
		_expect(int(lod.max_y) == compact_max, "v%d compact LOD max_y is stale" % version)


func _collect_land_stamp(populator: VoxelPopulator, feature: int, hash_value: int) -> Dictionary:
	var blocks := {}
	for origin_z in [-16, 0, 16]:
		for origin_x in [-16, 0, 16]:
			var data := _empty_data()
			populator._stamp_feature(data, origin_x, origin_z, 8, 72, 8, feature, hash_value)
			for position: Vector3i in _blocks_except(data, origin_x, origin_z, BlockRegistryScript.BLOCK_AIR):
				blocks[position] = true
	return blocks


func _feature_anchors(origin: Vector2i, halo: int, radius: int, want_overlap: bool) -> Array[Vector2i]:
	var anchors: Array[Vector2i] = []
	var first_x: int = WorldGenHashScript.floor_div(origin.x - halo, VoxelPopulatorScript.FEATURE_CELL_SIZE)
	var last_x: int = WorldGenHashScript.floor_div(origin.x + VoxelDefsScript.CHUNK_SIZE - 1 + halo, VoxelPopulatorScript.FEATURE_CELL_SIZE)
	var first_z: int = WorldGenHashScript.floor_div(origin.y - halo, VoxelPopulatorScript.FEATURE_CELL_SIZE)
	var last_z: int = WorldGenHashScript.floor_div(origin.y + VoxelDefsScript.CHUNK_SIZE - 1 + halo, VoxelPopulatorScript.FEATURE_CELL_SIZE)
	var probe := _populator()
	for cell_z in range(first_z, last_z + 1):
		for cell_x in range(first_x, last_x + 1):
			var hash_value: int = WorldGenHashScript.hash_2d(918273 + 1103, cell_x, cell_z)
			var anchor := Vector2i(cell_x * VoxelPopulatorScript.FEATURE_CELL_SIZE + 1 + hash_value % 6,
				cell_z * VoxelPopulatorScript.FEATURE_CELL_SIZE + 1 + (hash_value / 31) % 6)
			if probe._footprint_intersects_chunk(anchor.x, anchor.y, radius, origin.x, origin.y) == want_overlap:
				anchors.append(anchor)
	return anchors


func _underwater_anchors(origin: Vector2i, want_overlap: bool) -> Array[Vector2i]:
	var anchors: Array[Vector2i] = []
	var first_x: int = WorldGenHashScript.floor_div(origin.x - VoxelPopulatorScript.UNDERWATER_HALO, VoxelPopulatorScript.UNDERWATER_CELL_SIZE)
	var last_x: int = WorldGenHashScript.floor_div(origin.x + VoxelDefsScript.CHUNK_SIZE - 1 + VoxelPopulatorScript.UNDERWATER_HALO, VoxelPopulatorScript.UNDERWATER_CELL_SIZE)
	var first_z: int = WorldGenHashScript.floor_div(origin.y - VoxelPopulatorScript.UNDERWATER_HALO, VoxelPopulatorScript.UNDERWATER_CELL_SIZE)
	var last_z: int = WorldGenHashScript.floor_div(origin.y + VoxelDefsScript.CHUNK_SIZE - 1 + VoxelPopulatorScript.UNDERWATER_HALO, VoxelPopulatorScript.UNDERWATER_CELL_SIZE)
	var probe := _populator()
	for cell_z in range(first_z, last_z + 1):
		for cell_x in range(first_x, last_x + 1):
			var hash_value: int = WorldGenHashScript.hash_2d(918273 + 1423, cell_x, cell_z)
			var anchor := Vector2i(cell_x * VoxelPopulatorScript.UNDERWATER_CELL_SIZE + 2 + hash_value % 2,
				cell_z * VoxelPopulatorScript.UNDERWATER_CELL_SIZE + 2 + (hash_value / 29) % 2)
			if probe._footprint_intersects_chunk(anchor.x, anchor.y, VoxelPopulatorScript.UNDERWATER_TUFT_RADIUS, origin.x, origin.y) == want_overlap:
				anchors.append(anchor)
	return anchors


func _populator(sampler: TerrainSampler = null, tree_density: float = 1.0, decoration_density: float = 1.0, version: int = 14) -> VoxelPopulator:
	return VoxelPopulatorScript.new(WorldGenConfigScript.new({"seed": 918273, "tree_density": tree_density,
		"decoration_density": decoration_density, "cave_density": 0.0, "worldgen_version": version}), BiomeCatalogScript.new(), sampler)


func _field(chunk_x: int, chunk_z: int, height: int, biome: int) -> ChunkTerrainData:
	var field := ChunkTerrainDataScript.new(chunk_x, chunk_z)
	for index in ChunkTerrainDataScript.CELL_COUNT:
		field.set_height(index, height, height, height, 0.0)
		field.set_biome(index, biome, biome, 0, biome)
	field.seal()
	return field


func _empty_data() -> PackedByteArray:
	var data := PackedByteArray()
	data.resize(VoxelDefsScript.CHUNK_AREA * VoxelDefsScript.WORLD_HEIGHT)
	return data


func _filled_data(block_id: int) -> PackedByteArray:
	var data := _empty_data()
	data.fill(block_id)
	return data


func _water_data() -> PackedByteArray:
	return _filled_data(BlockRegistryScript.BLOCK_WATER)


func _blocks_except(data: PackedByteArray, origin_x: int, origin_z: int, excluded_id: int) -> Array[Vector3i]:
	var blocks: Array[Vector3i] = []
	for y in VoxelDefsScript.WORLD_HEIGHT:
		for local_z in VoxelDefsScript.CHUNK_SIZE:
			for local_x in VoxelDefsScript.CHUNK_SIZE:
				if data[_index(local_x, y, local_z)] != excluded_id:
					blocks.append(Vector3i(origin_x + local_x, y, origin_z + local_z))
	return blocks


func _max_y(data: PackedByteArray) -> int:
	for y in range(VoxelDefsScript.WORLD_HEIGHT - 1, -1, -1):
		for local_z in VoxelDefsScript.CHUNK_SIZE:
			for local_x in VoxelDefsScript.CHUNK_SIZE:
				if data[_index(local_x, y, local_z)] != BlockRegistryScript.BLOCK_AIR:
					return y
	return 0


func _max_non_water_y(data: PackedByteArray) -> int:
	for y in range(VoxelDefsScript.WORLD_HEIGHT - 1, -1, -1):
		for local_z in VoxelDefsScript.CHUNK_SIZE:
			for local_x in VoxelDefsScript.CHUNK_SIZE:
				var id: int = data[_index(local_x, y, local_z)]
				if id != BlockRegistryScript.BLOCK_AIR and id != BlockRegistryScript.BLOCK_WATER:
					return y
	return -1


func _index(local_x: int, y: int, local_z: int) -> int:
	return local_x + local_z * VoxelDefsScript.DATA_STRIDE_Z + y * VoxelDefsScript.DATA_STRIDE_Y


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
