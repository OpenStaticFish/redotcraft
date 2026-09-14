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
	"decoration_density": 1.0,
}

var _failures := PackedStringArray()
var _registry: BlockRegistry
var _mesher: ChunkMesher


func _initialize() -> void:
	_registry = BlockRegistry.new()
	_mesher = ChunkMesher.new(_registry)
	_verify_cave_catalog()
	_verify_endless_cave_network()
	_verify_cave_dressing()
	_verify_surface_exclusion()
	_verify_geode()
	_verify_cave_lighting()
	if _failures.is_empty():
		print("WORLDGEN CAVE VERIFY: PASS")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("WORLDGEN CAVE VERIFY: FAIL (", _failures.size(), ")")
	quit(1)


func _verify_cave_catalog() -> void:
	var catalog := BiomeCatalog.new()
	_expect(catalog.name_for(BiomeCatalog.LUSH_CAVES) == "lush_caves", "lush cave biome was not appended to BiomeCatalog")
	_expect(catalog.name_for(BiomeCatalog.DEEP_DARK) == "deep_dark", "deep-dark biome was not appended to BiomeCatalog")
	var found_lush := false
	var found_deep := false
	var middle_regions := 0
	var middle_lush := 0
	for cell_z in range(-8, 9):
		for cell_x in range(-8, 9):
			var x := cell_x * BiomeCatalog.CAVE_REGION_SIZE + 16
			var z := cell_z * BiomeCatalog.CAVE_REGION_SIZE + 16
			var middle_biome := BiomeCatalog.cave_biome_at(int(TEST_CONFIG.seed), x, 50, z)
			found_lush = found_lush or middle_biome == BiomeCatalog.LUSH_CAVES
			found_deep = found_deep or BiomeCatalog.cave_biome_at(int(TEST_CONFIG.seed), x, 24, z) == BiomeCatalog.DEEP_DARK
			middle_regions += 1
			if middle_biome == BiomeCatalog.LUSH_CAVES:
				middle_lush += 1
	_expect(found_lush, "cave classifier produced no lush regions")
	_expect(found_deep, "cave classifier produced no deep-dark regions")
	_expect(float(middle_lush) / float(middle_regions) >= 0.65, "lush cave regions are too sparse to discover reliably")
	_expect(not BiomeCatalog.is_cave_biome(BiomeCatalog.PLAINS), "surface biome was classified as a cave biome")


func _verify_endless_cave_network() -> void:
	var setup := _worldgen_services()
	var populator: VoxelPopulator = setup.populator
	var sampler: TerrainSampler = setup.sampler
	# The canonical trunk advances one global macro cell on every step. This is
	# the topology guarantee: unlike the legacy 2-4 segment worms, it cannot end.
	var cell := Vector2i.ZERO
	var visited_cells := {}
	for step in 128:
		visited_cells[cell] = true
		cell += populator._cave_primary_offset(cell.x, 2, cell.y)
	_expect(visited_cells.size() == 128 and cell.x + cell.y == 128,
		"canonical cave trunk terminated or looped instead of continuing globally")

	# Carve the hybrid field independently in 25 chunks, then flood it as one volume.
	# A large component spanning the region proves stamps reproduce across chunk
	# borders and form an explorable network rather than isolated local pockets.
	const chunk_radius := 2
	const width := (chunk_radius * 2 + 1) * VoxelDefs.CHUNK_SIZE
	const depth := width
	const height := 96
	var cave_air := PackedByteArray()
	cave_air.resize(width * depth * height)
	for chunk_z in range(-chunk_radius, chunk_radius + 1):
		for chunk_x in range(-chunk_radius, chunk_radius + 1):
			var chunk_pos := Vector2i(chunk_x, chunk_z)
			var field := sampler.build_field(chunk_pos)
			_set_field_height(field, 100.0)
			var data := _solid_fixture(100)
			populator._carve_noise_caves(data, field, chunk_x * VoxelDefs.CHUNK_SIZE, chunk_z * VoxelDefs.CHUNK_SIZE)
			populator._carve_cave_network(data, field, chunk_x * VoxelDefs.CHUNK_SIZE, chunk_z * VoxelDefs.CHUNK_SIZE)
			for y in range(4, height):
				for local_z in VoxelDefs.CHUNK_SIZE:
					for local_x in VoxelDefs.CHUNK_SIZE:
						if _block(data, local_x, y, local_z) != BlockRegistry.BLOCK_AIR:
							continue
						var volume_x := (chunk_x + chunk_radius) * VoxelDefs.CHUNK_SIZE + local_x
						var volume_z := (chunk_z + chunk_radius) * VoxelDefs.CHUNK_SIZE + local_z
						cave_air[(y * depth + volume_z) * width + volume_x] = 1
	var metrics := _largest_air_component(cave_air, width, height, depth)
	var cave_share := float(cave_air.count(1)) / float(cave_air.size())
	_expect(cave_share >= 0.025, "hybrid cave field is too sparse to find through ordinary exploration")
	_expect(cave_share <= 0.24, "hybrid cave field removes too much underground terrain")
	_expect(int(metrics.count) >= 2500, "largest cave network component is too small to sustain exploration")
	_expect(maxi(int(metrics.span_x), int(metrics.span_z)) >= width - 2,
		"cave network does not remain connected across the generated multi-chunk region")
	_expect(int(metrics.span_y) >= 24, "cave network has no meaningful vertical connections")
	print("WORLDGEN CAVE NETWORK: air=", snappedf(cave_share * 100.0, 0.01), "% component=", metrics.count,
		" span=", metrics.span_x, "x", metrics.span_y, "x", metrics.span_z)


