extends SceneTree

const TEST_CONFIG := {
	"seed": 123456789,
	"world_type": 0,
	"terrain_scale": 1.0,
	"tree_density": 1.0,
	"macro_scale": 384.0,
	"river_density": 1.0,
	"erosion_strength": 0.55,
	"regional_erosion": 0.5,
	"cave_density": 1.0,
	"decoration_density": 1.0,
}

var _failures := PackedStringArray()

const FIELD_POINT_TOLERANCE: float = 0.001
const MAX_ADJACENT_HEIGHT_JUMP: float = 8.0
const MAX_FIELD_SLOPE: float = 8.0
# Share of 1-block steps above 2 blocks; guards against a broken-up surface.
const MAX_ROUGH_RATIO: float = 0.06

var _biomes: BiomeCatalog = BiomeCatalog.new()


func _initialize() -> void:
	var generator := TerrainGenerator.new()
	generator.configure(TEST_CONFIG)
	_verify_repeatability(generator)
	_verify_field_seams()
	_verify_sampler_parity(TEST_CONFIG, [Vector2i.ZERO, Vector2i(-3, 2), Vector2i(-6250, 6250)], "normal")
	_verify_flat_sampler()
	_verify_terrain_continuity()
	_verify_local_detail()
	_verify_surface_blankets()
	_verify_foliage_tint_blending(generator)
	_verify_ground_cover()
	_verify_props()
	_verify_seabed_sediment()
	_verify_seabed_shaping()
	_verify_underwater_vegetation()
	_verify_water_plant_meshing()
	_verify_underwater_biomes()
	_verify_edit_priority(generator)
	_verify_parallel_generation(generator)
	_verify_distribution(generator)
	if _failures.is_empty():
		print("WORLDGEN VERIFY: PASS")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("WORLDGEN VERIFY: FAIL (", _failures.size(), ")")
	quit(1)


func _verify_repeatability(generator: TerrainGenerator) -> void:
	var first := generator.generate_data(Vector2i(3, -2), {}, false)
	var second := generator.generate_data(Vector2i(3, -2), {}, false)
	_expect(first.data == second.data, "same seed/chunk produced different blocks")
	_expect(first.heights == second.heights, "same seed/chunk produced different heightmaps")
	_expect(first.max_y < VoxelDefs.WORLD_HEIGHT - 1, "generated feature reached the reserved world ceiling")


func _verify_field_seams() -> void:
	var config := WorldGenConfig.new(TEST_CONFIG)
	var sampler := TerrainSampler.new(config, TerrainProfileCatalog.new(), BiomeCatalog.new())
	var left := sampler.build_field(Vector2i.ZERO)
	var right := sampler.build_field(Vector2i(1, 0))
	for z in range(-1, VoxelDefs.CHUNK_SIZE + 1):
		var left_index := ChunkTerrainData.cell_index(VoxelDefs.CHUNK_SIZE, z)
		var right_index := ChunkTerrainData.cell_index(0, z)
		_expect(is_equal_approx(left.final_height[left_index], right.final_height[right_index]), "terrain field seam mismatch at z=%d" % z)
		_expect(is_equal_approx(left.river[left_index], right.river[right_index]), "river field seam mismatch at z=%d" % z)
		_expect(left.dominant_biome[left_index] == right.dominant_biome[right_index], "biome field seam mismatch at z=%d" % z)


func _verify_sampler_parity(config: Dictionary, chunks: Array[Vector2i], label: String) -> void:
	var sampler := TerrainSampler.new(WorldGenConfig.new(config), TerrainProfileCatalog.new(), BiomeCatalog.new())
	var cells := 0
	var height_mismatches := 0
	var primary_biome_mismatches := 0
	var dominant_biome_mismatches := 0
	var climate_mismatches := 0
	var decoration_mismatches := 0
	var beach_height_mismatches := 0
	var flat_height_mismatches := 0
	var max_height_delta := 0.0
	var max_temperature_delta := 0.0
	var max_moisture_delta := 0.0
	var expected_flat_height := float(VoxelDefs.SEA_LEVEL) + 2.0
	for chunk_pos in chunks:
		var field := sampler.build_field(chunk_pos)
		for local_z in range(-1, VoxelDefs.CHUNK_SIZE + 1):
			for local_x in range(-1, VoxelDefs.CHUNK_SIZE + 1):
				var index := ChunkTerrainData.cell_index(local_x, local_z)
				var world_x := chunk_pos.x * VoxelDefs.CHUNK_SIZE + local_x
				var world_z := chunk_pos.y * VoxelDefs.CHUNK_SIZE + local_z
				var point := sampler.sample_point(world_x, world_z)
				var decoration_ground := sampler.sample_decoration_ground(world_x, world_z)
				var field_height := float(field.final_height[index])
				var point_height := float(point["final_height"])
				var height_delta := absf(field_height - point_height)
				var temperature_delta := absf(float(field.temperature[index]) - float(point["temperature"]))
				var moisture_delta := absf(float(field.moisture[index]) - float(point["moisture"]))
				max_height_delta = maxf(max_height_delta, height_delta)
				max_temperature_delta = maxf(max_temperature_delta, temperature_delta)
				max_moisture_delta = maxf(max_moisture_delta, moisture_delta)
				if height_delta > FIELD_POINT_TOLERANCE:
					height_mismatches += 1
				if int(field.biome_id[index]) != int(point["biome_id"]):
					primary_biome_mismatches += 1
				if int(field.dominant_biome[index]) != int(point["dominant_biome_id"]):
					dominant_biome_mismatches += 1
				if temperature_delta > FIELD_POINT_TOLERANCE or moisture_delta > FIELD_POINT_TOLERANCE:
					climate_mismatches += 1
				var expected_decoration_y := clampi(roundi(point_height), 2, VoxelDefs.WORLD_HEIGHT - 2)
				if decoration_ground.x != expected_decoration_y or decoration_ground.y != int(point["dominant_biome_id"]):
					decoration_mismatches += 1
				if int(field.biome_id[index]) == BiomeCatalog.BEACH and field_height > float(VoxelDefs.SEA_LEVEL) + 1.0 + FIELD_POINT_TOLERANCE:
					beach_height_mismatches += 1
				if int(config["world_type"]) == WorldGenConfig.WORLD_TYPE_FLAT and absf(field_height - expected_flat_height) > FIELD_POINT_TOLERANCE:
					flat_height_mismatches += 1
				cells += 1
	print("WORLDGEN PARITY %s: cells=%d height_max=%.6f temperature_max=%.6f moisture_max=%.6f" % [label, cells, max_height_delta, max_temperature_delta, max_moisture_delta])
	_expect(height_mismatches == 0, "%s field/sample height parity failed in %d cells (max delta %.6f)" % [label, height_mismatches, max_height_delta])
	_expect(primary_biome_mismatches == 0, "%s field/sample primary-biome parity failed in %d cells" % [label, primary_biome_mismatches])
	_expect(dominant_biome_mismatches == 0, "%s field/sample dominant-biome parity failed in %d cells" % [label, dominant_biome_mismatches])
	_expect(climate_mismatches == 0, "%s field/sample climate parity failed in %d cells (temperature %.6f, moisture %.6f)" % [label, climate_mismatches, max_temperature_delta, max_moisture_delta])
	_expect(decoration_mismatches == 0, "%s compact decoration query parity failed in %d cells" % [label, decoration_mismatches])
	_expect(beach_height_mismatches == 0, "%s assigned beach above SEA_LEVEL + 1 in %d cells" % [label, beach_height_mismatches])
	if int(config["world_type"]) == WorldGenConfig.WORLD_TYPE_FLAT:
		_expect(flat_height_mismatches == 0, "flat field height was not constant at SEA_LEVEL + 2 in %d cells" % flat_height_mismatches)


