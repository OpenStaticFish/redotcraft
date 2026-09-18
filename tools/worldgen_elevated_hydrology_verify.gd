extends SceneTree

var _failures := PackedStringArray()


func _initialize() -> void:
	_verify_config_gates()
	_verify_disabled_equivalence()
	_verify_flat_gate()
	_verify_v10_compatibility()
	var fixture := _find_v11_fixture()
	if fixture.is_empty():
		_failures.append("could not find a routed v11 elevated-water fixture with a stepped drop")
	else:
		_verify_v11_fixture(fixture)
	if _failures.is_empty():
		print("WORLDGEN ELEVATED HYDROLOGY VERIFY: PASS")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("WORLDGEN ELEVATED HYDROLOGY VERIFY: FAIL (", _failures.size(), ")")
	quit(1)


func _verify_config_gates() -> void:
	_expect(not WorldGenConfig.new({"worldgen_version": 9, "elevated_hydrology": true}).elevated_hydrology,
		"legacy world enabled elevated hydrology")
	_expect(not WorldGenConfig.new({"worldgen_version": 11}).elevated_hydrology,
		"elevated hydrology is not default-off")
	_expect(WorldGenConfig.new({"worldgen_version": 10, "elevated_hydrology": true}).elevated_hydrology,
		"v10 did not retain the legacy experiment")
	var enabled := WorldGenConfig.new({"worldgen_version": 11, "elevated_hydrology": true})
	_expect(enabled.elevated_hydrology and bool(enabled.to_dictionary().get("elevated_hydrology", false)),
		"v11 elevated hydrology did not serialize")


func _verify_disabled_equivalence() -> void:
	var disabled := _sampler(11, false).build_field(Vector2i(3, -2))
	_expect(disabled.inland_water_y.count(-1) == ChunkTerrainData.CELL_COUNT,
		"disabled hydrology emitted inland water")
	var enabled := _sampler(11, true).build_field(Vector2i(3, -2))
	for index in ChunkTerrainData.CELL_COUNT:
		_expect(enabled.final_height[index] <= disabled.final_height[index] + 0.0001,
			"routed hydrology raised terrain while enabled")


func _verify_flat_gate() -> void:
	var config := _config(11, true)
	config.world_type = WorldGenConfig.WORLD_TYPE_FLAT
	var sampler := TerrainSampler.new(config, TerrainProfileCatalog.new(), BiomeCatalog.new())
	var field := sampler.build_field(Vector2i(-3, 4))
	_expect(field.inland_water_y.count(-1) == ChunkTerrainData.CELL_COUNT,
		"flat world emitted routed elevated water")


func _verify_v10_compatibility() -> void:
	var sampler := _sampler(10, true)
	var found := false
	for cell_z in range(-12, 13):
		for cell_x in range(-12, 13):
			var hash_value := WorldGenHash.hash_2d(918273 + 2213, cell_x, cell_z)
			if hash_value % 100 >= 30:
				continue
			var x := cell_x * TerrainSampler.INLAND_WATER_CELL_SIZE + 32 + (hash_value / 101) % 128
			var z := cell_z * TerrainSampler.INLAND_WATER_CELL_SIZE + 32 + (hash_value / 307) % 128
			var sample := sampler.sample_point(x, z)
			if int(sample["inland_water_y"]) <= VoxelDefs.SEA_LEVEL:
				continue
			found = true
			_expect(int(sample["inland_water_y"]) == TerrainSampler.INLAND_WATER_Y,
				"v11 changed v10's fixed elevated-water level")
			_expect(float(sample["final_height"]) <= float(TerrainSampler.INLAND_WATER_Y - 1),
				"v10 elevated water lost its supported bed")
			break
		if found:
			break
	_expect(found, "could not find a legacy v10 elevated-water fixture")


## A source lake is accepted only after TerrainSampler's immutable owner-cell
## validation. Require an actual water-level drop, so the fixture also covers
## the waterfall-facing path rather than merely locating a lake.
func _find_v11_fixture() -> Dictionary:
	var sampler := _sampler(11, true)
	for cell_z in range(-28, 29):
		for cell_x in range(-28, 29):
			var route: Dictionary = sampler._v11_route_for_source(cell_x, cell_z)
			if route.is_empty():
				continue
			var levels: PackedInt32Array = route["levels"]
			var source_water_y: int = int(route["source_water_y"])
			var previous: int = source_water_y
			var drop_index := -1
			for index in levels.size():
				if levels[index] < previous:
					drop_index = index
					break
				previous = levels[index]
			if drop_index < 0:
				continue
			var center: Vector2i = route["center"]
			var sample := sampler.sample_point(center.x, center.y)
			if int(sample["inland_water_y"]) > VoxelDefs.SEA_LEVEL:
				return {"sampler": sampler, "route": route, "drop_index": drop_index}
	return {}


