extends SceneTree

## Verifies that the compact LOD pipeline stays seam-compatible with full
## generation: per-column top/sub/water choices, the height map, and the
## top-face geometry of the distance mesh must all match the full-detail chunk
## for the same position. A decoration/cave-free generator is used for the
## parity checks so the terrain surface can be compared directly.

const BASE_CONFIG := {
	"seed": 123456789,
	"world_type": 0,
	"terrain_scale": 1.0,
	"tree_density": 1.0,
	"macro_scale": 384.0,
	"river_density": 1.0,
	"erosion_strength": 0.55,
	"regional_erosion": 0.5,
	"hydraulic_erosion": false,
	"cave_density": 1.0,
	"decoration_density": 1.0,
}
const CHUNKS: Array[Vector2i] = [
	Vector2i.ZERO, Vector2i(7, -3), Vector2i(-11, 14), Vector2i(40, 40),
]
const NO_OCEAN := Vector2i(-9999, -9999)

var _failures := 0
var _blocks: BlockRegistry


func _initialize() -> void:
	var clean := TerrainGenerator.new()
	var clean_config := BASE_CONFIG.duplicate()
	clean_config["cave_density"] = 0.0
	clean_config["decoration_density"] = 0.0
	clean.configure(clean_config)
	var decorated := TerrainGenerator.new()
	decorated.configure(BASE_CONFIG)
	var cave_free := TerrainGenerator.new()
	var cave_free_config := BASE_CONFIG.duplicate()
	cave_free_config["cave_density"] = 0.0
	cave_free.configure(cave_free_config)
	_blocks = BlockRegistry.new()
	var mesher := ChunkMesher.new(_blocks)
	for pos in CHUNKS:
		_verify_chunk(clean, decorated, cave_free, mesher, pos)
	_verify_canopy_coverage(decorated)
	_verify_lod_shading(mesher)
	if _failures == 0:
		print("WORLDGEN LOD VERIFY: PASS")
	else:
		print("WORLDGEN LOD VERIFY: FAIL (%d checks)" % _failures)
	quit(1 if _failures > 0 else 0)


func _verify_chunk(clean: TerrainGenerator, decorated: TerrainGenerator, cave_free: TerrainGenerator, mesher: ChunkMesher, pos: Vector2i) -> void:
	var full := clean.generate_data(pos, {}, false)
	var lod := clean.generate_data(pos, {}, true)
	var repeat := clean.generate_data(pos, {}, true)
	if lod.lod_solid_y != repeat.lod_solid_y or lod.lod_solid_id != repeat.lod_solid_id \
			or lod.lod_sub_id != repeat.lod_sub_id or lod.lod_water_y != repeat.lod_water_y \
			or lod.lod_water_level != repeat.lod_water_level:
		_fail("non-deterministic compact columns at %s" % pos)
	if lod.heights != full.heights:
		_fail("height map mismatch at %s" % pos)
	# Compact columns must include tree canopies but be independent of caves.
	var decorated_lod := decorated.generate_data(pos, {}, true)
	var bare_cave_lod := cave_free.generate_data(pos, {}, true)
	if decorated_lod.lod_solid_y != bare_cave_lod.lod_solid_y \
			or decorated_lod.lod_solid_id != bare_cave_lod.lod_solid_id \
			or decorated_lod.lod_sub_id != bare_cave_lod.lod_sub_id:
		_fail("compact canopies depend on cave density at %s" % pos)
	for local_z in VoxelDefs.CHUNK_SIZE:
		for local_x in VoxelDefs.CHUNK_SIZE:
			var column := local_x + local_z * VoxelDefs.DATA_STRIDE_Z
			var scan_solid := -1
			var scan_id := 0
			var scan_water := -1
			for y in range(full.max_y, -1, -1):
				var id: int = full.data[column + y * VoxelDefs.DATA_STRIDE_Y]
				if id == BlockRegistry.BLOCK_AIR:
					continue
				if _blocks.is_water_id(id):
					if scan_water < 0:
						scan_water = y
					continue
				if _blocks.has_flag(id, BlockRegistry.FLAG_CROSS):
					continue
				scan_solid = y
				scan_id = id
				break
			if lod.lod_solid_y[column] != scan_solid or lod.lod_solid_id[column] != scan_id:
				_fail("compact top mismatch at %s column (%d,%d)" % [pos, local_x, local_z])
			if lod.lod_water_y[column] != scan_water:
				_fail("compact water mismatch at %s column (%d,%d)" % [pos, local_x, local_z])
			if scan_solid > 1:
				var below: int = full.data[column + (scan_solid - 1) * VoxelDefs.DATA_STRIDE_Y]
				if lod.lod_sub_id[column] != below:
					_fail("compact sub mismatch at %s column (%d,%d): %d != %d" % [pos, local_x, local_z, lod.lod_sub_id[column], below])
	_verify_top_faces(lod, mesher, pos)
	_verify_compact_neighbors(decorated, mesher, pos)