func _verify_cave_dressing() -> void:
	var setup := _worldgen_services()
	var populator: VoxelPopulator = setup.populator
	var sampler: TerrainSampler = setup.sampler
	for cave_biome in [BiomeCatalog.LUSH_CAVES, BiomeCatalog.DEEP_DARK]:
		var chunk_pos := _find_cave_chunk(cave_biome)
		var field := sampler.build_field(chunk_pos)
		_set_field_height(field, 100.0)
		var data := _room_fixture(68, 9, 59)
		populator._decorate_caves(data, field, chunk_pos.x * VoxelDefs.CHUNK_SIZE, chunk_pos.y * VoxelDefs.CHUNK_SIZE)
		if cave_biome == BiomeCatalog.LUSH_CAVES:
			var lush_surface_blocks := data.count(BlockRegistry.BLOCK_MOSS) + data.count(BlockRegistry.BLOCK_CAVE_MOSS)
			_expect(lush_surface_blocks >= 24, "lush cave material patches are too sparse to read visually")
			_expect(data.count(BlockRegistry.BLOCK_CAVE_MOSS) > 0, "lush cave dressing placed no vegetation")
		else:
			var deep_surface_blocks := data.count(BlockRegistry.BLOCK_DEEPSTONE) + data.count(BlockRegistry.BLOCK_SCULK)
			_expect(deep_surface_blocks >= 24, "deep-dark material patches are too sparse to read visually")
			_expect(data.count(BlockRegistry.BLOCK_SCULK) > 0, "deep-dark dressing placed no sculk")
	var normal_chunk := Vector2i.ZERO
	var normal_field := sampler.build_field(normal_chunk)
	_set_field_height(normal_field, 100.0)
	var normal_data := _room_fixture(52, 9, 43)
	populator._decorate_caves(normal_data, normal_field, 0, 0)
	_expect(normal_data.count(BlockRegistry.BLOCK_DRIPSTONE) > 0, "cave dressing placed no stalactites/stalagmites")
	_expect(normal_data.count(BlockRegistry.BLOCK_WATER) > 0, "cave dressing placed no small underground pools")


