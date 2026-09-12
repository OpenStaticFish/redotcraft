class_name TerrainGenerator
extends RefCounted

const BIOME_PLAINS := 0
const BIOME_FOREST := 1
const BIOME_DESERT := 2
const BIOME_SNOW := 3
const BIOME_SWAMP := 4

const BIOME_NAMES := ["PLAINS", "FOREST", "DESERT", "SNOWY TUNDRA", "SWAMP"]

const BASE_HEIGHT := 34.0
const SNOW_LINE := 74
const MIN_TERRAIN_HEIGHT := 4
const WORLD_HEIGHT_MARGIN := 24

var world_type := 0
var terrain_scale := 1.0
var tree_density := 1.0

var _seed := 0
var _noises: Array = []


class GenResult:
	var data: PackedByteArray
	var max_y: int
	var heights: PackedByteArray

	func _init(p_data: PackedByteArray, p_max_y: int, p_heights: PackedByteArray) -> void:
		data = p_data
		max_y = p_max_y
		heights = p_heights


func configure(config: Dictionary) -> void:
	_seed = int(config.get("seed", 0))
	world_type = int(config.get("world_type", 0))
	terrain_scale = clampf(float(config.get("terrain_scale", 1.0)), 0.4, 3.0)
	tree_density = clampf(float(config.get("tree_density", 1.0)), 0.0, 3.0)
	if world_type == 2:
		terrain_scale = maxf(terrain_scale, 1.0) * 1.8
	_noises = _make_noise_set()


## Thread-safe: only reads immutable state once configure() has run.
func generate_data(chunk_pos: Vector2i, edits: Dictionary) -> GenResult:
	_ensure_configured()
	var origin_x := chunk_pos.x * VoxelDefs.CHUNK_SIZE
	var origin_z := chunk_pos.y * VoxelDefs.CHUNK_SIZE
	var data := PackedByteArray()
	data.resize(VoxelDefs.CHUNK_AREA * VoxelDefs.WORLD_HEIGHT)
	var max_y := 0
	for local_z in VoxelDefs.CHUNK_SIZE:
		var world_z := origin_z + local_z
		for local_x in VoxelDefs.CHUNK_SIZE:
			var world_x := origin_x + local_x
			var biome := BIOME_PLAINS
			var height := 34
			if world_type != 1:
				biome = _biome_at(world_x, world_z)
				height = _height_at(world_x, world_z)
			var top := BlockRegistry.BLOCK_GRASS
			var sub := BlockRegistry.BLOCK_DIRT
			if biome == BIOME_DESERT:
				top = BlockRegistry.BLOCK_SAND
				sub = BlockRegistry.BLOCK_SAND
			elif biome == BIOME_SNOW:
				top = BlockRegistry.BLOCK_SNOW
			if biome != BIOME_SNOW and height > SNOW_LINE:
				top = BlockRegistry.BLOCK_SNOW
			if height < VoxelDefs.SEA_LEVEL:
				if height >= VoxelDefs.SEA_LEVEL - 3:
					top = BlockRegistry.BLOCK_SAND
				else:
					top = BlockRegistry.BLOCK_GRAVEL if _rand01(world_x, 0, world_z, 31) < 0.6 else BlockRegistry.BLOCK_CLAY
				sub = top
			elif height <= VoxelDefs.SEA_LEVEL + 1 and biome != BIOME_SNOW:
				top = BlockRegistry.BLOCK_SAND
				sub = BlockRegistry.BLOCK_SAND
			var column := local_x + local_z * VoxelDefs.DATA_STRIDE_Z
			for y in range(0, height + 1):
				var id := BlockRegistry.BLOCK_STONE
				if y == 0:
					id = BlockRegistry.BLOCK_BEDROCK
				elif y == 1 and _rand01(world_x, y, world_z, 3) < 0.45:
					id = BlockRegistry.BLOCK_BEDROCK
				elif y == height:
					id = top
				elif y >= height - 3:
					id = sub
				elif y > 3 and y < height - 1:
					if world_type != 1 and _cave_at(world_x, y, world_z):
						continue
					id = _ore_at(world_x, y, world_z)
				data[column + y * VoxelDefs.DATA_STRIDE_Y] = id
			if height < VoxelDefs.SEA_LEVEL:
				for y in range(height + 1, VoxelDefs.SEA_LEVEL + 1):
					data[column + y * VoxelDefs.DATA_STRIDE_Y] = BlockRegistry.BLOCK_WATER
				max_y = maxi(max_y, VoxelDefs.SEA_LEVEL)
			else:
				max_y = maxi(max_y, height)
	max_y = _stamp_trees(chunk_pos, data, max_y)
	for key in edits.keys():
		var block_position: Vector3i = key
		var local_x := block_position.x - origin_x
		var local_z := block_position.z - origin_z
		if local_x < 0 or local_x >= VoxelDefs.CHUNK_SIZE or local_z < 0 or local_z >= VoxelDefs.CHUNK_SIZE:
			continue
		if block_position.y < 0 or block_position.y >= VoxelDefs.WORLD_HEIGHT:
			continue
		var id: int = edits[key]
		data[local_x + local_z * VoxelDefs.DATA_STRIDE_Z + block_position.y * VoxelDefs.DATA_STRIDE_Y] = id
		if id != BlockRegistry.BLOCK_AIR:
			max_y = maxi(max_y, block_position.y)
	return GenResult.new(data, max_y, _build_heights(data, max_y))