## Distance chunks must expose a leaf canopy over dense groves and none over
## open water, so forests stay readable past the full-detail ring.
func _verify_canopy_coverage(generator: TerrainGenerator) -> void:
	var grove_pos := _find_biome_chunk(generator, [BiomeCatalog.FOREST, BiomeCatalog.TAIGA, BiomeCatalog.JUNGLE, BiomeCatalog.SWAMP])
	var grove_canopies := 0
	if grove_pos.x != NO_OCEAN.x:
		var grove_lod := generator.generate_data(grove_pos, {}, true)
		for column in VoxelDefs.CHUNK_AREA:
			if _is_tree_block(grove_lod.lod_solid_id[column]):
				grove_canopies += 1
				if grove_lod.lod_solid_y[column] <= VoxelDefs.SEA_LEVEL:
					_fail("distance canopy sits at or below sea level at %s" % grove_pos)
	if grove_canopies < 32:
		_fail("distance grove sample at %s has only %d canopy columns" % [grove_pos, grove_canopies])
	var ocean_pos := _find_biome_chunk(generator, [BiomeCatalog.OCEAN, BiomeCatalog.DEEP_OCEAN])
	if ocean_pos.x != NO_OCEAN.x:
		var ocean_lod := generator.generate_data(ocean_pos, {}, true)
		for column in VoxelDefs.CHUNK_AREA:
			if _is_tree_block(ocean_lod.lod_solid_id[column]):
				_fail("distance canopy appeared over open water at %s" % ocean_pos)
				break
	print("WORLDGEN LOD CANOPY: grove=%s columns=%d ocean=%s" % [grove_pos, grove_canopies, ocean_pos])


func _find_biome_chunk(generator: TerrainGenerator, wanted: Array[int]) -> Vector2i:
	for radius in range(0, 64):
		for step: Vector2i in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]:
			var chunk: Vector2i = Vector2i(1, 1) + step * radius
			var hits := 0
			for dz in [-8, 0, 8]:
				for dx in [-8, 0, 8]:
					var sample: Dictionary = generator.sample_point(chunk.x * 16 + 8 + dx, chunk.y * 16 + 8 + dz)
					if int(sample["dominant_biome_id"]) in wanted:
						hits += 1
			if hits == 9:
				return chunk
	return NO_OCEAN


func _is_tree_block(block_id: int) -> bool:
	if _blocks.has_flag(block_id, BlockRegistry.FLAG_LEAVES):
		return true
	return block_id == BlockRegistry.BLOCK_LOG \
		or block_id == BlockRegistry.BLOCK_BIRCH_LOG \
		or block_id == BlockRegistry.BLOCK_SPRUCE_LOG \
		or block_id == BlockRegistry.BLOCK_JUNGLE_LOG \
		or block_id == BlockRegistry.BLOCK_ACACIA_LOG \
		or block_id == BlockRegistry.BLOCK_MANGROVE_LOG \
		or block_id == BlockRegistry.BLOCK_MANGROVE_ROOTS


## Distance lighting must vary with occlusion instead of flat full-sky shading,
## and deep cliff sides must stop showing the soil block all the way down.
func _verify_lod_shading(mesher: ChunkMesher) -> void:
	var flat := TerrainGenerator.new()
	var flat_config := BASE_CONFIG.duplicate()
	flat_config["world_type"] = WorldGenConfig.WORLD_TYPE_FLAT
	flat_config["decoration_density"] = 0.0
	flat_config["cave_density"] = 0.0
	flat.configure(flat_config)
	var flat_lod := flat.generate_data(Vector2i.ZERO, {}, true)
	var flat_mesh := mesher.build_lod(flat_lod.lod_solid_y, flat_lod.lod_solid_id, flat_lod.lod_sub_id, flat_lod.lod_water_y, flat_lod.lod_water_level, flat_lod.max_y, flat_lod.foliage_tints, flat_lod.water_tints, ChunkMesher.LodNeighbors.new())
	var flat_spread := _top_luminance_spread(flat_mesh)
	if flat_spread > 0.002:
		_fail("flat LOD terrain has occlusion variation (%.4f)" % flat_spread)
	var hilly := TerrainGenerator.new()
	hilly.configure(BASE_CONFIG)
	var hilly_lod := hilly.generate_data(Vector2i(20, -12), {}, true)
	var hilly_mesh := mesher.build_lod(hilly_lod.lod_solid_y, hilly_lod.lod_solid_id, hilly_lod.lod_sub_id, hilly_lod.lod_water_y, hilly_lod.lod_water_level, hilly_lod.max_y, hilly_lod.foliage_tints, hilly_lod.water_tints, ChunkMesher.LodNeighbors.new())
	var hilly_spread := _top_luminance_spread(hilly_mesh)
	if hilly_spread < 0.03:
		_fail("hilly LOD terrain has no occlusion shading (%.4f)" % hilly_spread)
	var stone_side: float = _blocks.layer_for(BlockRegistry.BLOCK_STONE, 2)
	var stone_sides := 0
	for face_index in range(0, hilly_mesh.verts.size(), 4):
		if hilly_mesh.normals[face_index].y > 0.5:
			continue
		if is_equal_approx(hilly_mesh.layers[face_index], stone_side):
			stone_sides += 1
	if stone_sides == 0:
		_fail("deep LOD cliff sides never use the stone layer")
	print("WORLDGEN LOD SHADING: flat_spread=%.4f hilly_spread=%.4f stone_sides=%d" % [flat_spread, hilly_spread, stone_sides])