func _verify_surface_exclusion() -> void:
	var setup := _worldgen_services()
	var populator: VoxelPopulator = setup.populator
	var sampler: TerrainSampler = setup.sampler
	var field := sampler.build_field(Vector2i.ZERO)
	_set_field_height(field, 30.0)
	var ocean := PackedByteArray()
	ocean.resize(VoxelDefs.CHUNK_AREA * VoxelDefs.WORLD_HEIGHT)
	for y in range(31):
		for column in VoxelDefs.CHUNK_AREA:
			ocean[y * VoxelDefs.DATA_STRIDE_Y + column] = BlockRegistry.BLOCK_STONE
	for y in range(31, VoxelDefs.SEA_LEVEL + 1):
		for column in VoxelDefs.CHUNK_AREA:
			ocean[y * VoxelDefs.DATA_STRIDE_Y + column] = BlockRegistry.BLOCK_WATER
	var unchanged := ocean.duplicate()
	populator._decorate_caves(ocean, field, 0, 0)
	_expect(ocean == unchanged, "cave dressing escaped onto the ocean surface")

	_set_field_height(field, 52.0)
	var land := PackedByteArray()
	land.resize(VoxelDefs.CHUNK_AREA * VoxelDefs.WORLD_HEIGHT)
	for y in range(53):
		for column in VoxelDefs.CHUNK_AREA:
			land[y * VoxelDefs.DATA_STRIDE_Y + column] = BlockRegistry.BLOCK_STONE
	var land_unchanged := land.duplicate()
	populator._decorate_caves(land, field, 0, 0)
	_expect(land == land_unchanged, "cave dressing escaped onto open land")


func _verify_geode() -> void:
	var setup := _worldgen_services()
	var populator: VoxelPopulator = setup.populator
	var sampler: TerrainSampler = setup.sampler
	var field := sampler.build_field(Vector2i.ZERO)
	var data := PackedByteArray()
	data.resize(VoxelDefs.CHUNK_AREA * VoxelDefs.WORLD_HEIGHT)
	for y in range(0, 64):
		for column in VoxelDefs.CHUNK_AREA:
			data[y * VoxelDefs.DATA_STRIDE_Y + column] = BlockRegistry.BLOCK_BEDROCK if y == 0 else BlockRegistry.BLOCK_STONE
	populator._stamp_geode(data, field, Vector3i(8, 28, 8), 7, 991)
	_expect(data.count(BlockRegistry.BLOCK_GEODE_SHELL) > 0, "geode has no outer shell")
	_expect(data.count(BlockRegistry.BLOCK_CALCITE) > 0, "geode has no calcite lining")
	_expect(data.count(BlockRegistry.BLOCK_AMETHYST) > 0, "geode has no amethyst deposits")
	_expect(data.count(BlockRegistry.BLOCK_CRYSTAL_BUD) > 0, "geode has no crystal formations")
	_expect(_block(data, 8, 28, 8) == BlockRegistry.BLOCK_AIR, "geode center is not hollow")
	_expect(_block(data, 8, 0, 8) == BlockRegistry.BLOCK_BEDROCK, "geode overwrote bedrock")


