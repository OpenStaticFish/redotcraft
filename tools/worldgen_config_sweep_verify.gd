extends SceneTree

## Bounded configuration-boundary coverage for WorldGenConfig and TerrainSampler.
## Each case builds four small terrain fields and two authoritative chunks only.

const SEED: int = 457219
const FIELD_POINT_TOLERANCE: float = 0.001
const MAX_CLAMP_FLAT_TOP_RATIO: float = 0.45
const EDGE_SAMPLES: Array[int] = [-1, 0, 8, 15, 16]
const FIELD_ORIGIN := Vector2i(-17, 23)
## Widely spaced fields make the ceiling-ratio guard meaningful even at the
## largest 8192-block macro scale, while keeping each case finite and small.
const CLAMP_PROBE_ORIGINS: Array[Vector2i] = [
	FIELD_ORIGIN, Vector2i(127, -91), Vector2i(-359, 211), Vector2i(797, -631),
]
const GENERATED_CHUNK := Vector2i(2, -1)

var _failures := PackedStringArray()
var _case_count: int = 0
var _point_count: int = 0
var _max_clamp_flat_top_ratio: float = 0.0


func _initialize() -> void:
	for test_case in _cases():
		_verify_case(test_case)
	if _failures.is_empty():
		print("WORLDGEN CONFIG SWEEP: PASS cases=%d point_samples=%d max_clamp_flat_top_ratio=%.4f" % [
			_case_count, _point_count, _max_clamp_flat_top_ratio])
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("WORLDGEN CONFIG SWEEP: FAIL cases=%d failures=%d" % [_case_count, _failures.size()])
	quit(1)


