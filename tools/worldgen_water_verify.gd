extends SceneTree

const TEST_CONFIG := {
	"seed": 123456789,
	"world_type": 0,
	"terrain_scale": 1.0,
	"tree_density": 0.0,
	"macro_scale": 384.0,
	"river_density": 1.0,
	"erosion_strength": 0.55,
	"regional_erosion": 0.5,
	"cave_density": 1.0,
	"decoration_density": 0.0,
}

const SEEDS: Array[int] = [123456789, 246813579, -987654321]

var _failures := PackedStringArray()


func _initialize() -> void:
	_verify_determinism()
	_verify_legacy_compatibility()
	_verify_adjacent_chunk_borders()
	_verify_surface_and_river_protection()
	if _failures.is_empty():
		print("WORLDGEN WATER VERIFY: PASS")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("WORLDGEN WATER VERIFY: FAIL (", _failures.size(), ")")
	quit(1)


func _verify_determinism() -> void:
	var samples := 0
	for seed in SEEDS:
		var populator := _populator_for(seed)
		for world_z in range(-160, 161, 7):
			for world_x in range(-160, 161, 5):
				var first: int = populator._aquifer_water_level_at(world_x, world_z)
				var second: int = populator._aquifer_water_level_at(world_x, world_z)
				_expect(first == second, "aquifer table was not deterministic at %d, %d for seed %d" % [world_x, world_z, seed])
				samples += 1
		var chunk := Vector2i(-3, 4)
		var field := _flat_field(chunk, 100, 0.0)
		var first_data := _air_fixture()
		var second_data := _air_fixture()
		populator._fill_underground_liquids(first_data, field, chunk.x * VoxelDefs.CHUNK_SIZE, chunk.y * VoxelDefs.CHUNK_SIZE)
		populator._fill_underground_liquids(second_data, field, chunk.x * VoxelDefs.CHUNK_SIZE, chunk.y * VoxelDefs.CHUNK_SIZE)
		_expect(first_data == second_data, "aquifer population changed between identical runs for seed %d" % seed)
	print("WORLDGEN WATER DETERMINISM: seeds=%d samples=%d" % [SEEDS.size(), samples])


func _verify_legacy_compatibility() -> void:
	var legacy_config: Dictionary = TEST_CONFIG.duplicate()
	legacy_config["worldgen_version"] = 8
	var populator := VoxelPopulator.new(WorldGenConfig.new(legacy_config), BiomeCatalog.new())
	var fixture_chunk := Vector2i.ZERO
	for chunk_z in range(-12, 13):
		for chunk_x in range(-12, 13):
			var aquifer_hash := WorldGenHash.hash_2d(int(legacy_config.seed) + 907, chunk_x, chunk_z)
			if aquifer_hash % 11 == 0:
				fixture_chunk = Vector2i(chunk_x, chunk_z)
				break
		if fixture_chunk != Vector2i.ZERO:
			break
	var data := _fill_air_fixture(populator, fixture_chunk, 100, 0.0)
	var digest := _sha256(data)
	print("WORLDGEN WATER LEGACY: chunk=%s sha256=%s" % [fixture_chunk, digest])
	_expect(fixture_chunk == Vector2i(-10, -12), "legacy aquifer fixture location changed: %s" % fixture_chunk)
	_expect(digest == "5d0e4ac9ccea24e9786143e1ba7db9ae02fa1b3d404adc1244f9f54634a61e11",
		"legacy aquifer fixture changed: %s" % digest)