func _verify_cave_lighting() -> void:
	var sealed := _room_fixture(42, 8, 30)
	var sealed_heights := _heights(sealed, 42)
	var closed_volume := _mesher.build_light_volume(sealed, 42, sealed_heights, ChunkMesher.NeighborSet.new())
	_expect(closed_volume.w == VoxelDefs.CHUNK_SIZE * 3 and closed_volume.d == VoxelDefs.CHUNK_SIZE * 3,
		"cave light footprint is not the documented 3x3 chunks")
	_expect(closed_volume.h == 45, "cave light volume height did not keep the max-y padding")
	_expect(closed_volume.blocks.size() == closed_volume.w * closed_volume.d * closed_volume.h,
		"large-cavern light-volume bounds do not match storage")
	_expect(_sky(closed_volume, ChunkMesher.LIGHT_PAD + 8, 18, ChunkMesher.LIGHT_PAD + 8) == 0,
		"sealed cave received sky light through a missing neighbor")

	# A west-neighbor opening illuminates a connected large cavern. At fourteen
	# horizontal steps it retains level one; the finite 15-level flood cannot
	# influence cells farther away, proving the one-chunk pad is sufficient.
	var west := _room_fixture(42, 8, 30)
	for y in range(30, 43):
		west[15 + 8 * VoxelDefs.DATA_STRIDE_Z + y * VoxelDefs.DATA_STRIDE_Y] = BlockRegistry.BLOCK_AIR
	var neighbors := ChunkMesher.NeighborSet.new()
	neighbors.samples[Vector2i(-1, 0)] = ChunkMesher.NeighborSample.new(west, 42, _heights(west, 42))
	var open_volume := _mesher.build_light_volume(sealed, 42, sealed_heights, neighbors)
	var near_level := _sky(open_volume, ChunkMesher.LIGHT_PAD, 29, ChunkMesher.LIGHT_PAD + 8)
	var far_level := _sky(open_volume, ChunkMesher.LIGHT_PAD + 14, 29, ChunkMesher.LIGHT_PAD + 8)
	_expect(near_level >= 14, "large cave opening did not seed skylight into the connected cavern")
	_expect(far_level == 0, "sky light propagated beyond its finite 15-level reach")
	var wet_cave := sealed.duplicate()
	wet_cave[0 + 8 * VoxelDefs.DATA_STRIDE_Z + 29 * VoxelDefs.DATA_STRIDE_Y] = BlockRegistry.BLOCK_WATER
	var wet_volume := _mesher.build_light_volume(wet_cave, 42, sealed_heights, neighbors)
	_expect(_sky(wet_volume, ChunkMesher.LIGHT_PAD, 29, ChunkMesher.LIGHT_PAD + 8) == 12,
		"side-lit cave water did not apply its three-level attenuation")

	# Rows above a committed neighbor's max_y are known air, while a genuinely
	# absent tile stays stone. Confusing the two creates false light walls at
	# borders between a low chunk and a taller center chunk.
	var low_neighbor := _room_fixture(10, 4, 8)
	var height_neighbors := ChunkMesher.NeighborSet.new()
	height_neighbors.samples[Vector2i(-1, 0)] = ChunkMesher.NeighborSample.new(low_neighbor, 10, _heights(low_neighbor, 10))
	var height_volume := _mesher.build_light_volume(sealed, 42, sealed_heights, height_neighbors)
	_expect(height_volume.blocks[_volume_index(height_volume, ChunkMesher.LIGHT_PAD - 1, 20, ChunkMesher.LIGHT_PAD + 8)] == BlockRegistry.BLOCK_AIR,
		"known neighbor air above max_y became an artificial solid light wall")
	_expect(height_volume.blocks[_volume_index(height_volume, ChunkMesher.LIGHT_PAD * 3 - 1, 20, ChunkMesher.LIGHT_PAD + 8)] == BlockRegistry.BLOCK_STONE,
		"missing neighbor stopped acting as a closed light boundary")

	var crystal_data := sealed.duplicate()
	crystal_data[8 + 8 * VoxelDefs.DATA_STRIDE_Z + 18 * VoxelDefs.DATA_STRIDE_Y] = BlockRegistry.BLOCK_CRYSTAL_BUD
	var crystal_volume := _mesher.build_light_volume(crystal_data, 42, sealed_heights, ChunkMesher.NeighborSet.new())
	var emitter_index := _volume_index(crystal_volume, ChunkMesher.LIGHT_PAD + 8, 18, ChunkMesher.LIGHT_PAD + 8)
	_expect(not crystal_volume.block_b.is_empty() and crystal_volume.block_b[emitter_index] > 0,
		"crystal formation did not seed colored block light")


func _worldgen_services() -> Dictionary:
	var config := WorldGenConfig.new(TEST_CONFIG)
	var biomes := BiomeCatalog.new()
	var sampler := TerrainSampler.new(config, TerrainProfileCatalog.new(), biomes)
	return {"populator": VoxelPopulator.new(config, biomes, sampler), "sampler": sampler}


func _find_cave_chunk(target: int) -> Vector2i:
	var y := 50 if target == BiomeCatalog.LUSH_CAVES else 24
	for cell_z in range(-10, 11):
		for cell_x in range(-10, 11):
			var world_x := cell_x * BiomeCatalog.CAVE_REGION_SIZE + 16
			var world_z := cell_z * BiomeCatalog.CAVE_REGION_SIZE + 16
			if BiomeCatalog.cave_biome_at(int(TEST_CONFIG.seed), world_x, y, world_z) == target:
				return Vector2i(WorldGenHash.floor_div(world_x, VoxelDefs.CHUNK_SIZE), WorldGenHash.floor_div(world_z, VoxelDefs.CHUNK_SIZE))
	_failures.append("could not find cave biome %d fixture region" % target)
	return Vector2i.ZERO


