## Focused regression coverage for versioned world-generation audit fixes.
extends SceneTree

const DecorationCatalogScript = preload("res://world/worldgen/decoration_catalog.gd")
const VoxelPopulatorScript = preload("res://world/worldgen/voxel_populator.gd")
const WorldGenConfigScript = preload("res://world/worldgen/world_gen_config.gd")
const BiomeCatalogScript = preload("res://world/worldgen/biome_catalog.gd")
const ChunkTerrainDataScript = preload("res://world/worldgen/chunk_terrain_data.gd")
const BlockRegistryScript = preload("res://world/block_registry.gd")
const VoxelDefsScript = preload("res://world/voxel_defs.gd")

const OCEAN_ORIGIN_SEED: int = 123456789
const OCEAN_FIXTURE_ORIGIN := Vector2i(-440, -512)
const MAX_SPAWN_TIME_MSEC: float = 2000.0

var _failures := PackedStringArray()


func _initialize() -> void:
	_verify_large_tree_version_gate()
	_verify_ocean_origin_spawn()
	_verify_versioned_lava_basins()
	if _failures.is_empty():
		print("WORLDGEN AUDIT VERIFY: PASS")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("WORLDGEN AUDIT VERIFY: FAIL (", _failures.size(), ")")
	quit(1)


func _verify_large_tree_version_gate() -> void:
	for version in range(1, 11):
		var legacy := DecorationCatalogScript.new(version)
		_expect(not _contains_large_tree(legacy.tree_entries_for_set(BiomeCatalogScript.DECORATION_FOREST)),
			"v%d forest catalog still exposes FEATURE_LARGE_TREE" % version)
		_expect(not _contains_large_tree(legacy.tree_entries_for_set(BiomeCatalogScript.DECORATION_TROPICAL)),
			"v%d tropical catalog still exposes FEATURE_LARGE_TREE" % version)

	var current := DecorationCatalogScript.new(11)
	var forest_entry := _large_tree_entry(current.tree_entries_for_set(BiomeCatalogScript.DECORATION_FOREST))
	var tropical_entry := _large_tree_entry(current.tree_entries_for_set(BiomeCatalogScript.DECORATION_TROPICAL))
	_expect(not forest_entry.is_empty() and float(forest_entry[2]) > 0.0,
		"v11 forest FEATURE_LARGE_TREE lacks a nonzero occurrence chance")
	_expect(not tropical_entry.is_empty() and float(tropical_entry[2]) > 0.0,
		"v11 tropical FEATURE_LARGE_TREE lacks a nonzero occurrence chance")
	_expect(_selects_large_tree(current, BiomeCatalogScript.DECORATION_FOREST),
		"v11 forest large tree is unreachable through tree selection")
	_expect(_selects_large_tree(current, BiomeCatalogScript.DECORATION_TROPICAL),
		"v11 tropical large tree is unreachable through tree selection")

	var populator := VoxelPopulatorScript.new(WorldGenConfigScript.new({"worldgen_version": 11}), BiomeCatalogScript.new())
	var data := PackedByteArray()
	data.resize(VoxelDefsScript.CHUNK_AREA * VoxelDefsScript.WORLD_HEIGHT)
	var highest: int = populator._stamp_feature(data, 0, 0, 8, 48, 8,
		DecorationCatalogScript.FEATURE_LARGE_TREE, 918273)
	_expect(highest > 48 and data.count(BlockRegistryScript.BLOCK_LOG) > 0
		and data.count(BlockRegistryScript.BLOCK_LEAVES) > 0,
		"v11 FEATURE_LARGE_TREE stamp produced no complete tree")