func _verify_flat_sampler() -> void:
	var flat_config: Dictionary = TEST_CONFIG.duplicate()
	flat_config["world_type"] = WorldGenConfig.WORLD_TYPE_FLAT
	_verify_sampler_parity(flat_config, [Vector2i.ZERO, Vector2i(-4, 3), Vector2i(6250, -6250)], "flat")


func _verify_terrain_continuity() -> void:
	var seeds: Array[int] = [int(TEST_CONFIG["seed"]), 246813579, -987654321]
	var chunks: Array[Vector2i] = [Vector2i.ZERO, Vector2i(3, -2), Vector2i(16, -16), Vector2i(18, -18), Vector2i(6250, -6250), Vector2i(-6250, 6250)]
	var max_jump := 0.0
	var max_slope := 0.0
	var jump_total := 0.0
	var jump_samples := 0
	var rough_samples := 0
	for seed in seeds:
		var config: Dictionary = TEST_CONFIG.duplicate()
		config["seed"] = seed
		var sampler := TerrainSampler.new(WorldGenConfig.new(config), TerrainProfileCatalog.new(), BiomeCatalog.new())
		for chunk_pos in chunks:
			var field := sampler.build_field(chunk_pos)
			for local_z in VoxelDefs.CHUNK_SIZE:
				for local_x in VoxelDefs.CHUNK_SIZE:
					var index := ChunkTerrainData.cell_index(local_x, local_z)
					max_slope = maxf(max_slope, float(field.slope[index]))
					if local_x + 1 < VoxelDefs.CHUNK_SIZE:
						var east_index := ChunkTerrainData.cell_index(local_x + 1, local_z)
						var east_jump := absf(float(field.final_height[index]) - float(field.final_height[east_index]))
						max_jump = maxf(max_jump, east_jump)
						jump_total += east_jump
						jump_samples += 1
						if east_jump > 2.0:
							rough_samples += 1
					if local_z + 1 < VoxelDefs.CHUNK_SIZE:
						var south_index := ChunkTerrainData.cell_index(local_x, local_z + 1)
						var south_jump := absf(float(field.final_height[index]) - float(field.final_height[south_index]))
						max_jump = maxf(max_jump, south_jump)
						jump_total += south_jump
						jump_samples += 1
						if south_jump > 2.0:
							rough_samples += 1
	var mean_jump := jump_total / maxf(float(jump_samples), 1.0)
	var rough_ratio := float(rough_samples) / maxf(float(jump_samples), 1.0)
	print("WORLDGEN TERRAIN CONTINUITY: seeds=%d chunks=%d adjacent_samples=%d max_jump=%.3f mean_jump=%.3f max_slope=%.3f rough_ratio=%.4f" % [seeds.size(), chunks.size(), jump_samples, max_jump, mean_jump, max_slope, rough_ratio])
	_expect(max_jump <= MAX_ADJACENT_HEIGHT_JUMP, "terrain adjacent height jump %.3f exceeded generous limit %.3f" % [max_jump, MAX_ADJACENT_HEIGHT_JUMP])
	_expect(max_slope <= MAX_FIELD_SLOPE, "terrain slope %.3f exceeded generous limit %.3f" % [max_slope, MAX_FIELD_SLOPE])
	_expect(mean_jump <= 1.0, "normal terrain is too rough on average (adjacent delta %.3f)" % mean_jump)
	_expect(rough_ratio <= MAX_ROUGH_RATIO, "terrain surface is too broken up (%.2f%% of adjacent steps exceed 2 blocks)" % (rough_ratio * 100.0))