## Topmost non-air block per column, used by the mesher to start sky-light
## propagation without scanning from the top of the world.
func _build_heights(data: PackedByteArray, max_y: int) -> PackedByteArray:
	var heights := PackedByteArray()
	heights.resize(VoxelDefs.CHUNK_AREA)
	for local_z in VoxelDefs.CHUNK_SIZE:
		for local_x in VoxelDefs.CHUNK_SIZE:
			var column := local_x + local_z * VoxelDefs.DATA_STRIDE_Z
			for y in range(max_y, -1, -1):
				if data[column + y * VoxelDefs.DATA_STRIDE_Y] != BlockRegistry.BLOCK_AIR:
					heights[column] = y
					break
	return heights


func biome_name(world_position: Vector3) -> String:
	_ensure_configured()
	var biome := _biome_at(floori(world_position.x), floori(world_position.z))
	return BIOME_NAMES[clampi(biome, 0, BIOME_NAMES.size() - 1)]


func find_spawn_position() -> Vector3:
	_ensure_configured()
	for radius in range(0, 64):
		for dx in range(-radius, radius + 1):
			for dz in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dz)) != radius:
					continue
				if _biome_at(dx, dz) == BIOME_SWAMP:
					continue
				var height := _height_at(dx, dz)
				if height > VoxelDefs.SEA_LEVEL + 1:
					return Vector3(float(dx) + 0.5, float(height) + 2.5, float(dz) + 0.5)
	return Vector3(0.5, VoxelDefs.SEA_LEVEL + 12.0, 0.5)


func _ensure_configured() -> void:
	if _noises.is_empty():
		configure({})


func _make_noise_set() -> Array:
	var seeds := [
		[FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.0035, 4, 11],
		[FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.0045, 3, 22],
		[FastNoiseLite.TYPE_SIMPLEX, 0.02, 2, 33],
		[FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.0022, 2, 44],
		[FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.0026, 2, 55],
		[FastNoiseLite.TYPE_CELLULAR, 0.05, 2, 66],
		[FastNoiseLite.TYPE_PERLIN, 0.028, 2, 77],
		[FastNoiseLite.TYPE_SIMPLEX, 0.018, 2, 88],
	]
	var noises: Array = []
	for entry in seeds:
		var noise := FastNoiseLite.new()
		noise.noise_type = entry[0]
		noise.frequency = entry[1]
		noise.fractal_octaves = entry[2]
		noise.seed = entry[3] + _seed
		noises.append(noise)
	return noises


func _height_at(x: int, z: int) -> int:
	var continent: float = _noises[0].get_noise_2d(float(x), float(z))
	var ridge_raw: float = _noises[1].get_noise_2d(float(x), float(z))
	var detail: float = _noises[2].get_noise_2d(float(x), float(z))
	var height := BASE_HEIGHT + continent * 12.0 * terrain_scale
	var mountain := maxf(continent - 0.12, 0.0) * 2.4
	var ridge := 1.0 - absf(ridge_raw)
	height += ridge * ridge * mountain * 36.0 * maxf(terrain_scale, 0.5)
	height += detail * 2.6 * terrain_scale
	var biome := _biome_at(x, z)
	if biome == BIOME_DESERT:
		height = 33.0 + (height - BASE_HEIGHT) * 0.35
	elif biome == BIOME_SWAMP:
		height = minf(height, float(VoxelDefs.SEA_LEVEL) + 3.0) - 1.0
	elif biome == BIOME_SNOW:
		height += mountain * 5.0
	if height > float(VoxelDefs.SEA_LEVEL) - 1.5 and height < float(VoxelDefs.SEA_LEVEL) + 1.5:
		if height < float(VoxelDefs.SEA_LEVEL):
			height = float(VoxelDefs.SEA_LEVEL) - 1.0
		else:
			height = float(VoxelDefs.SEA_LEVEL) + 1.0
	return clampi(roundi(height), MIN_TERRAIN_HEIGHT, VoxelDefs.WORLD_HEIGHT - WORLD_HEIGHT_MARGIN)


