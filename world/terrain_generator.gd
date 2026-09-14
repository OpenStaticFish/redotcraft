class_name TerrainGenerator
extends RefCounted

## Facade for the immutable, worker-safe world-generation pipeline. Terrain
## sampling and voxel population are separated so each subsystem can be tuned
## or replaced without changing VoxelWorld's chunk contract.

class GenResult:
	var data: PackedByteArray
	var max_y: int
	var heights: PackedInt32Array
	var foliage_tints: PackedColorArray
	var water_tints: PackedColorArray
	var timings: Dictionary
	var lod_solid_y := PackedInt32Array()
	var lod_solid_id := PackedByteArray()
	var lod_sub_id := PackedByteArray()
	var lod_water_y := PackedInt32Array()
	var lod_water_level := PackedByteArray()

	func _init(p_data: PackedByteArray, p_max_y: int, p_heights: PackedInt32Array, p_foliage_tints: PackedColorArray, p_water_tints: PackedColorArray, p_timings: Dictionary) -> void:
		data = p_data
		max_y = p_max_y
		heights = p_heights
		foliage_tints = p_foliage_tints
		water_tints = p_water_tints
		timings = p_timings


var _config: WorldGenConfig
var _profiles: TerrainProfileCatalog
var _biomes: BiomeCatalog
var _sampler: TerrainSampler
var _populator: VoxelPopulator


func configure(source: Dictionary) -> void:
	_config = WorldGenConfig.from_dictionary(source)
	_profiles = TerrainProfileCatalog.new()
	_biomes = BiomeCatalog.new()
	_sampler = TerrainSampler.new(_config, _profiles, _biomes)
	_populator = VoxelPopulator.new(_config, _biomes, _sampler)


## Thread-safe after configure(): all pipeline services are immutable and all
## generated arrays are owned by this call's worker job.
func generate_data(chunk_pos: Vector2i, edits: Dictionary, lod: bool = false) -> GenResult:
	_ensure_configured()
	var total_start := Time.get_ticks_usec()
	var terrain_start := total_start
	var field: ChunkTerrainData = _sampler.build_field(chunk_pos)
	var terrain_us := Time.get_ticks_usec() - terrain_start
	var populate_start := Time.get_ticks_usec()
	if lod:
		var compact: Dictionary = _populator.populate_lod(chunk_pos, field)
		var populate_us := Time.get_ticks_usec() - populate_start
		var heights_start := Time.get_ticks_usec()
		var lod_heights := _build_lod_heights(compact["solid_y"], compact["water_y"])
		var heights_us := Time.get_ticks_usec() - heights_start
		var result := GenResult.new(PackedByteArray(), int(compact["max_y"]), lod_heights,
			_build_foliage_tints(field), _build_water_tints(field), {
				"terrain_us": terrain_us,
				"populate_us": populate_us,
				"heightmap_us": heights_us,
				"generation_us": Time.get_ticks_usec() - total_start,
			})
		result.lod_solid_y = compact["solid_y"]
		result.lod_solid_id = compact["solid_id"]
		result.lod_sub_id = compact["sub_id"]
		result.lod_water_y = compact["water_y"]
		result.lod_water_level = compact["water_level"]
		return result
	var populated: Dictionary = _populator.populate(chunk_pos, field, edits, true)
	var populate_us := Time.get_ticks_usec() - populate_start
	var data: PackedByteArray = populated["data"]
	var max_y: int = populated["max_y"]
	var heights_start := Time.get_ticks_usec()
	var heights := _build_heights(data, max_y)
	var heights_us := Time.get_ticks_usec() - heights_start
	return GenResult.new(data, max_y, heights, _build_foliage_tints(field), _build_water_tints(field), {
		"terrain_us": terrain_us,
		"populate_us": populate_us,
		"heightmap_us": heights_us,
		"generation_us": Time.get_ticks_usec() - total_start,
	})


func _build_foliage_tints(field: ChunkTerrainData) -> PackedColorArray:
	var tints := PackedColorArray()
	tints.resize(VoxelDefs.CHUNK_AREA)
	var reference := _biomes.foliage_color(BiomeCatalog.PLAINS)
	for local_z in VoxelDefs.CHUNK_SIZE:
		for local_x in VoxelDefs.CHUNK_SIZE:
			var column := local_x + local_z * VoxelDefs.DATA_STRIDE_Z
			var field_index := ChunkTerrainData.cell_index(local_x, local_z)
			# Discrete generation uses coherent ecotone dominant patches. Blend
			# the continuous climate pair for foliage tint; both values are shared by
			# adjacent chunk fields, so this remains deterministic and seam-safe.
			var primary := _biomes.foliage_color(int(field.biome_id[field_index]))
			var secondary := _biomes.foliage_color(int(field.biome_secondary_id[field_index]))
			var blend := float(field.biome_blend[field_index]) / 255.0
			var biome_color_value := primary.lerp(secondary, blend)
			tints[column] = Color(
				clampf(biome_color_value.r / maxf(reference.r, 0.01), 0.68, 1.28),
				clampf(biome_color_value.g / maxf(reference.g, 0.01), 0.68, 1.28),
				clampf(biome_color_value.b / maxf(reference.b, 0.01), 0.68, 1.28), 1.0)
	return tints