func _verify_local_detail() -> void:
	var profiles := TerrainProfileCatalog.new()
	var sampler := TerrainSampler.new(WorldGenConfig.new(TEST_CONFIG), profiles, BiomeCatalog.new())
	for profile in profiles.profile_count():
		var minimum := INF
		var maximum := -INF
		var bound := profiles.value(profile, TerrainProfileCatalog.FIELD_LOCAL_RELIEF) * 1.25 \
			+ profiles.value(profile, TerrainProfileCatalog.FIELD_SURFACE_DETAIL)
		for origin in [Vector2.ZERO, Vector2(100000, -100000)]:
			for z in range(0, 96, 4):
				for x in range(0, 96, 4):
					var detail := sampler._local_landform_detail(origin + Vector2(x, z), profile, profile, 0.0)
					minimum = minf(minimum, detail)
					maximum = maxf(maximum, detail)
		_expect(maximum - minimum > 0.75, "local detail disappeared for profile %d" % profile)
		_expect(maxf(absf(minimum), absf(maximum)) <= bound, "local detail exceeded its amplitude budget for profile %d" % profile)
		print("WORLDGEN LOCAL DETAIL %s: span=%.3f peak=%.3f amplitude_budget=%.3f" % [profiles.name_for(profile), maximum - minimum, maxf(absf(minimum), absf(maximum)), bound])


func _verify_edit_priority(generator: TerrainGenerator) -> void:
	var edit_position := Vector3i(2, VoxelDefs.SEA_LEVEL + 40, 2)
	var result := generator.generate_data(Vector2i.ZERO, {edit_position: BlockRegistry.BLOCK_GLOWSTONE}, false)
	var index := edit_position.x + edit_position.z * VoxelDefs.DATA_STRIDE_Z + edit_position.y * VoxelDefs.DATA_STRIDE_Y
	_expect(result.data[index] == BlockRegistry.BLOCK_GLOWSTONE, "player edit did not override procedural output")


func _verify_surface_blankets() -> void:
	var populator := VoxelPopulator.new(WorldGenConfig.new(TEST_CONFIG), BiomeCatalog.new())
	var surface_y := VoxelDefs.SEA_LEVEL + 6
	var field := ChunkTerrainData.new()
	for local_z in range(-1, VoxelDefs.CHUNK_SIZE + 1):
		for local_x in range(-1, VoxelDefs.CHUNK_SIZE + 1):
			var index := ChunkTerrainData.cell_index(local_x, local_z)
			field.set_height(index, surface_y, surface_y, surface_y, 0.0)
			field.set_climate(index, 0.8, 1.0, 0.5, 0.5)
			var dominant := BiomeCatalog.PLAINS if local_x < VoxelDefs.CHUNK_SIZE / 2 else BiomeCatalog.SNOW
			field.set_biome(index, BiomeCatalog.PLAINS, BiomeCatalog.SNOW, 96, dominant, 180)
	field.seal()
	# Surface-only generation isolates the coherent ecotone patches from caves.
	var result := populator.populate(Vector2i.ZERO, field, {}, false)
	var data: PackedByteArray = result["data"]
	for local_z in VoxelDefs.CHUNK_SIZE:
		var transitions := 0
		var previous := -1
		for local_x in VoxelDefs.CHUNK_SIZE:
			var column := local_x + local_z * VoxelDefs.DATA_STRIDE_Z
			var expected := BlockRegistry.BLOCK_GRASS if local_x < VoxelDefs.CHUNK_SIZE / 2 else BlockRegistry.BLOCK_SNOW
			var surface := int(data[column + surface_y * VoxelDefs.DATA_STRIDE_Y])
			_expect(surface == expected, "ecotone surface did not follow its coherent dominant-biome patch")
			if previous >= 0 and surface != previous:
				transitions += 1
			previous = surface
			_expect(data[column + (surface_y + 1) * VoxelDefs.DATA_STRIDE_Y] == BlockRegistry.BLOCK_AIR,
				"river mask created suspended water above sea level")
		_expect(transitions == 1, "ecotone surface patch fragmented into a checkerboard")


## Rendering tints must use the smooth primary/secondary blend, not the
## deliberately dithered dominant biome used for discrete generation choices.
func _verify_foliage_tint_blending(generator: TerrainGenerator) -> void:
	var field := ChunkTerrainData.new()
	for index in ChunkTerrainData.CELL_COUNT:
		field.set_biome(index, BiomeCatalog.PLAINS, BiomeCatalog.FOREST, 127,
			BiomeCatalog.PLAINS if index % 2 == 0 else BiomeCatalog.FOREST)
	field.seal()
	var tints := generator._build_foliage_tints(field)
	for tint in tints:
		_expect(tint.is_equal_approx(tints[0]), "foliage tint still follows dithered dominant biome")