func _biome_at(x: int, z: int) -> int:
	var temperature: float = _noises[3].get_noise_2d(float(x), float(z))
	var humidity: float = _noises[4].get_noise_2d(float(x), float(z))
	if temperature < -0.35:
		return BIOME_SNOW
	if temperature > 0.3 and humidity < -0.1:
		return BIOME_DESERT
	if humidity > 0.4:
		return BIOME_SWAMP
	if humidity > 0.1:
		return BIOME_FOREST
	return BIOME_PLAINS


func _cave_at(x: int, y: int, z: int) -> bool:
	var fy := float(y) * 2.4
	var worm: float = _noises[5].get_noise_3d(float(x), fy, float(z))
	var cheese: float = _noises[6].get_noise_3d(float(x), fy * 0.62, float(z))
	return worm > 0.56 or cheese > 0.62


func _ore_at(x: int, y: int, z: int) -> int:
	var hashed := _hash3(x, y, z, 7)
	var roll := float(hashed % 100000) / 100000.0
	if y < 28 and roll < 0.0022:
		return BlockRegistry.BLOCK_GOLD_ORE
	if y < 48 and roll < 0.010:
		return BlockRegistry.BLOCK_IRON_ORE
	if y < 66 and roll < 0.022:
		return BlockRegistry.BLOCK_COAL_ORE
	if roll > 0.9965:
		return BlockRegistry.BLOCK_GRAVEL
	return BlockRegistry.BLOCK_STONE


func _hash3(x: int, y: int, z: int, salt: int) -> int:
	var value := x * 374761393 + y * 668265263 + z * 1442695041 + salt * 1013904223 + _seed * 2654435761
	value = (value ^ (value >> 13)) * 1274126177
	value = value ^ (value >> 16)
	return value & 0x7FFFFFFF


func _rand01(x: int, y: int, z: int, salt: int) -> float:
	return float(_hash3(x, y, z, salt)) / 2147483647.0


func _stamp_trees(chunk_pos: Vector2i, data: PackedByteArray, max_y: int) -> int:
	if world_type == 1 or tree_density <= 0.0:
		return max_y
	var origin_x := chunk_pos.x * VoxelDefs.CHUNK_SIZE
	var origin_z := chunk_pos.y * VoxelDefs.CHUNK_SIZE
	for local_z in range(-2, VoxelDefs.CHUNK_SIZE + 2):
		var world_z := origin_z + local_z
		for local_x in range(-2, VoxelDefs.CHUNK_SIZE + 2):
			var world_x := origin_x + local_x
			var biome := _biome_at(world_x, world_z)
			var density := 0.0
			match biome:
				BIOME_FOREST:
					density = 0.06
				BIOME_PLAINS:
					density = 0.012
				BIOME_SNOW:
					density = 0.05
				BIOME_SWAMP:
					density = 0.035
				BIOME_DESERT:
					density = 0.018
			density *= tree_density
			if density <= 0.0:
				continue
			if _rand01(world_x, 0, world_z, 101) > density:
				continue
			var height := _height_at(world_x, world_z)
			if height <= VoxelDefs.SEA_LEVEL + 1 or height > 72:
				continue
			if _rand01(world_x, 1, world_z, 55) > 0.7:
				continue
			match biome:
				BIOME_DESERT:
					max_y = _stamp_cactus(local_x, height, local_z, world_x, world_z, data, max_y)
				BIOME_SNOW:
					max_y = _stamp_spruce(local_x, height, local_z, world_x, world_z, data, max_y)
				BIOME_FOREST:
					if _rand01(world_x, 2, world_z, 88) < 0.3:
						max_y = _stamp_birch(local_x, height, local_z, world_x, world_z, data, max_y)
					else:
						max_y = _stamp_oak(local_x, height, local_z, world_x, world_z, data, max_y)
				_:
					max_y = _stamp_oak(local_x, height, local_z, world_x, world_z, data, max_y)
	return max_y


func _stamp(data: PackedByteArray, local_x: int, y: int, local_z: int, id: int) -> void:
	if local_x < 0 or local_x >= VoxelDefs.CHUNK_SIZE or local_z < 0 or local_z >= VoxelDefs.CHUNK_SIZE:
		return
	if y < 0 or y >= VoxelDefs.WORLD_HEIGHT:
		return
	data[local_x + local_z * VoxelDefs.DATA_STRIDE_Z + y * VoxelDefs.DATA_STRIDE_Y] = id