func _room_fixture(max_y: int, floor_y: int, ceiling_y: int) -> PackedByteArray:
	var data := PackedByteArray()
	data.resize(VoxelDefs.CHUNK_AREA * VoxelDefs.WORLD_HEIGHT)
	for y in range(max_y + 1):
		for column in VoxelDefs.CHUNK_AREA:
			data[y * VoxelDefs.DATA_STRIDE_Y + column] = BlockRegistry.BLOCK_BEDROCK if y == 0 else BlockRegistry.BLOCK_STONE
	for y in range(floor_y + 1, ceiling_y):
		for z in VoxelDefs.CHUNK_SIZE:
			for x in VoxelDefs.CHUNK_SIZE:
				data[x + z * VoxelDefs.DATA_STRIDE_Z + y * VoxelDefs.DATA_STRIDE_Y] = BlockRegistry.BLOCK_AIR
	return data


func _solid_fixture(max_y: int) -> PackedByteArray:
	var data := PackedByteArray()
	data.resize(VoxelDefs.CHUNK_AREA * VoxelDefs.WORLD_HEIGHT)
	for y in range(max_y + 1):
		for column in VoxelDefs.CHUNK_AREA:
			data[y * VoxelDefs.DATA_STRIDE_Y + column] = BlockRegistry.BLOCK_BEDROCK if y == 0 else BlockRegistry.BLOCK_STONE
	return data


func _largest_air_component(cave_air: PackedByteArray, width: int, height: int, depth: int) -> Dictionary:
	var visited := PackedByteArray()
	visited.resize(cave_air.size())
	var largest := {"count": 0, "span_x": 0, "span_y": 0, "span_z": 0}
	var directions: Array[Vector3i] = [Vector3i.LEFT, Vector3i.RIGHT, Vector3i.DOWN, Vector3i.UP, Vector3i.FORWARD, Vector3i.BACK]
	for start in cave_air.size():
		if cave_air[start] == 0 or visited[start] != 0:
			continue
		var queue := PackedInt32Array([start])
		visited[start] = 1
		var cursor := 0
		var count := 0
		var min_pos := Vector3i(width, height, depth)
		var max_pos := Vector3i.ZERO
		while cursor < queue.size():
			var current := queue[cursor]
			cursor += 1
			var x: int = current % width
			var yz: int = current / width
			var z: int = yz % depth
			var y: int = yz / depth
			count += 1
			min_pos = min_pos.min(Vector3i(x, y, z))
			max_pos = max_pos.max(Vector3i(x, y, z))
			for direction in directions:
				var neighbor: Vector3i = Vector3i(x, y, z) + direction
				if neighbor.x < 0 or neighbor.x >= width or neighbor.y < 0 or neighbor.y >= height or neighbor.z < 0 or neighbor.z >= depth:
					continue
				var neighbor_index: int = (neighbor.y * depth + neighbor.z) * width + neighbor.x
				if cave_air[neighbor_index] == 0 or visited[neighbor_index] != 0:
					continue
				visited[neighbor_index] = 1
				queue.append(neighbor_index)
		if count > int(largest.count):
			largest = {
				"count": count,
				"span_x": max_pos.x - min_pos.x + 1,
				"span_y": max_pos.y - min_pos.y + 1,
				"span_z": max_pos.z - min_pos.z + 1,
			}
	return largest


func _set_field_height(field: ChunkTerrainData, height: float) -> void:
	for index in field.final_height.size():
		field.final_height[index] = height


func _heights(data: PackedByteArray, max_y: int) -> PackedInt32Array:
	var heights := PackedInt32Array()
	heights.resize(VoxelDefs.CHUNK_AREA)
	heights.fill(-1)
	for column in VoxelDefs.CHUNK_AREA:
		for y in range(max_y, -1, -1):
			if data[column + y * VoxelDefs.DATA_STRIDE_Y] != BlockRegistry.BLOCK_AIR:
				heights[column] = y
				break
	return heights


func _block(data: PackedByteArray, x: int, y: int, z: int) -> int:
	return data[x + z * VoxelDefs.DATA_STRIDE_Z + y * VoxelDefs.DATA_STRIDE_Y]


func _volume_index(volume: ChunkMesher.LightVolume, x: int, y: int, z: int) -> int:
	return (y * volume.d + z) * volume.w + x


func _sky(volume: ChunkMesher.LightVolume, x: int, y: int, z: int) -> int:
	return volume.sky[_volume_index(volume, x, y, z)]


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