func _cases() -> Array[Dictionary]:
	return [
		_case("normal_minimums", {
			"terrain_scale": WorldGenConfig.MIN_TERRAIN_SCALE,
			"tree_density": WorldGenConfig.MIN_TREE_DENSITY,
			"macro_scale": WorldGenConfig.MIN_MACRO_SCALE,
			"biome_scale": WorldGenConfig.MIN_BIOME_SCALE,
			"river_density": WorldGenConfig.MIN_RIVER_DENSITY,
			"erosion_strength": WorldGenConfig.MIN_EROSION_STRENGTH,
			"regional_erosion": WorldGenConfig.MIN_EROSION_STRENGTH,
			"cave_density": WorldGenConfig.MIN_CAVE_DENSITY,
			"decoration_density": WorldGenConfig.MIN_DECORATION_DENSITY,
		}),
		_case("normal_maximums", {
			"terrain_scale": WorldGenConfig.MAX_TERRAIN_SCALE,
			"tree_density": WorldGenConfig.MAX_TREE_DENSITY,
			"macro_scale": WorldGenConfig.MAX_MACRO_SCALE,
			"biome_scale": WorldGenConfig.MAX_BIOME_SCALE,
			"river_density": WorldGenConfig.MAX_RIVER_DENSITY,
			"erosion_strength": WorldGenConfig.MAX_EROSION_STRENGTH,
			"regional_erosion": WorldGenConfig.MAX_EROSION_STRENGTH,
			"cave_density": WorldGenConfig.MAX_CAVE_DENSITY,
			"decoration_density": WorldGenConfig.MAX_DECORATION_DENSITY,
		}),
		_case("macro_min_biome_max", {
			"macro_scale": WorldGenConfig.MIN_MACRO_SCALE,
			"biome_scale": WorldGenConfig.MAX_BIOME_SCALE,
		}),
		_case("macro_max_biome_min", {
			"macro_scale": WorldGenConfig.MAX_MACRO_SCALE,
			"biome_scale": WorldGenConfig.MIN_BIOME_SCALE,
		}),
		_case("river_off_erosion_max", {
			"river_density": WorldGenConfig.MIN_RIVER_DENSITY,
			"erosion_strength": WorldGenConfig.MAX_EROSION_STRENGTH,
			"regional_erosion": WorldGenConfig.MAX_EROSION_STRENGTH,
		}),
		_case("river_max_erosion_min", {
			"river_density": WorldGenConfig.MAX_RIVER_DENSITY,
			"erosion_strength": WorldGenConfig.MIN_EROSION_STRENGTH,
			"regional_erosion": WorldGenConfig.MIN_EROSION_STRENGTH,
		}),
		_case("caves_and_decorations_off", {
			"cave_density": WorldGenConfig.MIN_CAVE_DENSITY,
			"decoration_density": WorldGenConfig.MIN_DECORATION_DENSITY,
			"tree_density": WorldGenConfig.MIN_TREE_DENSITY,
		}),
		_case("caves_and_decorations_max", {
			"cave_density": WorldGenConfig.MAX_CAVE_DENSITY,
			"decoration_density": WorldGenConfig.MAX_DECORATION_DENSITY,
			"tree_density": WorldGenConfig.MAX_TREE_DENSITY,
		}),
		_case("flat_minimums", {
			"world_type": WorldGenConfig.WORLD_TYPE_FLAT,
			"terrain_scale": WorldGenConfig.MIN_TERRAIN_SCALE,
			"macro_scale": WorldGenConfig.MIN_MACRO_SCALE,
			"biome_scale": WorldGenConfig.MIN_BIOME_SCALE,
			"river_density": WorldGenConfig.MIN_RIVER_DENSITY,
			"erosion_strength": WorldGenConfig.MIN_EROSION_STRENGTH,
			"regional_erosion": WorldGenConfig.MIN_EROSION_STRENGTH,
			"cave_density": WorldGenConfig.MIN_CAVE_DENSITY,
			"decoration_density": WorldGenConfig.MIN_DECORATION_DENSITY,
		}),
		_case("flat_maximums", {
			"world_type": WorldGenConfig.WORLD_TYPE_FLAT,
			"terrain_scale": WorldGenConfig.MAX_TERRAIN_SCALE,
			"macro_scale": WorldGenConfig.MAX_MACRO_SCALE,
			"biome_scale": WorldGenConfig.MAX_BIOME_SCALE,
			"river_density": WorldGenConfig.MAX_RIVER_DENSITY,
			"erosion_strength": WorldGenConfig.MAX_EROSION_STRENGTH,
			"regional_erosion": WorldGenConfig.MAX_EROSION_STRENGTH,
			"cave_density": WorldGenConfig.MAX_CAVE_DENSITY,
			"decoration_density": WorldGenConfig.MAX_DECORATION_DENSITY,
		}),
		_case("amplified_minimums", {
			"world_type": WorldGenConfig.WORLD_TYPE_AMPLIFIED,
			"terrain_scale": WorldGenConfig.MIN_TERRAIN_SCALE,
			"macro_scale": WorldGenConfig.MIN_MACRO_SCALE,
			"biome_scale": WorldGenConfig.MIN_BIOME_SCALE,
			"river_density": WorldGenConfig.MIN_RIVER_DENSITY,
		}),
		_case("amplified_maximums", {
			"world_type": WorldGenConfig.WORLD_TYPE_AMPLIFIED,
			"terrain_scale": WorldGenConfig.MAX_TERRAIN_SCALE,
			"macro_scale": WorldGenConfig.MAX_MACRO_SCALE,
			"biome_scale": WorldGenConfig.MAX_BIOME_SCALE,
			"river_density": WorldGenConfig.MAX_RIVER_DENSITY,
			"erosion_strength": WorldGenConfig.MAX_EROSION_STRENGTH,
			"regional_erosion": WorldGenConfig.MAX_EROSION_STRENGTH,
		}),
		_case("experimental_disabled", {
			"hydraulic_erosion": false,
			"spline_terrain": false,
			"elevated_hydrology": false,
			"climate_variants": false,
			"region_structures": false,
		}),
		_case("experimental_enabled", {
			"hydraulic_erosion": true,
			"spline_terrain": true,
			"elevated_hydrology": true,
			"climate_variants": true,
			"region_structures": true,
			"river_density": WorldGenConfig.MAX_RIVER_DENSITY,
		}),
	]