func _verify_v11_fixture(fixture: Dictionary) -> void:
	var sampler: TerrainSampler = fixture["sampler"]
	var route: Dictionary = fixture["route"]
	var points: Array = route["points"]
	var levels: PackedInt32Array = route["levels"]
	var center: Vector2i = route["center"]
	var source_water_y: int = int(route["source_water_y"])
	var source := sampler.sample_point(center.x, center.y)

	# Source lakes remain wide, supported water bodies rather than route-only
	# ribbons. The 3x3 interior is a conservative lake-presence check.
	_expect(int(source["inland_water_y"]) > VoxelDefs.SEA_LEVEL, "v11 source lake is dry")
	var lake_cells := 0
	for offset_z in range(-1, 2):
		for offset_x in range(-1, 2):
			var lake_sample := sampler.sample_point(center.x + offset_x * 4, center.y + offset_z * 4)
			if int(lake_sample["inland_water_y"]) == source_water_y:
				lake_cells += 1
	_expect(lake_cells >= 7, "v11 source did not produce a lake")

	# Every route endpoint is chosen downhill from the clearly pre-hydrology
	# coarse terrain source, while water levels can only stay level or descend.
	var previous_water_y: int = source_water_y
	for reach in levels.size():
		var start: Vector2i = points[reach]
		var finish: Vector2i = points[reach + 1]
		var start_height: float = sampler._coarse_pre_hydrology_height_at(start.x, start.y)
		var finish_height: float = sampler._coarse_pre_hydrology_height_at(finish.x, finish.y)
		_expect(finish_height < start_height - 0.24,
			"route reach %d was not selected downhill" % reach)
		_expect(levels[reach] <= previous_water_y,
			"route reach %d raised its water level" % reach)
		previous_water_y = levels[reach]
	var drop_index: int = int(fixture["drop_index"])
	var drop_before: int = source_water_y if drop_index == 0 else levels[drop_index - 1]
	_expect(levels[drop_index] < drop_before, "fixture does not contain a stepped drop")

	var chunk_pos := Vector2i(WorldGenHash.floor_div(center.x, VoxelDefs.CHUNK_SIZE),
		WorldGenHash.floor_div(center.y, VoxelDefs.CHUNK_SIZE))
	var field := sampler.build_field(chunk_pos)
	var disabled := _sampler(11, false).build_field(chunk_pos)
	for local_z in range(-1, VoxelDefs.CHUNK_SIZE + 1):
		for local_x in range(-1, VoxelDefs.CHUNK_SIZE + 1):
			var index := ChunkTerrainData.cell_index(local_x, local_z)
			var water_y: int = field.inland_water_y[index]
			_expect(field.final_height[index] <= disabled.final_height[index] + 0.0001,
				"hydrology raised a bank at (%d,%d)" % [local_x, local_z])
			if water_y > VoxelDefs.SEA_LEVEL:
				_expect(roundi(field.final_height[index]) < water_y,
					"elevated water column has no supported bed")
	var local_x := center.x - chunk_pos.x * VoxelDefs.CHUNK_SIZE
	var local_z := center.y - chunk_pos.y * VoxelDefs.CHUNK_SIZE
	var center_index := ChunkTerrainData.cell_index(local_x, local_z)
	_expect(field.inland_water_y[center_index] == int(source["inland_water_y"]),
		"point/field inland-water parity failed")
	_expect(is_equal_approx(field.final_height[center_index], float(source["final_height"])),
		"point/field elevated-height parity failed")

	_verify_seams(sampler, chunk_pos)
	_verify_waterfall_face(sampler, points[drop_index])
	_verify_full_compact_parity(chunk_pos, center, int(source["inland_water_y"]))