func _build_water_tints(field: ChunkTerrainData) -> PackedColorArray:
	var tints := PackedColorArray()
	tints.resize(VoxelDefs.CHUNK_AREA)
	for local_z in VoxelDefs.CHUNK_SIZE:
		for local_x in VoxelDefs.CHUNK_SIZE:
			var column := local_x + local_z * VoxelDefs.DATA_STRIDE_Z
			var field_index := ChunkTerrainData.cell_index(local_x, local_z)
			var primary := _biomes.water_tint(int(field.biome_id[field_index]))
			var secondary := _biomes.water_tint(int(field.biome_secondary_id[field_index]))
			var blend := float(field.biome_blend[field_index]) / 255.0
			tints[column] = primary.lerp(secondary, blend)
	return tints


func biome_name(world_position: Vector3) -> String:
	_ensure_configured()
	var sample: Dictionary = _sampler.sample_point(floori(world_position.x), floori(world_position.z))
	return _biomes.name_for(int(sample["dominant_biome_id"])).replace("_", " ").to_upper()


func sample_point(world_x: int, world_z: int) -> Dictionary:
	_ensure_configured()
	var sample := _sampler.sample_point(world_x, world_z)
	sample["biome_name"] = _biomes.name_for(int(sample["dominant_biome_id"]))
	sample["profile_name"] = _profiles.name_for(int(sample["profile_id"]))
	return sample


## Cheap dominant-biome identity for ambient grading: no raw/slope work, so it
## is safe to call a few times per second for underwater fog and tint.
func biome_id_at(world_x: int, world_z: int) -> int:
	_ensure_configured()
	return _sampler.sample_decoration_ground(world_x, world_z).y


## Water grading color for a biome; matches the water mesh's vertex tint.
func water_tint_for(biome_id: int) -> Color:
	_ensure_configured()
	return _biomes.water_tint(biome_id)


## Deterministic underground-region lookup shared by population and the
## throttled camera ambience query. The caller decides whether the voxel is
## actually inside a cave before applying this 3D region label.
func cave_biome_id_at(world_x: int, y: int, world_z: int) -> int:
	_ensure_configured()
	return BiomeCatalog.cave_biome_at(_config.seed, world_x, y, world_z)


func biome_color(biome_id: int) -> Color:
	_ensure_configured()
	match biome_id:
		BiomeCatalog.OCEAN:
			return Color("#356f9d")
		BiomeCatalog.DEEP_OCEAN:
			return Color("#183f70")
		BiomeCatalog.KELP_FOREST:
			return Color("#2e6b4f")
		BiomeCatalog.SEAGRASS_MEADOW:
			return Color("#6dbf7a")
		BiomeCatalog.CORAL_REEF:
			return Color("#e0709a")
		BiomeCatalog.FROZEN_OCEAN:
			return Color("#cfeef5")
		BiomeCatalog.BEACH:
			return Color("#d8c884")
		BiomeCatalog.RIVER:
			return Color("#4d8db5")
		BiomeCatalog.DESERT:
			return Color("#dec978")
		BiomeCatalog.SNOW:
			return Color("#e8f1f2")
		BiomeCatalog.SWAMP:
			return Color("#536b3b")
		BiomeCatalog.BADLANDS:
			return Color("#b7633f")
		BiomeCatalog.HIGHLANDS:
			return Color("#7d8580")
		_:
			return _biomes.foliage_color(biome_id)


func config_dictionary() -> Dictionary:
	_ensure_configured()
	return _config.to_dictionary()


## Worker-safe diagnostic raster. Image creation remains on the main thread;
## this method only returns packed colors and scalar metadata.
func build_debug_map(mode: String, center: Vector2i, size: int, stride: int) -> Dictionary:
	_ensure_configured()
	var safe_size := clampi(size, 16, 128)
	var safe_stride := clampi(stride, 1, 32)
	var pixels := PackedColorArray()
	pixels.resize(safe_size * safe_size)
	var origin := center - Vector2i(safe_size * safe_stride / 2, safe_size * safe_stride / 2)
	for map_z in safe_size:
		var world_z := origin.y + map_z * safe_stride
		for map_x in safe_size:
			var world_x := origin.x + map_x * safe_stride
			var sample: Dictionary = _sampler.sample_debug_point(mode, world_x, world_z)
			pixels[map_x + map_z * safe_size] = _debug_color(mode, sample)
	return {
		"pixels": pixels,
		"width": safe_size,
		"height": safe_size,
		"center": center,
		"stride": safe_stride,
	}


