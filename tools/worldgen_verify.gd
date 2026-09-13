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
	_verify_seabed_sediment()
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
	for biome in [BiomeCatalog.PLAINS, BiomeCatalog.SNOW]:
		var field := ChunkTerrainData.new()
		for index in ChunkTerrainData.CELL_COUNT:
			field.set_height(index, surface_y, surface_y, surface_y, 0.0)
			field.set_climate(index, 0.8, 1.0, 0.5, 0.5)
			field.set_biome(index, biome, BiomeCatalog.SNOW, 127,
				BiomeCatalog.SNOW if index % 2 == 0 else BiomeCatalog.PLAINS)
		field.seal()
		# Surface-only generation isolates the blanket from caves/decorations.
		var result := populator.populate(Vector2i.ZERO, field, {}, false)
		var data: PackedByteArray = result["data"]
		var expected := BlockRegistry.BLOCK_SNOW if biome == BiomeCatalog.SNOW else BlockRegistry.BLOCK_GRASS
		for column in VoxelDefs.CHUNK_AREA:
			_expect(data[column + surface_y * VoxelDefs.DATA_STRIDE_Y] == expected,
				"biome dithering fragmented a coherent surface blanket")
			_expect(data[column + (surface_y + 1) * VoxelDefs.DATA_STRIDE_Y] == BlockRegistry.BLOCK_AIR,
				"river mask created suspended water above sea level")


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
	_expect(populator._place_ground_cover(carved_fixture, field, 0, 0, 1, 0) == -1,
		"ground cover floated above an absent soil voxel")
	_expect(carved_fixture[target_index] == BlockRegistry.BLOCK_AIR,
		"ground cover wrote into a floating target")


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