func _verify_adjacent_chunk_borders() -> void:
	var shared_water_faces := 0
	var static_boundary_walls := 0
	var table_mismatches := 0
	for seed in SEEDS:
		var populator := _populator_for(seed)
		for chunk_z in range(-5, 6):
			for chunk_x in range(-5, 6):
				var chunk := Vector2i(chunk_x, chunk_z)
				for direction: Vector2i in [Vector2i.RIGHT, Vector2i.DOWN]:
					var neighbor: Vector2i = chunk + direction
					var first := _fill_air_fixture(populator, chunk, 100, 0.0)
					var second := _fill_air_fixture(populator, neighbor, 100, 0.0)
					var border := _border_metrics(first, second, direction)
					shared_water_faces += int(border.shared)
					static_boundary_walls += int(border.static_wall)
					table_mismatches += _count_table_mismatches(populator, first, chunk)
					table_mismatches += _count_table_mismatches(populator, second, neighbor)
	_expect(shared_water_faces > 0, "no generated aquifer region crossed an adjacent chunk border")
	_expect(static_boundary_walls == 0, "aquifer ownership produced %d static chunk-boundary water walls" % static_boundary_walls)
	_expect(table_mismatches == 0, "generated aquifer blocks disagreed with the global table in %d fixture cells" % table_mismatches)
	print("WORLDGEN WATER SEAMS: seeds=%d shared_faces=%d static_walls=%d table_mismatches=%d" % [SEEDS.size(), shared_water_faces, static_boundary_walls, table_mismatches])


func _verify_surface_and_river_protection() -> void:
	var protected_water_cells := 0
	var violations := 0
	for seed in SEEDS:
		var populator := _populator_for(seed)
		var chunk := _find_aquifer_chunk(populator)
		var land_field := _flat_field(chunk, 100, 0.0)
		for local_z in VoxelDefs.CHUNK_SIZE:
			for local_x in VoxelDefs.CHUNK_SIZE:
				var index := ChunkTerrainData.cell_index(local_x, local_z)
				land_field.final_height[index] = 10.0 + float((local_x + local_z) % 7)
		var land_data := _air_fixture()
		populator._fill_underground_liquids(land_data, land_field, chunk.x * VoxelDefs.CHUNK_SIZE, chunk.y * VoxelDefs.CHUNK_SIZE)
		violations += _count_protection_violations(land_data, land_field)
		protected_water_cells += land_data.count(BlockRegistry.BLOCK_WATER)

		var river_field := _flat_field(chunk, 100, 0.75)
		var river_data := _air_fixture()
		populator._fill_underground_liquids(river_data, river_field, chunk.x * VoxelDefs.CHUNK_SIZE, chunk.y * VoxelDefs.CHUNK_SIZE)
		violations += _count_protection_violations(river_data, river_field)
	_expect(protected_water_cells > 0, "surface-clearance fixture did not contain an aquifer")
	_expect(violations == 0, "generated aquifer water crossed the surface or river protection ceiling in %d cells" % violations)
	print("WORLDGEN WATER PROTECTION: seeds=%d water_cells=%d violations=%d" % [SEEDS.size(), protected_water_cells, violations])


func _populator_for(seed: int) -> VoxelPopulator:
	var config: Dictionary = TEST_CONFIG.duplicate()
	config["seed"] = seed
	return VoxelPopulator.new(WorldGenConfig.new(config), BiomeCatalog.new())


func _flat_field(chunk: Vector2i, height: int, river: float) -> ChunkTerrainData:
	var field := ChunkTerrainData.new(chunk.x, chunk.y)
	for index in field.final_height.size():
		field.final_height[index] = float(height)
		field.river[index] = river
	return field


func _air_fixture() -> PackedByteArray:
	var data := PackedByteArray()
	data.resize(VoxelDefs.CHUNK_AREA * VoxelDefs.WORLD_HEIGHT)
	for column in VoxelDefs.CHUNK_AREA:
		data[column] = BlockRegistry.BLOCK_BEDROCK
	return data


func _fill_air_fixture(populator: VoxelPopulator, chunk: Vector2i, height: int, river: float) -> PackedByteArray:
	var data := _air_fixture()
	populator._fill_underground_liquids(data, _flat_field(chunk, height, river), chunk.x * VoxelDefs.CHUNK_SIZE, chunk.y * VoxelDefs.CHUNK_SIZE)
	return data