func _verify_ocean_origin_spawn() -> void:
	var generator := TerrainGenerator.new()
	generator.configure({"seed": OCEAN_ORIGIN_SEED, "worldgen_version": 11})
	var origin := generator.sample_point(OCEAN_FIXTURE_ORIGIN.x, OCEAN_FIXTURE_ORIGIN.y)
	var origin_biome: int = int(origin["dominant_biome_id"])
	_expect(BiomeCatalogScript.new().is_ocean_biome(origin_biome),
		"pinned ocean fixture is not ocean for seed %d at %s" % [OCEAN_ORIGIN_SEED, OCEAN_FIXTURE_ORIGIN])
	var start_us := Time.get_ticks_usec()
	var first := generator.find_spawn_position()
	var elapsed_msec: float = float(Time.get_ticks_usec() - start_us) / 1000.0
	var second := generator.find_spawn_position()
	var spawn_sample := generator.sample_point(floori(first.x), floori(first.z))
	var spawn_biome: int = int(spawn_sample["dominant_biome_id"])
	var spawn_height: float = float(spawn_sample["final_height"])
	var spawn_slope: float = float(spawn_sample["slope"])
	_expect(first == second, "ocean-origin spawn search is not deterministic")
	_expect(not BiomeCatalogScript.new().is_ocean_biome(spawn_biome)
		and spawn_biome not in [BiomeCatalogScript.BEACH, BiomeCatalogScript.RIVER, BiomeCatalogScript.SWAMP],
		"ocean-origin spawn did not reject water-adjacent biomes")
	_expect(spawn_height > VoxelDefsScript.SEA_LEVEL + 2 and spawn_slope < 2.2,
		"ocean-origin spawn did not return safe dry, level land")
	_expect(elapsed_msec <= MAX_SPAWN_TIME_MSEC,
		"ocean-origin spawn search exceeded generous %.0f ms ceiling (%.3f ms)" % [MAX_SPAWN_TIME_MSEC, elapsed_msec])
	print("WORLDGEN AUDIT SPAWN: seed=%d ocean_origin=%s biome=%d position=%s elapsed_ms=%.3f" % [
		OCEAN_ORIGIN_SEED, OCEAN_FIXTURE_ORIGIN, spawn_biome, first, elapsed_msec])


func _verify_versioned_lava_basins() -> void:
	const center := Vector3i(8, 20, 8)
	const radius := 4
	var v10 := VoxelPopulatorScript.new(WorldGenConfigScript.new({"worldgen_version": 10}), BiomeCatalogScript.new())
	var legacy_data := _lava_fixture(0, center, radius)
	v10._fill_lava_lake(legacy_data, ChunkTerrainDataScript.new(0, 0), center, radius)
	var legacy_count := legacy_data.count(BlockRegistryScript.BLOCK_LAVA)
	_expect(legacy_count > 0, "v10 legacy lava fixture produced no lava")
	_expect(_lava_only_at_y(legacy_data, center.y), "v10 lava fixture no longer uses its legacy one-plane fill")

	var v11 := VoxelPopulatorScript.new(WorldGenConfigScript.new({"worldgen_version": 11}), BiomeCatalogScript.new())
	var basin_data := _lava_fixture(0, center, radius)
	v11._fill_lava_lake(basin_data, ChunkTerrainDataScript.new(0, 0), center, radius)
	var basin_count := basin_data.count(BlockRegistryScript.BLOCK_LAVA)
	_expect(basin_count > legacy_count and _lava_count_at_y(basin_data, center.y - 2) > 0,
		"v11 lava basin lacks supported multi-cell depth")
	_expect(_lava_is_supported(basin_data), "v11 lava basin contains floating lava")

	const seam_center := Vector3i(16, 20, 8)
	const seam_radius := 5
	var left := _lava_fixture(0, seam_center, seam_radius)
	var right := _lava_fixture(1, seam_center, seam_radius)
	v11._fill_lava_lake(left, ChunkTerrainDataScript.new(0, 0), seam_center, seam_radius)
	v11._fill_lava_lake(right, ChunkTerrainDataScript.new(1, 0), seam_center, seam_radius)
	var repeated_left := _lava_fixture(0, seam_center, seam_radius)
	var repeated_right := _lava_fixture(1, seam_center, seam_radius)
	v11._fill_lava_lake(repeated_left, ChunkTerrainDataScript.new(0, 0), seam_center, seam_radius)
	v11._fill_lava_lake(repeated_right, ChunkTerrainDataScript.new(1, 0), seam_center, seam_radius)
	_expect(left == repeated_left and right == repeated_right, "v11 lava seam fill is not deterministic")
	_expect(_seam_lava_matches_expected(left, right, seam_center, seam_radius),
		"v11 lava basin clipped or opened across a chunk seam")
	_expect(_lava_is_supported(left) and _lava_is_supported(right),
		"v11 seam basin contains floating lava")
	print("WORLDGEN AUDIT LAVA: v10_cells=%d v11_cells=%d seam_cells=%d" % [
		legacy_count, basin_count,
		left.count(BlockRegistryScript.BLOCK_LAVA) + right.count(BlockRegistryScript.BLOCK_LAVA)])


func _contains_large_tree(entries: Array) -> bool:
	return not _large_tree_entry(entries).is_empty()


func _large_tree_entry(entries: Array) -> Array:
	for entry in entries:
		if int(entry[0]) == DecorationCatalogScript.FEATURE_LARGE_TREE:
			return entry
	return []


