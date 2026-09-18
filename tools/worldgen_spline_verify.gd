extends SceneTree

var _failures := PackedStringArray()

const V10_COMPATIBILITY_FINGERPRINT: int = 3534179881661516132


func _initialize() -> void:
	_verify_config_gate()
	_verify_v10_splines()
	_verify_v10_compatibility()
	_verify_v11_splines()
	_verify_v11_field_point_parity()
	_verify_variant_diversity()
	if _failures.is_empty():
		print("WORLDGEN SPLINE VERIFY: PASS")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("WORLDGEN SPLINE VERIFY: FAIL (", _failures.size(), ")")
	quit(1)


func _verify_config_gate() -> void:
	_expect(not WorldGenConfig.new({"worldgen_version": 9, "spline_terrain": true}).spline_terrain,
		"legacy world enabled spline terrain")
	var enabled := WorldGenConfig.new({"worldgen_version": 10, "spline_terrain": true})
	_expect(enabled.spline_terrain, "version 10 did not retain explicit spline terrain")
	_expect(bool(enabled.to_dictionary().get("spline_terrain", false)),
		"spline terrain did not serialize")
	_expect(not WorldGenConfig.new({"worldgen_version": 10}).spline_terrain,
		"spline terrain is not default-off")
	_expect(not WorldGenConfig.new({"worldgen_version": 10, "climate_variants": true}).climate_variants,
		"legacy world enabled climate variants")
	_expect(WorldGenConfig.new({"worldgen_version": 11}).climate_variants,
		"version 11 did not enable climate variants by default")
	_expect(not WorldGenConfig.new({"worldgen_version": 11, "climate_variants": false}).climate_variants,
		"version 11 did not retain explicit climate-variant opt-out")


func _verify_v10_splines() -> void:
	var sampler := _sampler(10, true)
	for outputs in [TerrainSampler.CONTINENT_SPLINE_Y, TerrainSampler.PROFILE_SPLINE_Y]:
		var previous := -1.0
		for step in 101:
			var result: float = sampler._piecewise_cubic_remap(float(step) / 100.0, outputs)
			_expect(result >= previous and result >= 0.0 and result <= 1.0,
				"spline remap is not monotone and bounded")
			previous = result
		for knot in 5:
			_expect(is_equal_approx(sampler._piecewise_cubic_remap(float(knot) * 0.25, outputs),
				float(outputs[knot])), "spline remap missed knot %d" % knot)


## Fixed quantized samples protect the released v10 experimental terrain from
## accidental changes while v11 evolves independently. The input set includes
## coast, inland, and island regions rather than a single local patch.
func _verify_v10_compatibility() -> void:
	var sampler := _sampler(10, true)
	var fingerprint := 17
	for position in [Vector2i(-1024, -768), Vector2i(-256, 320), Vector2i(0, 0),
			Vector2i(384, -640), Vector2i(960, 768), Vector2i(1536, -1152)]:
		var sample := sampler.sample_point(position.x, position.y)
		fingerprint = fingerprint * 31 + roundi(float(sample["continentalness"]) * 100000.0)
		fingerprint = fingerprint * 31 + roundi(float(sample["final_height"]) * 100000.0)
		fingerprint = fingerprint * 31 + int(sample["profile_id"])
		fingerprint = fingerprint * 31 + int(sample["dominant_biome_id"])
	_expect(fingerprint == V10_COMPATIBILITY_FINGERPRINT,
		"v10 spline compatibility fingerprint changed (%d)" % fingerprint)


func _verify_v11_splines() -> void:
	var sampler := _sampler(11, true)
	for row in TerrainSampler.PROFILE_GRID:
		_verify_monotone_bounded(sampler, row, "profile-grid row")
	for column in range(TerrainSampler.PROFILE_GRID[0].size()):
		var values: Array[float] = []
		for row in TerrainSampler.PROFILE_GRID:
			values.append(float(row[column]))
		_verify_monotone_bounded(sampler, values, "profile-grid column")
	for continental_step in 21:
		var previous := -1.0
		for landform_step in 101:
			var result := sampler._profile_grid_sample(
				float(continental_step) / 20.0, float(landform_step) / 100.0)
			_expect(result >= previous - 0.000001 and result >= -0.000001 and result <= 1.000001,
				"v11 profile grid overshot or reversed along landform")
			previous = result
	for landform_step in 21:
		var previous := -1.0
		for continental_step in 101:
			var result := sampler._profile_grid_sample(
				float(continental_step) / 100.0, float(landform_step) / 20.0)
			_expect(result >= previous - 0.000001 and result >= -0.000001 and result <= 1.000001,
				"v11 profile grid overshot or reversed along continentalness")
			previous = result
	for row_index in TerrainSampler.PROFILE_GRID.size():
		for column_index in TerrainSampler.PROFILE_GRID[row_index].size():
			var result := sampler._profile_grid_sample(float(row_index) * 0.25, float(column_index) * 0.25)
			_expect(is_equal_approx(result, float(TerrainSampler.PROFILE_GRID[row_index][column_index])),
				"v11 profile grid missed knot (%d, %d)" % [row_index, column_index])