## Tufts are a deterministic independent pass and may only stand on an actual
## grass voxel after surface generation, rather than on sampler-only terrain.
func _verify_ground_cover() -> void:
	var config: Dictionary = TEST_CONFIG.duplicate()
	config["cave_density"] = 0.0
	config["tree_density"] = 0.0
	var populator := VoxelPopulator.new(WorldGenConfig.new(config), BiomeCatalog.new())
	var field := _uniform_field(VoxelDefs.SEA_LEVEL + 5, BiomeCatalog.PLAINS)
	var first := _grass_fixture(VoxelDefs.SEA_LEVEL + 5)
	var second := _grass_fixture(VoxelDefs.SEA_LEVEL + 5)
	populator._decorate_ground_cover(first, field, 0, 0)
	populator._decorate_ground_cover(second, field, 0, 0)
	_expect(first == second, "ground cover changed between identical generation runs")
	var grass_count := 0
	for local_z in VoxelDefs.CHUNK_SIZE:
		for local_x in VoxelDefs.CHUNK_SIZE:
			var plant_index := local_x + local_z * VoxelDefs.DATA_STRIDE_Z + (VoxelDefs.SEA_LEVEL + 6) * VoxelDefs.DATA_STRIDE_Y
			if first[plant_index] != BlockRegistry.BLOCK_TALL_GRASS:
				continue
			grass_count += 1
			_expect(first[plant_index - VoxelDefs.DATA_STRIDE_Y] == BlockRegistry.BLOCK_GRASS,
				"ground cover was not placed on solid grass soil")
	_expect(grass_count > 0, "ground-cover fixture produced no tall-grass tufts")
	_expect(grass_count < VoxelDefs.CHUNK_AREA / 4, "ground cover is too dense and carpets the terrain")
	var carved_fixture := _grass_fixture(VoxelDefs.SEA_LEVEL + 5)
	var soil_index := 1 + (VoxelDefs.SEA_LEVEL + 5) * VoxelDefs.DATA_STRIDE_Y
	var target_index := 1 + (VoxelDefs.SEA_LEVEL + 6) * VoxelDefs.DATA_STRIDE_Y
	carved_fixture[soil_index] = BlockRegistry.BLOCK_AIR
	_expect(populator._place_ground_cover(carved_fixture, field, 0, 0, 1, 0, BiomeCatalog.PLAINS, 0) == -1,
		"ground cover floated above an absent soil voxel")
	_expect(carved_fixture[target_index] == BlockRegistry.BLOCK_AIR,
		"ground cover wrote into a floating target")


## Props must add their own blocks and nothing else, and floor patches must be
## deterministic and replace only the biome's surface block.
func _verify_props() -> void:
	var populator := VoxelPopulator.new(WorldGenConfig.new(TEST_CONFIG), BiomeCatalog.new())
	var surface_y := VoxelDefs.SEA_LEVEL + 5

	var pebble := _grass_fixture(surface_y)
	populator._stamp_pebble(pebble, 0, 0, 8, surface_y, 8, 12345)
	var pebble_count := 0
	for local_z in VoxelDefs.CHUNK_SIZE:
		for local_x in VoxelDefs.CHUNK_SIZE:
			var above := pebble[local_x + local_z * VoxelDefs.DATA_STRIDE_Z + (surface_y + 1) * VoxelDefs.DATA_STRIDE_Y]
			if above == BlockRegistry.BLOCK_COBBLESTONE or above == BlockRegistry.BLOCK_STONE:
				pebble_count += 1
			elif above != BlockRegistry.BLOCK_AIR:
				_expect(false, "pebble stamped an unexpected block")
	_expect(pebble_count >= 1 and pebble_count <= 3, "pebble prop size out of range (%d)" % pebble_count)

	var stump := _grass_fixture(surface_y)
	populator._stamp_stump(stump, 0, 0, 8, surface_y, 8, 33)
	var stump_logs := 0
	var stump_roots := 0
	for local_z in VoxelDefs.CHUNK_SIZE:
		for local_x in VoxelDefs.CHUNK_SIZE:
			for y in range(surface_y + 1, surface_y + 4):
				var block: int = stump[local_x + local_z * VoxelDefs.DATA_STRIDE_Z + y * VoxelDefs.DATA_STRIDE_Y]
				if block == BlockRegistry.BLOCK_LOG:
					stump_logs += 1
				elif block == BlockRegistry.BLOCK_MANGROVE_ROOTS:
					stump_roots += 1
	_expect(stump_logs >= 1 and stump_logs <= 2, "stump trunk height out of range (%d)" % stump_logs)
	_expect(stump_roots <= 1, "stump placed too many roots")

	var dead := _grass_fixture(surface_y)
	populator._stamp_dead_tree(dead, 0, 0, 8, surface_y, 8, 99)
	var dead_logs := 0
	var dead_leaves := 0
	for local_z in VoxelDefs.CHUNK_SIZE:
		for local_x in VoxelDefs.CHUNK_SIZE:
			for y in range(surface_y + 1, surface_y + 7):
				var block: int = dead[local_x + local_z * VoxelDefs.DATA_STRIDE_Z + y * VoxelDefs.DATA_STRIDE_Y]
				if block == BlockRegistry.BLOCK_LOG:
					dead_logs += 1
				elif block == BlockRegistry.BLOCK_LEAVES:
					dead_leaves += 1
	_expect(dead_logs >= 4, "dead tree trunk too short")
	_expect(dead_leaves == 0, "dead tree produced leaves")

	var large := _grass_fixture(surface_y)
	populator._stamp_tree(large, 0, 0, 8, surface_y, 8, BlockRegistry.BLOCK_LOG, BlockRegistry.BLOCK_LEAVES, 7, 3, 55)
	var large_logs := 0
	var large_leaves := 0
	for local_z in VoxelDefs.CHUNK_SIZE:
		for local_x in VoxelDefs.CHUNK_SIZE:
			for y in range(surface_y + 1, surface_y + 9):
				var block: int = large[local_x + local_z * VoxelDefs.DATA_STRIDE_Z + y * VoxelDefs.DATA_STRIDE_Y]
				if block == BlockRegistry.BLOCK_LOG:
					large_logs += 1
				elif block == BlockRegistry.BLOCK_LEAVES:
					large_leaves += 1
	_expect(large_logs >= 6, "large tree trunk too short")
	_expect(large_leaves > 0, "large tree produced no canopy")

	var field := _uniform_field(surface_y, BiomeCatalog.FOREST)
	var patch_found := false
	var patch_origin := Vector2i.ZERO
	for chunk_x in range(0, 8):
		for chunk_z in range(0, 4):
			var fixture := _grass_fixture(surface_y)
			populator._decorate_floor_patches(fixture, field, chunk_x * VoxelDefs.CHUNK_SIZE, chunk_z * VoxelDefs.CHUNK_SIZE)
			for local_z in VoxelDefs.CHUNK_SIZE:
				for local_x in VoxelDefs.CHUNK_SIZE:
					var index := local_x + local_z * VoxelDefs.DATA_STRIDE_Z + surface_y * VoxelDefs.DATA_STRIDE_Y
					if fixture[index] == BlockRegistry.BLOCK_DIRT:
						if not patch_found:
							patch_origin = Vector2i(chunk_x, chunk_z)
						patch_found = true
					elif fixture[index] != BlockRegistry.BLOCK_GRASS:
						_expect(false, "floor patch wrote an unexpected block")
	if not patch_found:
		_expect(false, "floor patch pass produced no patches for the fixture seed")
	else:
		var first := _grass_fixture(surface_y)
		var second := _grass_fixture(surface_y)
		populator._decorate_floor_patches(first, field, patch_origin.x * VoxelDefs.CHUNK_SIZE, patch_origin.y * VoxelDefs.CHUNK_SIZE)
		populator._decorate_floor_patches(second, field, patch_origin.x * VoxelDefs.CHUNK_SIZE, patch_origin.y * VoxelDefs.CHUNK_SIZE)
		_expect(first == second, "floor patches changed between identical runs")
		_expect(first != _grass_fixture(surface_y), "floor patch origin produced no patch for the comparison")