func _selects_large_tree(catalog: DecorationCatalog, decoration_set: int) -> bool:
	for step in range(1000):
		var entry := catalog.choose_tree(decoration_set, float(step) / 1000.0)
		if not entry.is_empty() and int(entry[0]) == DecorationCatalogScript.FEATURE_LARGE_TREE:
			return true
	return false


func _lava_fixture(chunk_x: int, center: Vector3i, radius: int) -> PackedByteArray:
	var data := PackedByteArray()
	data.resize(VoxelDefsScript.CHUNK_AREA * VoxelDefsScript.WORLD_HEIGHT)
	for y in range(center.y + 1):
		for column in VoxelDefsScript.CHUNK_AREA:
			data[column + y * VoxelDefsScript.DATA_STRIDE_Y] = BlockRegistryScript.BLOCK_STONE
	for world_z in range(center.z - radius, center.z + radius + 1):
		for world_x in range(center.x - radius, center.x + radius + 1):
			var dx: int = world_x - center.x
			var dz: int = world_z - center.z
			if dx * dx + dz * dz > radius * radius:
				continue
			var local_x: int = world_x - chunk_x * VoxelDefsScript.CHUNK_SIZE
			if local_x < 0 or local_x >= VoxelDefsScript.CHUNK_SIZE:
				continue
			var local_z: int = world_z
			if local_z < 0 or local_z >= VoxelDefsScript.CHUNK_SIZE:
				continue
			var depth := _lava_depth(dx, dz, radius)
			for y in range(center.y - depth + 1, center.y + 1):
				data[local_x + local_z * VoxelDefsScript.DATA_STRIDE_Z + y * VoxelDefsScript.DATA_STRIDE_Y] = BlockRegistryScript.BLOCK_AIR
	return data


func _lava_depth(dx: int, dz: int, radius: int) -> int:
	var radial: float = sqrt(float(dx * dx + dz * dz)) / float(maxi(radius, 1))
	return 1 + roundi((1.0 - clampf(radial, 0.0, 1.0)) * 2.0)


func _lava_only_at_y(data: PackedByteArray, expected_y: int) -> bool:
	for y in VoxelDefsScript.WORLD_HEIGHT:
		for column in VoxelDefsScript.CHUNK_AREA:
			if data[column + y * VoxelDefsScript.DATA_STRIDE_Y] == BlockRegistryScript.BLOCK_LAVA and y != expected_y:
				return false
	return true


func _lava_count_at_y(data: PackedByteArray, y: int) -> int:
	var count := 0
	for column in VoxelDefsScript.CHUNK_AREA:
		if data[column + y * VoxelDefsScript.DATA_STRIDE_Y] == BlockRegistryScript.BLOCK_LAVA:
			count += 1
	return count


func _lava_is_supported(data: PackedByteArray) -> bool:
	for y in range(1, VoxelDefsScript.WORLD_HEIGHT):
		for column in VoxelDefsScript.CHUNK_AREA:
			if data[column + y * VoxelDefsScript.DATA_STRIDE_Y] != BlockRegistryScript.BLOCK_LAVA:
				continue
			var below: int = data[column + (y - 1) * VoxelDefsScript.DATA_STRIDE_Y]
			if below == BlockRegistryScript.BLOCK_AIR or below == BlockRegistryScript.BLOCK_WATER:
				return false
	return true


func _seam_lava_matches_expected(left: PackedByteArray, right: PackedByteArray, center: Vector3i, radius: int) -> bool:
	var expected_count := 0
	for world_z in range(center.z - radius, center.z + radius + 1):
		for world_x in range(center.x - radius, center.x + radius + 1):
			var dx: int = world_x - center.x
			var dz: int = world_z - center.z
			if dx * dx + dz * dz > radius * radius:
				continue
			var depth := _lava_depth(dx, dz, radius)
			for y in range(center.y - depth + 1, center.y + 1):
				expected_count += 1
				var data := left if world_x < VoxelDefsScript.CHUNK_SIZE else right
				var local_x: int = world_x if world_x < VoxelDefsScript.CHUNK_SIZE else world_x - VoxelDefsScript.CHUNK_SIZE
				var index: int = local_x + world_z * VoxelDefsScript.DATA_STRIDE_Z + y * VoxelDefsScript.DATA_STRIDE_Y
				if data[index] != BlockRegistryScript.BLOCK_LAVA:
					return false
	return expected_count == left.count(BlockRegistryScript.BLOCK_LAVA) + right.count(BlockRegistryScript.BLOCK_LAVA)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