func _verify_monotone_bounded(sampler: TerrainSampler, outputs: Array, label: String) -> void:
	var previous := -1.0
	for step in 101:
		var result: float = sampler._monotone_cubic_sample(float(step) / 100.0, outputs)
		_expect(result >= previous - 0.000001 and result >= -0.000001 and result <= 1.000001,
			"%s is not monotone and bounded" % label)
		previous = result


func _verify_v11_field_point_parity() -> void:
	var baseline := _sampler(11, false)
	var enabled := _sampler(11, true)
	var changed := 0
	for z in range(-512, 513, 64):
		for x in range(-512, 513, 64):
			var before := baseline.sample_point(x, z)
			var after := enabled.sample_point(x, z)
			if absf(float(before.final_height) - float(after.final_height)) > 0.01:
				changed += 1
	_expect(changed >= 20, "v11 spline terrain did not materially alter sampled terrain")
	var left := enabled.build_field(Vector2i.ZERO)
	var right := enabled.build_field(Vector2i(1, 0))
	for local_z in range(-1, VoxelDefs.CHUNK_SIZE + 1):
		var left_index := ChunkTerrainData.cell_index(VoxelDefs.CHUNK_SIZE, local_z)
		var right_index := ChunkTerrainData.cell_index(0, local_z)
		_expect(is_equal_approx(left.final_height[left_index], right.final_height[right_index]),
			"v11 spline terrain height seam at z=%d" % local_z)
		_expect(is_equal_approx(left.continentalness[left_index], right.continentalness[right_index]),
			"v11 spline continentalness seam at z=%d" % local_z)
		_expect(left.biome_id[left_index] == right.biome_id[right_index],
			"v11 biome seam at z=%d" % local_z)
	for chunk_pos in [Vector2i.ZERO, Vector2i(1, 0), Vector2i(-3, 2)]:
		var field := enabled.build_field(chunk_pos)
		for local_z in range(-1, VoxelDefs.CHUNK_SIZE + 1):
			for local_x in range(-1, VoxelDefs.CHUNK_SIZE + 1):
				var index := ChunkTerrainData.cell_index(local_x, local_z)
				var world_x: int = chunk_pos.x * VoxelDefs.CHUNK_SIZE + local_x
				var world_z: int = chunk_pos.y * VoxelDefs.CHUNK_SIZE + local_z
				var point := enabled.sample_point(world_x, world_z)
				var ground := enabled.sample_decoration_ground(world_x, world_z)
				_expect(is_equal_approx(field.final_height[index], float(point["final_height"])),
					"v11 field/point height parity at (%d, %d)" % [world_x, world_z])
				_expect(field.biome_id[index] == int(point["biome_id"]),
					"v11 field/point biome parity at (%d, %d)" % [world_x, world_z])
				_expect(field.dominant_biome[index] == int(point["dominant_biome_id"]),
					"v11 field/point dominant parity at (%d, %d)" % [world_x, world_z])
				_expect(ground.y == int(point["dominant_biome_id"]),
					"v11 decoration-ground biome parity at (%d, %d)" % [world_x, world_z])
				var debug := enabled.sample_debug_point("biome", world_x, world_z)
				_expect(int(debug["dominant_biome_id"]) == int(point["dominant_biome_id"]),
					"v11 debug-biome parity at (%d, %d)" % [world_x, world_z])


func _verify_variant_diversity() -> void:
	var sampler := _sampler(11, true)
	var seen := {}
	for z in range(-8192, 8193, 128):
		if seen.size() == 3:
			break
		for x in range(-8192, 8193, 128):
			if seen.size() == 3:
				break
			var sample := sampler.sample_point(x, z)
			var biome := int(sample["biome_id"])
			if biome in [BiomeCatalog.SNOWY_TAIGA, BiomeCatalog.WOODED_BADLANDS, BiomeCatalog.STONY_SHORE]:
				seen[biome] = true
				var debug := sampler.sample_debug_point("biome", x, z)
				_expect(int(debug["biome_id"]) == biome,
					"v11 debug biome omitted variant %d" % biome)
	_expect(seen.has(BiomeCatalog.SNOWY_TAIGA), "v11 did not produce snowy taiga")
	_expect(seen.has(BiomeCatalog.WOODED_BADLANDS), "v11 did not produce wooded badlands")
	_expect(seen.has(BiomeCatalog.STONY_SHORE), "v11 did not produce stony shore")


func _sampler(version: int, enabled: bool) -> TerrainSampler:
	var config := WorldGenConfig.new({
		"seed": 918273,
		"worldgen_version": version,
		"spline_terrain": enabled,
		"climate_variants": true,
		"hydraulic_erosion": false,
	})
	return TerrainSampler.new(config, TerrainProfileCatalog.new(), BiomeCatalog.new())


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