func _verify_seabed_sediment() -> void:
	var populator := VoxelPopulator.new(WorldGenConfig.new(TEST_CONFIG), BiomeCatalog.new())
	var shallow_y := VoxelDefs.SEA_LEVEL - 4
	var shallow: Dictionary = populator.populate(Vector2i.ZERO, _uniform_field(shallow_y, BiomeCatalog.FOREST), {}, false)
	var shallow_data: PackedByteArray = shallow["data"]
	var shallow_index := shallow_y * VoxelDefs.DATA_STRIDE_Y
	_expect(shallow_data[shallow_index] == BlockRegistry.BLOCK_SAND, "shallow coastal seabed was not sand")
	_expect(shallow_data[shallow_index - 5 * VoxelDefs.DATA_STRIDE_Y] == BlockRegistry.BLOCK_SAND,
		"shallow sand shelf did not retain a sediment blanket")
	var deep_y := VoxelDefs.SEA_LEVEL - 13
	var deep: Dictionary = populator.populate(Vector2i.ZERO, _uniform_field(deep_y, BiomeCatalog.FOREST), {}, false)
	var deep_data: PackedByteArray = deep["data"]
	var deep_index := deep_y * VoxelDefs.DATA_STRIDE_Y
	_expect(deep_data[deep_index] == BlockRegistry.BLOCK_GRAVEL, "deeper seabed did not transition to gravel")
	_expect(deep_data[deep_index - 4 * VoxelDefs.DATA_STRIDE_Y] == BlockRegistry.BLOCK_GRAVEL,
		"deep gravel seabed exposed stone before its sediment blanket ended")
	# The waterline stays sand for every sea biome; the surface and buried
	# layers then change with depth and biome.
	var biome_cases: Array = [
		[BiomeCatalog.OCEAN, 4, BlockRegistry.BLOCK_SAND, BlockRegistry.BLOCK_SAND],
		[BiomeCatalog.OCEAN, 8, BlockRegistry.BLOCK_SAND, BlockRegistry.BLOCK_CLAY],
		[BiomeCatalog.CORAL_REEF, 10, BlockRegistry.BLOCK_CORAL_SUBSTRATE, BlockRegistry.BLOCK_CORAL_SUBSTRATE],
		[BiomeCatalog.SEAGRASS_MEADOW, 8, BlockRegistry.BLOCK_SAND, BlockRegistry.BLOCK_CLAY],
		[BiomeCatalog.KELP_FOREST, 8, BlockRegistry.BLOCK_GRAVEL, BlockRegistry.BLOCK_STONE],
		[BiomeCatalog.FROZEN_OCEAN, 12, BlockRegistry.BLOCK_GRAVEL, BlockRegistry.BLOCK_GRAVEL],
		[BiomeCatalog.DEEP_OCEAN, 13, BlockRegistry.BLOCK_CLAY, BlockRegistry.BLOCK_GRAVEL],
	]
	for case in biome_cases:
		var biome: int = case[0]
		var depth: int = case[1]
		var expected: int = case[2]
		var expected_sub: int = case[3]
		var surface_y: int = VoxelDefs.SEA_LEVEL - depth
		var result: Dictionary = populator.populate(Vector2i.ZERO, _uniform_field(surface_y, biome), {}, false)
		var data: PackedByteArray = result["data"]
		_expect(data[surface_y * VoxelDefs.DATA_STRIDE_Y] == expected,
			"%s seabed substrate was wrong at depth %d" % [_biomes.name_for(biome), depth])
		_expect(data[(surface_y - 1) * VoxelDefs.DATA_STRIDE_Y] == expected_sub,
			"%s seabed subsurface was wrong at depth %d" % [_biomes.name_for(biome), depth])
		var shelf_y := VoxelDefs.SEA_LEVEL - 4
		var shelf: Dictionary = populator.populate(Vector2i.ZERO, _uniform_field(shelf_y, biome), {}, false)
		var shelf_data: PackedByteArray = shelf["data"]
		_expect(shelf_data[shelf_y * VoxelDefs.DATA_STRIDE_Y] == BlockRegistry.BLOCK_SAND,
			"%s waterline sediment broke the sand shelf" % _biomes.name_for(biome))