func _verify_seams(sampler: TerrainSampler, chunk_pos: Vector2i) -> void:
	for origin in [chunk_pos, Vector2i(-17, 11)]:
		var field := sampler.build_field(origin)
		var east := sampler.build_field(origin + Vector2i(1, 0))
		var south := sampler.build_field(origin + Vector2i(0, 1))
		for local in range(-1, VoxelDefs.CHUNK_SIZE + 1):
			var field_east := ChunkTerrainData.cell_index(VoxelDefs.CHUNK_SIZE, local)
			var neighbor_west := ChunkTerrainData.cell_index(0, local)
			_expect(field.inland_water_y[field_east] == east.inland_water_y[neighbor_west],
				"east/west elevated-water seam at %s/%d" % [origin, local])
			_expect(is_equal_approx(field.final_height[field_east], east.final_height[neighbor_west]),
				"east/west elevated-bed seam at %s/%d" % [origin, local])
			var field_south := ChunkTerrainData.cell_index(local, VoxelDefs.CHUNK_SIZE)
			var neighbor_north := ChunkTerrainData.cell_index(local, 0)
			_expect(field.inland_water_y[field_south] == south.inland_water_y[neighbor_north],
				"north/south elevated-water seam at %s/%d" % [origin, local])
			_expect(is_equal_approx(field.final_height[field_south], south.final_height[neighbor_north]),
				"north/south elevated-bed seam at %s/%d" % [origin, local])


func _verify_waterfall_face(sampler: TerrainSampler, drop: Vector2i) -> void:
	var center_chunk := Vector2i(WorldGenHash.floor_div(drop.x, VoxelDefs.CHUNK_SIZE),
		WorldGenHash.floor_div(drop.y, VoxelDefs.CHUNK_SIZE))
	var found_face := false
	for chunk_z in range(center_chunk.y - 1, center_chunk.y + 2):
		for chunk_x in range(center_chunk.x - 1, center_chunk.x + 2):
			var field := sampler.build_field(Vector2i(chunk_x, chunk_z))
			for local_z in range(-1, VoxelDefs.CHUNK_SIZE + 1):
				for local_x in range(-1, VoxelDefs.CHUNK_SIZE + 1):
					var here: int = field.inland_water_y[ChunkTerrainData.cell_index(local_x, local_z)]
					if here <= VoxelDefs.SEA_LEVEL:
						continue
					for offset in [Vector2i.RIGHT, Vector2i.DOWN]:
						var next_x: int = local_x + offset.x
						var next_z: int = local_z + offset.y
						if not ChunkTerrainData.is_valid_local(next_x, next_z):
							continue
						var next: int = field.inland_water_y[ChunkTerrainData.cell_index(next_x, next_z)]
						if next > VoxelDefs.SEA_LEVEL and next != here:
							found_face = true
	_expect(found_face, "stepped drop did not expose a waterfall water face")


func _verify_full_compact_parity(chunk_pos: Vector2i, center: Vector2i, water_y: int) -> void:
	var config := _config(11, true)
	var generator := TerrainGenerator.new()
	generator.configure(config.to_dictionary())
	var full := generator.generate_data(chunk_pos, {}, false)
	var lod := generator.generate_data(chunk_pos, {}, true)
	_expect(full.heights == lod.heights, "full/compact elevated terrain height parity failed")
	var local_x := center.x - chunk_pos.x * VoxelDefs.CHUNK_SIZE
	var local_z := center.y - chunk_pos.y * VoxelDefs.CHUNK_SIZE
	var column := local_x + local_z * VoxelDefs.DATA_STRIDE_Z
	_expect(lod.lod_water_y[column] == water_y, "LOD omitted elevated lake water")
	_expect(full.data[column + water_y * VoxelDefs.DATA_STRIDE_Y] == BlockRegistry.BLOCK_WATER,
		"full generation omitted elevated lake water")
	_expect(full.data[column + roundi(full.heights[column]) * VoxelDefs.DATA_STRIDE_Y] != BlockRegistry.BLOCK_AIR,
		"full elevated-water bed is not solid")


func _sampler(version: int, enabled: bool) -> TerrainSampler:
	var config := _config(version, enabled)
	return TerrainSampler.new(config, TerrainProfileCatalog.new(), BiomeCatalog.new())


func _config(version: int, enabled: bool) -> WorldGenConfig:
	return WorldGenConfig.new({
		"seed": 918273,
		"worldgen_version": version,
		"elevated_hydrology": enabled,
		"cave_density": 0.0,
		"tree_density": 0.0,
		"decoration_density": 0.0,
		"hydraulic_erosion": false,
	})


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