func _stamp_oak(local_x: int, ground_y: int, local_z: int, world_x: int, world_z: int, data: PackedByteArray, max_y: int) -> int:
	var trunk := 4 + int(_rand01(world_x, 2, world_z, 77) * 3.0)
	var top_y := ground_y + trunk
	for offset in range(1, trunk + 1):
		_stamp(data, local_x, ground_y + offset, local_z, BlockRegistry.BLOCK_LOG)
	for layer in range(-2, 2):
		var y := top_y + layer
		var radius := 2 if layer < 0 else 1
		for dx in range(-radius, radius + 1):
			for dz in range(-radius, radius + 1):
				if dx == 0 and dz == 0 and layer < 1:
					continue
				if absi(dx) == radius and absi(dz) == radius:
					if layer >= 0 or _rand01(world_x + dx, y, world_z + dz, 41) < 0.5:
						continue
				_stamp(data, local_x + dx, y, local_z + dz, BlockRegistry.BLOCK_LEAVES)
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			if absi(dx) + absi(dz) <= 1:
				_stamp(data, local_x + dx, top_y + 2, local_z + dz, BlockRegistry.BLOCK_LEAVES)
	return maxi(max_y, top_y + 2)


func _stamp_birch(local_x: int, ground_y: int, local_z: int, world_x: int, world_z: int, data: PackedByteArray, max_y: int) -> int:
	var trunk := 5 + int(_rand01(world_x, 3, world_z, 79) * 3.0)
	var top_y := ground_y + trunk
	for offset in range(1, trunk + 1):
		_stamp(data, local_x, ground_y + offset, local_z, BlockRegistry.BLOCK_BIRCH_LOG)
	for layer in range(-2, 2):
		var y := top_y + layer
		var radius := 1 if layer > -2 else 2
		for dx in range(-radius, radius + 1):
			for dz in range(-radius, radius + 1):
				if dx == 0 and dz == 0 and layer < 1:
					continue
				if absi(dx) + absi(dz) > radius + 1:
					continue
				_stamp(data, local_x + dx, y, local_z + dz, BlockRegistry.BLOCK_BIRCH_LEAVES)
	_stamp(data, local_x, top_y + 1, local_z, BlockRegistry.BLOCK_BIRCH_LEAVES)
	return maxi(max_y, top_y + 1)


func _stamp_spruce(local_x: int, ground_y: int, local_z: int, world_x: int, world_z: int, data: PackedByteArray, max_y: int) -> int:
	var trunk := 6 + int(_rand01(world_x, 4, world_z, 91) * 4.0)
	for offset in range(1, trunk + 1):
		_stamp(data, local_x, ground_y + offset, local_z, BlockRegistry.BLOCK_SPRUCE_LOG)
	for offset in range(2, trunk + 1):
		var y := ground_y + offset
		var taper := float(trunk - offset) / float(trunk)
		var radius := 0
		if taper > 0.55:
			radius = 2
		elif taper > 0.2:
			radius = 1
		for dx in range(-radius, radius + 1):
			for dz in range(-radius, radius + 1):
				if dx == 0 and dz == 0:
					continue
				if absi(dx) + absi(dz) > radius + 1:
					continue
				if radius == 2 and absi(dx) == 2 and absi(dz) == 2:
					continue
				_stamp(data, local_x + dx, y, local_z + dz, BlockRegistry.BLOCK_SPRUCE_LEAVES)
	_stamp(data, local_x, ground_y + trunk + 1, local_z, BlockRegistry.BLOCK_SPRUCE_LEAVES)
	return maxi(max_y, ground_y + trunk + 1)


func _stamp_cactus(local_x: int, ground_y: int, local_z: int, world_x: int, world_z: int, data: PackedByteArray, max_y: int) -> int:
	if local_x >= 0 and local_x < VoxelDefs.CHUNK_SIZE and local_z >= 0 and local_z < VoxelDefs.CHUNK_SIZE:
		if data[local_x + local_z * VoxelDefs.DATA_STRIDE_Z + ground_y * VoxelDefs.DATA_STRIDE_Y] != BlockRegistry.BLOCK_SAND:
			return max_y
	var height := 1 + int(_rand01(world_x, 5, world_z, 13) * 3.0)
	for offset in range(1, height + 1):
		_stamp(data, local_x, ground_y + offset, local_z, BlockRegistry.BLOCK_CACTUS)
	return maxi(max_y, ground_y + height)