## Reef mounds must rise from the mid-shelf floor while the abyssal plain stays
## deep, and the biome label must track the shaped floor instead of ignoring it.
func _verify_seabed_shaping() -> void:
	var sampler := TerrainSampler.new(WorldGenConfig.new(TEST_CONFIG), TerrainProfileCatalog.new(), _biomes)
	var mound_total := 0.0
	var mound_count := 0
	var flat_total := 0.0
	var flat_count := 0
	var floor_min := INF
	var floor_max := -INF
	for z in range(-1024, 1025, 16):
		for x in range(-1024, 1025, 16):
			var continental := sampler._continentalness_at(x, z)
			if continental >= TerrainSampler.OCEAN_CONTINENTAL:
				continue
			var floor_height: float = sampler._ocean_floor_at(x, z, continental)
			floor_min = minf(floor_min, floor_height)
			floor_max = maxf(floor_max, floor_height)
			if continental < 0.15 or continental > 0.32:
				continue
			var mound: float = sampler._seabed_patch_strength(
				x, z, TerrainSampler.CHANNEL_REEF, TerrainSampler.REEF_PATCH_SCALE)
			if mound >= 0.70:
				mound_total += float(VoxelDefs.SEA_LEVEL) - floor_height
				mound_count += 1
			elif mound <= 0.05:
				flat_total += float(VoxelDefs.SEA_LEVEL) - floor_height
				flat_count += 1
	_expect(mound_count > 0, "no high-reef-mask shelf samples found")
	_expect(flat_count > 0, "no low-reef-mask shelf samples found")
	if mound_count > 0 and flat_count > 0:
		var mound_depth := mound_total / float(mound_count)
		var flat_depth := flat_total / float(flat_count)
		_expect(mound_depth < flat_depth - 1.0,
			"reef mounds did not raise the shelf floor (%.2f vs %.2f)" % [mound_depth, flat_depth])
	_expect(floor_max <= float(VoxelDefs.SEA_LEVEL) - 2.0, "seabed shaping broke the water surface")
	var abyssal_budget: float = TerrainSampler.ABYSSAL_DEPTH + TerrainSampler.SEABED_RELIEF_HEIGHT
	_expect(floor_min >= float(VoxelDefs.SEA_LEVEL) - abyssal_budget - 0.01, "seabed shaping exceeded the abyssal budget")
	print("WORLDGEN SEABED SHAPING: floor_min=%.1f floor_max=%.1f mound_depth=%.2f flat_depth=%.2f" % [
		floor_min, floor_max, mound_total / maxf(float(mound_count), 1.0), flat_total / maxf(float(flat_count), 1.0)])


## Seabed plants must appear in their biomes, stand on the seabed (never float
## or break the surface), honour the decoration-density gate, and stay
## deterministic across identical runs.
func _verify_underwater_vegetation() -> void:
	var config: Dictionary = TEST_CONFIG.duplicate()
	config["cave_density"] = 0.0
	config["tree_density"] = 0.0
	var populator := VoxelPopulator.new(WorldGenConfig.new(config), _biomes)
	# Dense biomes are asserted per chunk; shelf and abyssal seas are sparse by
	# design and would make a single-chunk fixture flaky.
	var cases: Array = [
		[BiomeCatalog.CORAL_REEF, 6],
		[BiomeCatalog.SEAGRASS_MEADOW, 6],
		[BiomeCatalog.KELP_FOREST, 9],
	]
	for case in cases:
		var biome: int = case[0]
		var depth: int = case[1]
		var surface_y: int = VoxelDefs.SEA_LEVEL - depth
		var field := _uniform_field(surface_y, biome)
		var result: Dictionary = populator.populate(Vector2i.ZERO, field, {}, true)
		var data: PackedByteArray = result["data"]
		var plant_count := 0
		var floating := 0
		for column in VoxelDefs.CHUNK_AREA:
			_expect(data[column + VoxelDefs.SEA_LEVEL * VoxelDefs.DATA_STRIDE_Y] == BlockRegistry.BLOCK_WATER,
				"%s seabed vegetation broke the water surface" % _biomes.name_for(biome))
			for y in range(surface_y + 2, VoxelDefs.SEA_LEVEL):
				var block: int = data[column + y * VoxelDefs.DATA_STRIDE_Y]
				if not _is_underwater_plant(block):
					continue
				plant_count += 1
				var below: int = data[column + (y - 1) * VoxelDefs.DATA_STRIDE_Y]
				if not _is_underwater_plant(below):
					floating += 1
			var surface_plus_one: int = data[column + (surface_y + 1) * VoxelDefs.DATA_STRIDE_Y]
			if _is_underwater_plant(surface_plus_one) and data[column + surface_y * VoxelDefs.DATA_STRIDE_Y] != _biomes.seabed_block(biome, depth):
				floating += 1
		_expect(plant_count > 0, "%s produced no seabed vegetation" % _biomes.name_for(biome))
		_expect(floating == 0, "%s seabed plants floated off the seabed (%d)" % [_biomes.name_for(biome), floating])
		var repeat: Dictionary = populator.populate(Vector2i.ZERO, _uniform_field(surface_y, biome), {}, true)
		_expect(repeat["data"] == data, "%s seabed vegetation changed between identical runs" % _biomes.name_for(biome))
		var barren_config: Dictionary = config.duplicate()
		barren_config["decoration_density"] = 0.0
		var barren := VoxelPopulator.new(WorldGenConfig.new(barren_config), _biomes)
		var barren_result: Dictionary = barren.populate(Vector2i.ZERO, _uniform_field(surface_y, biome), {}, true)
		for column in VoxelDefs.CHUNK_AREA:
			for y in range(surface_y + 1, VoxelDefs.SEA_LEVEL):
				_expect(not _is_underwater_plant(barren_result["data"][column + y * VoxelDefs.DATA_STRIDE_Y]),
					"decoration_density 0 still produced seabed vegetation")