func _case(label: String, overrides: Dictionary) -> Dictionary:
	var source: Dictionary = {
		"seed": SEED,
		"worldgen_version": WorldGenConfig.CURRENT_VERSION,
		"world_type": WorldGenConfig.WORLD_TYPE_NORMAL,
		"terrain_scale": WorldGenConfig.DEFAULT_TERRAIN_SCALE,
		"tree_density": WorldGenConfig.DEFAULT_TREE_DENSITY,
		"macro_scale": WorldGenConfig.DEFAULT_MACRO_SCALE,
		"biome_scale": WorldGenConfig.DEFAULT_BIOME_SCALE,
		"river_density": WorldGenConfig.DEFAULT_RIVER_DENSITY,
		"erosion_strength": WorldGenConfig.DEFAULT_EROSION_STRENGTH,
		"regional_erosion": WorldGenConfig.DEFAULT_REGIONAL_EROSION,
		"hydraulic_erosion": WorldGenConfig.DEFAULT_HYDRAULIC_EROSION,
		"cave_density": WorldGenConfig.DEFAULT_CAVE_DENSITY,
		"decoration_density": WorldGenConfig.DEFAULT_DECORATION_DENSITY,
		"spline_terrain": WorldGenConfig.DEFAULT_SPLINE_TERRAIN,
		"elevated_hydrology": WorldGenConfig.DEFAULT_ELEVATED_HYDROLOGY,
		"climate_variants": WorldGenConfig.DEFAULT_CLIMATE_VARIANTS,
		"region_structures": WorldGenConfig.DEFAULT_REGION_STRUCTURES,
	}
	for key in overrides:
		source[key] = overrides[key]
	return {"label": label, "source": source}


func _verify_case(test_case: Dictionary) -> void:
	var label: String = str(test_case["label"])
	var config := WorldGenConfig.new(test_case["source"])
	var sampler := TerrainSampler.new(config, TerrainProfileCatalog.new(), BiomeCatalog.new())
	var field := sampler.build_field(FIELD_ORIGIN)
	var repeat := sampler.build_field(FIELD_ORIGIN)
	var east := sampler.build_field(FIELD_ORIGIN + Vector2i.RIGHT)
	var south := sampler.build_field(FIELD_ORIGIN + Vector2i.DOWN)
	_expect(field.final_height == repeat.final_height, "%s field heights changed between identical runs" % label)
	_expect(field.river == repeat.river, "%s river field changed between identical runs" % label)
	_expect(field.dominant_biome == repeat.dominant_biome, "%s biome field changed between identical runs" % label)
	_verify_field_bounds(label, field)
	_verify_x_border(label, sampler, field, east)
	_verify_z_border(label, sampler, field, south)
	for probe_origin in CLAMP_PROBE_ORIGINS:
		if probe_origin != FIELD_ORIGIN:
			_verify_field_bounds("%s clamp probe %s" % [label, probe_origin], sampler.build_field(probe_origin))

	var generator := TerrainGenerator.new()
	generator.configure(config.to_dictionary())
	var generated := generator.generate_data(GENERATED_CHUNK, {}, false)
	var generated_repeat := generator.generate_data(GENERATED_CHUNK, {}, false)
	_expect(generated.data == generated_repeat.data, "%s generated blocks changed between identical runs" % label)
	_expect(generated.heights == generated_repeat.heights, "%s generated heightmap changed between identical runs" % label)
	_expect(generated.max_y == generated_repeat.max_y, "%s generated max_y changed between identical runs" % label)
	_expect(generated.max_y >= 0 and generated.max_y < VoxelDefs.WORLD_HEIGHT - 1,
		"%s generated max_y %d is outside valid world bounds" % [label, generated.max_y])
	_case_count += 1
	print("WORLDGEN CONFIG SWEEP %s: clamp_flat_top_ratio=%.4f max_y=%d" % [
		label, _flat_top_ratio(field), generated.max_y])


func _verify_field_bounds(label: String, field: ChunkTerrainData) -> void:
	var minimum: float = INF
	var maximum: float = -INF
	var clamp_count: int = 0
	var sample_count: int = 0
	var clamp_top: float = float(VoxelDefs.WORLD_HEIGHT) - TerrainSampler.HEIGHT_MARGIN
	for local_z in VoxelDefs.CHUNK_SIZE:
		for local_x in VoxelDefs.CHUNK_SIZE:
			var height: float = float(field.final_height[ChunkTerrainData.cell_index(local_x, local_z)])
			minimum = minf(minimum, height)
			maximum = maxf(maximum, height)
			if height >= clamp_top - FIELD_POINT_TOLERANCE:
				clamp_count += 1
			sample_count += 1
	_expect(minimum >= TerrainSampler.MIN_TERRAIN_HEIGHT - FIELD_POINT_TOLERANCE,
		"%s terrain minimum %.3f is below the valid bound" % [label, minimum])
	_expect(maximum <= clamp_top + FIELD_POINT_TOLERANCE,
		"%s terrain maximum %.3f exceeds the valid bound" % [label, maximum])
	var clamp_ratio: float = float(clamp_count) / float(sample_count)
	_max_clamp_flat_top_ratio = maxf(_max_clamp_flat_top_ratio, clamp_ratio)
	_expect(clamp_ratio <= MAX_CLAMP_FLAT_TOP_RATIO,
		"%s has excessive clamp-flat-top terrain (%.2f%%)" % [label, clamp_ratio * 100.0])