func _debug_color(mode: String, sample: Dictionary) -> Color:
	match mode:
		"biome":
			return biome_color(int(sample["dominant_biome_id"]))
		"height":
			var height := float(sample["final_height"])
			if height < VoxelDefs.SEA_LEVEL:
				return Color("#173b66").lerp(Color("#397caf"), height / float(VoxelDefs.SEA_LEVEL))
			return Color("#344734").lerp(Color("#f0eee5"), clampf((height - VoxelDefs.SEA_LEVEL) / 100.0, 0.0, 1.0))
		"raw_height":
			var raw_height := clampf(float(sample["raw_height"]) / float(VoxelDefs.WORLD_HEIGHT), 0.0, 1.0)
			return Color(raw_height, raw_height, raw_height)
		"slope":
			var slope := clampf(float(sample["slope"]) / 8.0, 0.0, 1.0)
			return Color("#101719").lerp(Color("#e7e5dc"), slope)
		"temperature":
			return Color("#5d8fc7").lerp(Color("#e2a04f"), float(sample["temperature"]))
		"moisture":
			return Color("#c6ad68").lerp(Color("#4c91a8"), float(sample["moisture"]))
		"continentalness":
			var value := float(sample["continentalness"])
			return Color("#183c70").lerp(Color("#e4dfbd"), value)
		"river":
			return Color("#182126").lerp(Color("#54bde8"), float(sample["river"]))
		"profile":
			var profile_id := int(sample["profile_id"])
			var profile_colors := [Color("#6fa653"), Color("#87a657"), Color("#9b8b58"), Color("#85837d"), Color("#d8d9d5")]
			return profile_colors[clampi(profile_id, 0, profile_colors.size() - 1)]
	return Color.MAGENTA


## Searches coarse-to-fine for temperate land, avoiding potentially long scans
## across an origin ocean while keeping the result deterministic per seed.
func find_spawn_position() -> Vector3:
	_ensure_configured()
	var best := Vector3(0.5, float(VoxelDefs.SEA_LEVEL + 16), 0.5)
	var best_score := -INF
	for radius in range(0, 65):
		for edge in range(-radius, radius + 1):
			var candidates := [Vector2i(edge, -radius), Vector2i(edge, radius)]
			if edge != -radius and edge != radius:
				candidates.append(Vector2i(-radius, edge))
				candidates.append(Vector2i(radius, edge))
			for coarse: Vector2i in candidates:
				var point := coarse * 8
				var sample: Dictionary = _sampler.sample_point(point.x, point.y)
				var biome: int = int(sample["dominant_biome_id"])
				var height: float = float(sample["final_height"])
				if _biomes.is_ocean_biome(biome) or biome in [BiomeCatalog.BEACH, BiomeCatalog.RIVER, BiomeCatalog.SWAMP]:
					continue
				var slope: float = float(sample["slope"])
				var score := height - slope * 8.0 - float(radius) * 0.12
				if height > VoxelDefs.SEA_LEVEL + 2 and slope < 2.2 and score > best_score:
					best_score = score
					best = Vector3(float(point.x) + 0.5, height + 2.5, float(point.y) + 0.5)
					if radius >= 2:
						return best
	return best


func _build_heights(data: PackedByteArray, max_y: int) -> PackedInt32Array:
	var heights := PackedInt32Array()
	heights.resize(VoxelDefs.CHUNK_AREA)
	heights.fill(-1)
	for local_z in VoxelDefs.CHUNK_SIZE:
		for local_x in VoxelDefs.CHUNK_SIZE:
			var column := local_x + local_z * VoxelDefs.DATA_STRIDE_Z
			for y in range(max_y, -1, -1):
				if data[column + y * VoxelDefs.DATA_STRIDE_Y] != BlockRegistry.BLOCK_AIR:
					heights[column] = y
					break
	return heights


func _build_lod_heights(solid_y: PackedInt32Array, water_y: PackedInt32Array) -> PackedInt32Array:
	var heights := PackedInt32Array()
	heights.resize(VoxelDefs.CHUNK_AREA)
	for column in heights.size():
		heights[column] = maxi(solid_y[column], water_y[column])
	return heights


func _ensure_configured() -> void:
	if _sampler == null:
		configure({})