func _top_luminance_spread(mesh: ChunkMesher.MeshResult) -> float:
	var minimum := INF
	var maximum := -INF
	for face_index in range(0, mesh.verts.size(), 4):
		if mesh.normals[face_index].y < 0.5:
			continue
		var color: Color = mesh.colors[face_index]
		var luminance := color.r + color.g + color.b
		minimum = minf(minimum, luminance)
		maximum = maxf(maximum, luminance)
	if minimum == INF:
		return 0.0
	return maximum - minimum


func _verify_top_faces(lod: TerrainGenerator.GenResult, mesher: ChunkMesher, pos: Vector2i) -> void:
	var lod_mesh := mesher.build_lod(lod.lod_solid_y, lod.lod_solid_id, lod.lod_sub_id, lod.lod_water_y, lod.lod_water_level, lod.max_y, lod.foliage_tints, lod.water_tints, ChunkMesher.LodNeighbors.new())
	var lod_tops := _top_face_heights(lod_mesh)
	if lod_tops.size() != VoxelDefs.CHUNK_AREA:
		_fail("LOD top face count at %s: %d != %d" % [pos, lod_tops.size(), VoxelDefs.CHUNK_AREA])
	for local_z in VoxelDefs.CHUNK_SIZE:
		for local_x in VoxelDefs.CHUNK_SIZE:
			var column := local_x + local_z * VoxelDefs.DATA_STRIDE_Z
			var key := Vector2i(local_x, local_z)
			if not lod_tops.has(key):
				_fail("LOD missing top face at %s for %s" % [pos, key])
			elif int(lod_tops[key]) != lod.lod_solid_y[column]:
				_fail("LOD top face height at %s for %s: %d != %d" % [pos, key, lod_tops[key], lod.lod_solid_y[column]])


## A full-detail chunk that borders LOD chunks must accept compact neighbor
## samples, cull boundary faces, and never read a materialized tile.
func _verify_compact_neighbors(generator: TerrainGenerator, mesher: ChunkMesher, pos: Vector2i) -> void:
	var full := generator.generate_data(pos, {}, false)
	var compact := generator.generate_data(pos, {}, true)
	var neighbors := ChunkMesher.NeighborSet.new()
	for index in VoxelDefs.DIRS_8.size():
		var direction: Vector2i = VoxelDefs.DIRS_8[index]
		neighbors.samples[direction] = ChunkMesher.NeighborSample.from_lod(
			compact.lod_solid_y, compact.lod_solid_id, compact.lod_sub_id, compact.lod_water_y)
		if index < 4:
			neighbors.mask |= (1 << index)
	var with_neighbors := mesher.build(full.data, full.max_y, full.heights, full.foliage_tints, full.water_tints, neighbors)
	var bare := mesher.build(full.data, full.max_y, full.heights, full.foliage_tints, full.water_tints, ChunkMesher.NeighborSet.new())
	if with_neighbors == null or with_neighbors.indices.is_empty():
		_fail("compact neighbors produced no mesh at %s" % pos)
	elif with_neighbors.indices.size() >= bare.indices.size():
		_fail("compact neighbors did not cull boundary faces at %s" % pos)


func _top_face_heights(mesh: ChunkMesher.MeshResult) -> Dictionary:
	var tops := {}
	var index := 0
	while index + 5 < mesh.indices.size():
		var base: int = mesh.indices[index]
		index += 6
		if mesh.normals[base].y <= 0.5:
			continue
		var vertex: Vector3 = mesh.verts[base]
		# Cross-block quads also face up but are inset; only cube quads count.
		if absf(vertex.x - roundf(vertex.x)) > 0.01 or absf(vertex.z - roundf(vertex.z)) > 0.01:
			continue
		tops[Vector2i(int(vertex.x), int(vertex.z) - 1)] = int(vertex.y) - 1
	return tops


func _fail(message: String) -> void:
	_failures += 1
	print("LOD VERIFY FAIL: ", message)