## Thin cross plants sit inside the water volume; the water mesh must cull its
## faces against them (same faces as an all-water fixture) or every tuft is
## boxed in its own glassy pocket.
func _verify_water_plant_meshing() -> void:
	var mesher := ChunkMesher.new(BlockRegistry.new())
	var heights := PackedInt32Array()
	heights.resize(VoxelDefs.CHUNK_AREA)
	heights.fill(24)
	var tints := PackedColorArray()
	tints.resize(VoxelDefs.CHUNK_AREA)
	tints.fill(Color.WHITE)
	var with_plant := mesher.build(_water_fixture(true), 24, heights, tints, tints, ChunkMesher.NeighborSet.new())
	var without_plant := mesher.build(_water_fixture(false), 24, heights, tints, tints, ChunkMesher.NeighborSet.new())
	_expect(with_plant.water_verts == without_plant.water_verts,
		"cross plants created internal water faces")
	_expect(with_plant.water_indices.size() == without_plant.water_indices.size(),
		"cross plants changed the water face count")
	print("WORLDGEN WATER PLANTS: faces=%d verts=%d" % [
		without_plant.water_indices.size() / 6, without_plant.water_verts.size()])


func _water_fixture(with_plant: bool) -> PackedByteArray:
	var data := PackedByteArray()
	data.resize(VoxelDefs.CHUNK_AREA * VoxelDefs.WORLD_HEIGHT)
	for local_z in range(4, 12):
		for local_x in range(4, 12):
			for y in range(16, 25):
				data[local_x + local_z * VoxelDefs.DATA_STRIDE_Z + y * VoxelDefs.DATA_STRIDE_Y] = BlockRegistry.BLOCK_WATER
	if with_plant:
		data[8 + 8 * VoxelDefs.DATA_STRIDE_Z + 20 * VoxelDefs.DATA_STRIDE_Y] = BlockRegistry.BLOCK_SEAGRASS
	return data


func _is_underwater_plant(block_id: int) -> bool:
	return block_id == BlockRegistry.BLOCK_SEAGRASS \
		or block_id == BlockRegistry.BLOCK_KELP \
		or block_id == BlockRegistry.BLOCK_CORAL_FAN \
		or block_id == BlockRegistry.BLOCK_CORAL_BRANCH \
		or block_id == BlockRegistry.BLOCK_SPONGE \
		or block_id == BlockRegistry.BLOCK_ANEMONE


## The ocean split must cover every underwater regime without leaking land
## biomes onto the seabed, and each label must follow the depth and climate
## the shape used.
func _verify_underwater_biomes() -> void:
	var seeds: Array[int] = [int(TEST_CONFIG["seed"]), -48271, 918273]
	var expected: Array[int] = [
		BiomeCatalog.OCEAN, BiomeCatalog.DEEP_OCEAN, BiomeCatalog.CORAL_REEF,
		BiomeCatalog.KELP_FOREST, BiomeCatalog.SEAGRASS_MEADOW, BiomeCatalog.FROZEN_OCEAN,
	]
	var seen := {}
	var samples := 0
	var stranded_land := 0
	var depth_totals := {}
	var depth_counts := {}
	var depth_min := {}
	var depth_max := {}
	var temperature_min := {}
	var temperature_max := {}
	for seed in seeds:
		var config: Dictionary = TEST_CONFIG.duplicate()
		config["seed"] = seed
		var generator := TerrainGenerator.new()
		generator.configure(config)
		for z in range(-2304, 2305, 64):
			for x in range(-2304, 2305, 64):
				var sample := generator.sample_point(x, z)
				var biome := int(sample["dominant_biome_id"])
				var height := float(sample["final_height"])
				var temperature := float(sample["temperature"])
				var depth := float(VoxelDefs.SEA_LEVEL) - height
				samples += 1
				# Beaches and rivers are allowed at the waterline; any deeper
				# land biome means the sea/shelf classification gapped.
				if depth >= 1.0 and not _biomes.is_ocean_biome(biome) \
						and biome != BiomeCatalog.RIVER and biome != BiomeCatalog.BEACH:
					stranded_land += 1
				if not _biomes.is_ocean_biome(biome):
					continue
				seen[biome] = true
				depth_totals[biome] = float(depth_totals.get(biome, 0.0)) + depth
				depth_counts[biome] = int(depth_counts.get(biome, 0)) + 1
				depth_min[biome] = minf(float(depth_min.get(biome, INF)), depth)
				depth_max[biome] = maxf(float(depth_max.get(biome, -INF)), depth)
				temperature_min[biome] = minf(float(temperature_min.get(biome, INF)), temperature)
				temperature_max[biome] = maxf(float(temperature_max.get(biome, -INF)), temperature)
	for biome in expected:
		_expect(seen.has(biome), "underwater biome %s never appeared in the sampled ocean" % _biomes.name_for(biome))
	_expect(stranded_land == 0, "%d land-biome samples sat at least one block below sea level" % stranded_land)
	var shelf_depth := _mean_value(depth_totals, depth_counts, BiomeCatalog.OCEAN)
	var deep_depth := _mean_value(depth_totals, depth_counts, BiomeCatalog.DEEP_OCEAN)
	_expect(deep_depth > shelf_depth + 4.0, "deep sea is not deeper than the shelf (%.1f vs %.1f)" % [deep_depth, shelf_depth])
	_expect(float(depth_max.get(BiomeCatalog.CORAL_REEF, 0.0)) <= TerrainSampler.CORAL_REEF_DEPTH + 0.01, "coral reef left the shallow shelf")
	_expect(float(depth_min.get(BiomeCatalog.DEEP_OCEAN, 0.0)) >= TerrainSampler.DEEP_SEA_DEPTH - 0.01, "deep sea reached the shelf")
	_expect(float(depth_min.get(BiomeCatalog.KELP_FOREST, 99.0)) >= TerrainSampler.KELP_FOREST_MIN_DEPTH - 0.01, "kelp forest grew at the waterline")
	_expect(float(temperature_max.get(BiomeCatalog.FROZEN_OCEAN, 1.0)) <= TerrainSampler.FROZEN_SEA_TEMPERATURE + 0.01, "frozen sea appeared outside cold water")
	_expect(float(temperature_min.get(BiomeCatalog.CORAL_REEF, 0.0)) >= TerrainSampler.CORAL_REEF_TEMPERATURE - 0.01, "coral reef appeared outside warm water")
	print("WORLDGEN UNDERWATER: samples=%d shelf_depth=%.1f deep_depth=%.1f coral=%.1f kelp=%.1f seagrass=%.1f frozen=%.1f" % [
		samples, shelf_depth, deep_depth,
		_mean_value(depth_totals, depth_counts, BiomeCatalog.CORAL_REEF),
		_mean_value(depth_totals, depth_counts, BiomeCatalog.KELP_FOREST),
		_mean_value(depth_totals, depth_counts, BiomeCatalog.SEAGRASS_MEADOW),
		_mean_value(depth_totals, depth_counts, BiomeCatalog.FROZEN_OCEAN)])
	print("WORLDGEN UNDERWATER SHARE: shelf=%d deep=%d coral=%d kelp=%d seagrass=%d frozen=%d" % [
		int(depth_counts.get(BiomeCatalog.OCEAN, 0)), int(depth_counts.get(BiomeCatalog.DEEP_OCEAN, 0)),
		int(depth_counts.get(BiomeCatalog.CORAL_REEF, 0)), int(depth_counts.get(BiomeCatalog.KELP_FOREST, 0)),
		int(depth_counts.get(BiomeCatalog.SEAGRASS_MEADOW, 0)), int(depth_counts.get(BiomeCatalog.FROZEN_OCEAN, 0))])