func _border_metrics(first: PackedByteArray, second: PackedByteArray, direction: Vector2i) -> Dictionary:
	var shared := 0
	var static_wall := false
	for y in range(4, 28):
		var first_water_count := 0
		var second_water_count := 0
		for offset in VoxelDefs.CHUNK_SIZE:
			var first_block: int
			var second_block: int
			if direction == Vector2i.RIGHT:
				first_block = _block(first, VoxelDefs.CHUNK_SIZE - 1, y, offset)
				second_block = _block(second, 0, y, offset)
			else:
				first_block = _block(first, offset, y, VoxelDefs.CHUNK_SIZE - 1)
				second_block = _block(second, offset, y, 0)
			if first_block == BlockRegistry.BLOCK_WATER and second_block == BlockRegistry.BLOCK_WATER:
				shared += 1
			if first_block == BlockRegistry.BLOCK_WATER:
				first_water_count += 1
			if second_block == BlockRegistry.BLOCK_WATER:
				second_water_count += 1
		# The retired chunk-local model produced an entire 16-block face of
		# water beside an entirely dry neighbor at every table depth. A circular
		# global region may have a natural edge, but cannot make this ownership
		# pattern along a complete chunk face.
		if (first_water_count == VoxelDefs.CHUNK_SIZE and second_water_count == 0) \
				or (second_water_count == VoxelDefs.CHUNK_SIZE and first_water_count == 0):
			static_wall = true
	return {"shared": shared, "static_wall": static_wall}


func _count_table_mismatches(populator: VoxelPopulator, data: PackedByteArray, chunk: Vector2i) -> int:
	var mismatches := 0
	for local_z in VoxelDefs.CHUNK_SIZE:
		for local_x in VoxelDefs.CHUNK_SIZE:
			var table: int = populator._aquifer_water_level_at(chunk.x * VoxelDefs.CHUNK_SIZE + local_x, chunk.y * VoxelDefs.CHUNK_SIZE + local_z)
			for y in range(4, 28):
				var expected_water := table >= y
				var actual_water := _block(data, local_x, y, local_z) == BlockRegistry.BLOCK_WATER
				if expected_water != actual_water:
					mismatches += 1
	return mismatches


func _find_aquifer_chunk(populator: VoxelPopulator) -> Vector2i:
	for chunk_z in range(-12, 13):
		for chunk_x in range(-12, 13):
			var world_x: int = chunk_x * VoxelDefs.CHUNK_SIZE + VoxelDefs.CHUNK_SIZE / 2
			var world_z: int = chunk_z * VoxelDefs.CHUNK_SIZE + VoxelDefs.CHUNK_SIZE / 2
			if populator._aquifer_water_level_at(world_x, world_z) >= 4:
				return Vector2i(chunk_x, chunk_z)
	_failures.append("could not find an aquifer fixture region")
	return Vector2i.ZERO


func _count_protection_violations(data: PackedByteArray, field: ChunkTerrainData) -> int:
	var violations := 0
	for local_z in VoxelDefs.CHUNK_SIZE:
		for local_x in VoxelDefs.CHUNK_SIZE:
			var index := ChunkTerrainData.cell_index(local_x, local_z)
			var ceiling: int = int(roundi(field.final_height[index])) - VoxelPopulator.SURFACE_CLEARANCE
			if field.river[index] >= 0.62:
				ceiling = mini(ceiling, VoxelDefs.SEA_LEVEL - 3)
			for y in range(maxi(4, ceiling + 1), VoxelDefs.WORLD_HEIGHT):
				if _block(data, local_x, y, local_z) == BlockRegistry.BLOCK_WATER:
					violations += 1
	return violations


func _block(data: PackedByteArray, x: int, y: int, z: int) -> int:
	return data[x + z * VoxelDefs.DATA_STRIDE_Z + y * VoxelDefs.DATA_STRIDE_Y]


func _sha256(data: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(data)
	return context.finish().hex_encode()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