func _flat_top_ratio(field: ChunkTerrainData) -> float:
	var clamp_count: int = 0
	var clamp_top: float = float(VoxelDefs.WORLD_HEIGHT) - TerrainSampler.HEIGHT_MARGIN
	for local_z in VoxelDefs.CHUNK_SIZE:
		for local_x in VoxelDefs.CHUNK_SIZE:
			if float(field.final_height[ChunkTerrainData.cell_index(local_x, local_z)]) >= clamp_top - FIELD_POINT_TOLERANCE:
				clamp_count += 1
	return float(clamp_count) / float(VoxelDefs.CHUNK_AREA)


func _verify_x_border(label: String, sampler: TerrainSampler, field: ChunkTerrainData, east: ChunkTerrainData) -> void:
	for local_z in EDGE_SAMPLES:
		var left_index: int = ChunkTerrainData.cell_index(VoxelDefs.CHUNK_SIZE, local_z)
		var right_index: int = ChunkTerrainData.cell_index(0, local_z)
		_expect(is_equal_approx(field.final_height[left_index], east.final_height[right_index]),
			"%s x height field seam at z=%d" % [label, local_z])
		_expect(is_equal_approx(field.river[left_index], east.river[right_index]),
			"%s x river field seam at z=%d" % [label, local_z])
		_expect(field.dominant_biome[left_index] == east.dominant_biome[right_index],
			"%s x biome field seam at z=%d" % [label, local_z])
		_verify_point_parity(label, sampler, field, VoxelDefs.CHUNK_SIZE, local_z, left_index)


func _verify_z_border(label: String, sampler: TerrainSampler, field: ChunkTerrainData, south: ChunkTerrainData) -> void:
	for local_x in EDGE_SAMPLES:
		var north_index: int = ChunkTerrainData.cell_index(local_x, VoxelDefs.CHUNK_SIZE)
		var south_index: int = ChunkTerrainData.cell_index(local_x, 0)
		_expect(is_equal_approx(field.final_height[north_index], south.final_height[south_index]),
			"%s z height field seam at x=%d" % [label, local_x])
		_expect(is_equal_approx(field.river[north_index], south.river[south_index]),
			"%s z river field seam at x=%d" % [label, local_x])
		_expect(field.dominant_biome[north_index] == south.dominant_biome[south_index],
			"%s z biome field seam at x=%d" % [label, local_x])
		_verify_point_parity(label, sampler, field, local_x, VoxelDefs.CHUNK_SIZE, north_index)


func _verify_point_parity(label: String, sampler: TerrainSampler, field: ChunkTerrainData,
		local_x: int, local_z: int, field_index: int) -> void:
	var world_x: int = FIELD_ORIGIN.x * VoxelDefs.CHUNK_SIZE + local_x
	var world_z: int = FIELD_ORIGIN.y * VoxelDefs.CHUNK_SIZE + local_z
	var point := sampler.sample_point(world_x, world_z)
	_expect(absf(float(field.final_height[field_index]) - float(point["final_height"])) <= FIELD_POINT_TOLERANCE,
		"%s field/point height mismatch at (%d, %d)" % [label, world_x, world_z])
	_expect(absf(float(field.river[field_index]) - float(point["river"])) <= FIELD_POINT_TOLERANCE,
		"%s field/point river mismatch at (%d, %d)" % [label, world_x, world_z])
	_expect(int(field.dominant_biome[field_index]) == int(point["dominant_biome_id"]),
		"%s field/point biome mismatch at (%d, %d)" % [label, world_x, world_z])
	_point_count += 1


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