func _mean_value(totals: Dictionary, counts: Dictionary, biome: int) -> float:
	var count := int(counts.get(biome, 0))
	if count == 0:
		return -1.0
	return float(totals.get(biome, 0.0)) / float(count)


func _uniform_field(surface_y: int, biome: int) -> ChunkTerrainData:
	var field := ChunkTerrainData.new()
	for index in ChunkTerrainData.CELL_COUNT:
		field.set_height(index, surface_y, surface_y, surface_y, 0.0)
		field.set_climate(index, 0.7, 0.0, 0.55, 0.52)
		field.set_biome(index, biome, biome, 0, biome)
	field.seal()
	return field


func _grass_fixture(surface_y: int) -> PackedByteArray:
	var data := PackedByteArray()
	data.resize(VoxelDefs.CHUNK_AREA * VoxelDefs.WORLD_HEIGHT)
	for local_z in VoxelDefs.CHUNK_SIZE:
		for local_x in VoxelDefs.CHUNK_SIZE:
			data[local_x + local_z * VoxelDefs.DATA_STRIDE_Z + surface_y * VoxelDefs.DATA_STRIDE_Y] = BlockRegistry.BLOCK_GRASS
	return data


func _verify_parallel_generation(generator: TerrainGenerator) -> void:
	var positions: Array[Vector2i] = [Vector2i(-2, -1), Vector2i(0, 0), Vector2i(2, 3), Vector2i(7, -4)]
	var expected: Array[PackedByteArray] = []
	for position in positions:
		expected.append(generator.generate_data(position, {}, false).data)
	var tasks := PackedInt64Array()
	var slots: Array[Dictionary] = []
	for position in positions:
		var slot: Dictionary = {}
		slots.append(slot)
		tasks.append(WorkerThreadPool.add_task(_generate_into.bind(generator, position, slot), true, "worldgen_verify"))
	for index in tasks.size():
		WorkerThreadPool.wait_for_task_completion(tasks[index])
		_expect(slots[index].has("data") and slots[index]["data"] == expected[index], "parallel output mismatch for %s" % positions[index])


func _generate_into(generator: TerrainGenerator, position: Vector2i, slot: Dictionary) -> void:
	slot["data"] = generator.generate_data(position, {}, false).data


func _verify_distribution(generator: TerrainGenerator) -> void:
	var seen := {}
	var river_samples := 0
	var cap_samples := 0
	for z in range(-1536, 1537, 48):
		for x in range(-1536, 1537, 48):
			var sample := generator.sample_point(x, z)
			seen[int(sample["dominant_biome_id"])] = true
			if float(sample["river"]) > 0.62:
				river_samples += 1
			if float(sample["final_height"]) >= VoxelDefs.WORLD_HEIGHT - 8:
				cap_samples += 1
	_expect(seen.size() >= 12, "biome distribution is too narrow (%d unique)" % seen.size())
	_expect(river_samples > 0, "no river corridors found in distribution sample")
	_expect(cap_samples == 0, "terrain height hit the generation cap")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
