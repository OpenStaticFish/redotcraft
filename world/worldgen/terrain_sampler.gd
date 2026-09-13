## Immutable, worker-safe terrain field sampler.
## Construct and configure on the main thread, then share read-only instances with
## chunk jobs. build_field uses only packed arrays in its cell loops and seals its
## result before returning it.
class_name TerrainSampler
extends RefCounted

const VoxelDefsScript = preload("res://world/voxel_defs.gd")
const HydraulicErosionScript = preload("res://world/worldgen/hydraulic_erosion.gd")

const CHANNEL_CONTINENT: int = 0
const CHANNEL_WARP_X: int = 1
const CHANNEL_WARP_Z: int = 2
const CHANNEL_LANDFORM: int = 3
const CHANNEL_RIDGE: int = 4
const CHANNEL_DETAIL: int = 5
const CHANNEL_RIVER: int = 6
const CHANNEL_TEMPERATURE: int = 7
const CHANNEL_MOISTURE: int = 8
const CHANNEL_COUNT: int = 9

const MIN_TERRAIN_HEIGHT: float = 3.0
const HEIGHT_MARGIN: float = 8.0
# build_field has four successively smaller grids. Float64 packed arrays retain
# point-query precision while making every coordinate's neighbourhood independent
# of which chunk is being generated.
const FIELD_MIN: int = -ChunkTerrainData.PADDING
const FIELD_MAX: int = VoxelDefsScript.CHUNK_SIZE + ChunkTerrainData.PADDING - 1
const FINAL_MIN: int = FIELD_MIN - 1
const FINAL_MAX: int = FIELD_MAX + 1
const RAW_MIN: int = FINAL_MIN - 1
const RAW_MAX: int = FINAL_MAX + 1
const SOURCE_MIN: int = RAW_MIN - RegionalErosion.SAMPLE_RADIUS
const SOURCE_MAX: int = RAW_MAX + RegionalErosion.SAMPLE_RADIUS
const SOURCE_SIDE: int = SOURCE_MAX - SOURCE_MIN + 1
const RAW_SIDE: int = RAW_MAX - RAW_MIN + 1
const FINAL_SIDE: int = FINAL_MAX - FINAL_MIN + 1
const CLIMATE_BIOMES := [
	BiomeCatalog.PLAINS, BiomeCatalog.FOREST, BiomeCatalog.DESERT,
	BiomeCatalog.SNOW, BiomeCatalog.SWAMP, BiomeCatalog.JUNGLE,
	BiomeCatalog.SAVANNA, BiomeCatalog.TAIGA, BiomeCatalog.BADLANDS,
	BiomeCatalog.MEADOW,
]

var _config: WorldGenConfig
var _profiles: PackedFloat32Array = PackedFloat32Array()
var _biome_temperatures: PackedFloat32Array = PackedFloat32Array()
var _biome_moistures: PackedFloat32Array = PackedFloat32Array()
var _noises: Array[FastNoiseLite] = []
var _regional_erosion: RegionalErosion
var _erosion_height_source: Callable
var _hydraulic_erosion: Variant = null
var _hydraulic_height_source: Callable
var _configured: bool = false


func _init(config: WorldGenConfig = null, profiles: TerrainProfileCatalog = null, biomes: BiomeCatalog = null) -> void:
	if config != null:
		configure(config, profiles, biomes)


## Configures exactly once. Inputs are copied so outside mutation cannot affect a
## live sampler. Catalog defaults are used when optional catalogs are omitted.
func configure(config: WorldGenConfig, profiles: TerrainProfileCatalog = null, biomes: BiomeCatalog = null) -> void:
	if _configured:
		push_warning("TerrainSampler is immutable after initialization")
		return
	_config = WorldGenConfig.new(config.to_dictionary())
	var profile_catalog: TerrainProfileCatalog = profiles if profiles != null else TerrainProfileCatalog.new()
	var biome_catalog: BiomeCatalog = biomes if biomes != null else BiomeCatalog.new()
	_copy_catalogs(profile_catalog, biome_catalog)
	_noises = _make_noise_channels()
	_regional_erosion = RegionalErosion.new(_config)
	_erosion_height_source = Callable(self, "_height_without_regional_erosion")
	# Do not allocate a cache or add hydraulic sampling work to the default path.
	if _config.hydraulic_erosion:
		_hydraulic_erosion = HydraulicErosionScript.new(_config)
		_hydraulic_height_source = Callable(self, "_height_without_regional_erosion")
	_configured = true


## Creates the 18x18 (16x16 plus one-cell border) structure-of-arrays field.
##
## Regional erosion needs a radius-four source neighbourhood. Talus/terracing
## then needs a raw-height ring, and slope needs a final-height ring. Evaluating
## those three expanded, packed grids once avoids the old nested point sampling
## and makes a coordinate produce the same result from every adjacent chunk.
func build_field(chunk_pos: Vector2i) -> ChunkTerrainData:
	_ensure_configured()
	var field := ChunkTerrainData.new(chunk_pos.x, chunk_pos.y)
	var origin_x: int = chunk_pos.x * VoxelDefsScript.CHUNK_SIZE
	var origin_z: int = chunk_pos.y * VoxelDefsScript.CHUNK_SIZE

	var source_height := PackedFloat64Array()
	var source_continental := PackedFloat64Array()
	var source_base := PackedFloat64Array()
	var source_river := PackedFloat64Array()
	var source_profile := PackedFloat64Array()
	var source_count: int = SOURCE_SIDE * SOURCE_SIDE
	source_height.resize(source_count)
	source_continental.resize(source_count)
	source_base.resize(source_count)
	source_river.resize(source_count)
	source_profile.resize(source_count)
	for local_z in range(SOURCE_MIN, SOURCE_MAX + 1):
		var world_z: int = origin_z + local_z
		var row: int = (local_z - SOURCE_MIN) * SOURCE_SIDE
		for local_x in range(SOURCE_MIN, SOURCE_MAX + 1):
			var world_x: int = origin_x + local_x
			var source_index: int = row + local_x - SOURCE_MIN
			var continental: float = _continentalness_at(world_x, world_z)
			var base: float = _base_height_at(world_x, world_z, continental)
			var profile_position: float = _profile_position_at(world_x, world_z, continental)
			var river_value: float = _river_at(world_x, world_z, continental)
			source_continental[source_index] = continental
			source_profile[source_index] = profile_position
			source_base[source_index] = base
			source_river[source_index] = river_value
			source_height[source_index] = _height_without_regional_erosion_from_samples(
				world_x, world_z, continental, base, profile_position, river_value)

	var raw_height := PackedFloat64Array()
	raw_height.resize(RAW_SIDE * RAW_SIDE)
	for local_z in range(RAW_MIN, RAW_MAX + 1):
		var world_z: int = origin_z + local_z
		var raw_row: int = (local_z - RAW_MIN) * RAW_SIDE
		var source_row: int = (local_z - SOURCE_MIN) * SOURCE_SIDE
		for local_x in range(RAW_MIN, RAW_MAX + 1):
			var world_x: int = origin_x + local_x
			var raw_index: int = raw_row + local_x - RAW_MIN
			var source_index: int = source_row + local_x - SOURCE_MIN
			var raw_value: float = source_height[source_index]
			if _config.world_type != WorldGenConfig.WORLD_TYPE_FLAT:
				raw_value += _regional_erosion.modifier_from_samples(
					world_x, world_z, raw_value,
					source_height[source_index - RegionalErosion.SAMPLE_RADIUS],
					source_height[source_index + RegionalErosion.SAMPLE_RADIUS],
					source_height[source_index - RegionalErosion.SAMPLE_RADIUS * SOURCE_SIDE],
					source_height[source_index + RegionalErosion.SAMPLE_RADIUS * SOURCE_SIDE],
					source_height[source_index - RegionalErosion.FLOW_SAMPLE_DISTANCE],
					source_height[source_index + RegionalErosion.FLOW_SAMPLE_DISTANCE],
					source_height[source_index - RegionalErosion.FLOW_SAMPLE_DISTANCE * SOURCE_SIDE],
					source_height[source_index + RegionalErosion.FLOW_SAMPLE_DISTANCE * SOURCE_SIDE])
				if _hydraulic_erosion != null:
					raw_value += _hydraulic_erosion.modifier(world_x, world_z, _hydraulic_height_source)
			raw_height[raw_index] = clampf(raw_value, MIN_TERRAIN_HEIGHT, float(VoxelDefsScript.WORLD_HEIGHT) - HEIGHT_MARGIN)

	var final_height := PackedFloat64Array()
	final_height.resize(FINAL_SIDE * FINAL_SIDE)
	for local_z in range(FINAL_MIN, FINAL_MAX + 1):
		var world_z: int = origin_z + local_z
		var final_row: int = (local_z - FINAL_MIN) * FINAL_SIDE
		var raw_row: int = (local_z - RAW_MIN) * RAW_SIDE
		for local_x in range(FINAL_MIN, FINAL_MAX + 1):
			var raw_index: int = raw_row + local_x - RAW_MIN
			final_height[final_row + local_x - FINAL_MIN] = _final_from_raw_neighborhood(
				origin_x + local_x, world_z, raw_height[raw_index],
				raw_height[raw_index - 1], raw_height[raw_index + 1],
				raw_height[raw_index - RAW_SIDE], raw_height[raw_index + RAW_SIDE])
	var final_temperature := PackedFloat64Array()
	var final_moisture := PackedFloat64Array()
	final_temperature.resize(FINAL_SIDE * FINAL_SIDE)
	final_moisture.resize(FINAL_SIDE * FINAL_SIDE)
	for local_z in range(FINAL_MIN, FINAL_MAX + 1):
		var world_z: int = origin_z + local_z
		var final_row: int = (local_z - FINAL_MIN) * FINAL_SIDE
		var raw_row: int = (local_z - RAW_MIN) * RAW_SIDE
		var source_row: int = (local_z - SOURCE_MIN) * SOURCE_SIDE
		for local_x in range(FINAL_MIN, FINAL_MAX + 1):
			var world_x := origin_x + local_x
			var final_index := final_row + local_x - FINAL_MIN
			var raw_index := raw_row + local_x - RAW_MIN
			var source_index := source_row + local_x - SOURCE_MIN
			var height := final_height[final_index]
			var climate := _climate_at(world_x, world_z, height, source_river[source_index])
			var temperature_value := climate.x
			var moisture_value := climate.y
			var climate_altitude := maxf(height - float(VoxelDefsScript.SEA_LEVEL), 0.0)
			var west := raw_height[raw_index - 1]
			var east := raw_height[raw_index + 1]
			var north := raw_height[raw_index - RAW_SIDE]
			var south := raw_height[raw_index + RAW_SIDE]
			var gradient := sqrt((east - west) * (east - west) + (south - north) * (south - north)) * 0.5
			var local_relief := absf(raw_height[raw_index] - (west + east + north + south) * 0.25)
			final_height[final_index] = _apply_climate_terrain_shape(
				height, source_profile[source_index], gradient, local_relief,
				temperature_value + climate_altitude * 0.0035,
				moisture_value + climate_altitude * 0.0015)
			# Point queries and chunk fields must classify the same final height.
			climate = _climate_at(world_x, world_z, final_height[final_index], source_river[source_index])
			final_temperature[final_index] = climate.x
			final_moisture[final_index] = climate.y

	# Copy the requested 18x18 field from the expanded grids and derive its climate.
	for local_z in range(FIELD_MIN, FIELD_MAX + 1):
		var world_z: int = origin_z + local_z
		var field_row: int = (local_z - FIELD_MIN) * ChunkTerrainData.SIDE
		var source_row: int = (local_z - SOURCE_MIN) * SOURCE_SIDE
		var raw_row: int = (local_z - RAW_MIN) * RAW_SIDE
		var final_row: int = (local_z - FINAL_MIN) * FINAL_SIDE
		for local_x in range(FIELD_MIN, FIELD_MAX + 1):
			var field_index: int = field_row + local_x - FIELD_MIN
			var source_index: int = source_row + local_x - SOURCE_MIN
			var raw_index: int = raw_row + local_x - RAW_MIN
			var final_index: int = final_row + local_x - FINAL_MIN
			var final_value: float = final_height[final_index]
			var west: float = final_height[final_index - 1]
			var east: float = final_height[final_index + 1]
			var north: float = final_height[final_index - FINAL_SIDE]
			var south: float = final_height[final_index + FINAL_SIDE]
			var slope_value: float = sqrt((east - west) * (east - west) + (south - north) * (south - north)) * 0.5
			var river_value: float = source_river[source_index]
			var temperature_value: float = final_temperature[final_index]
			var moisture_value: float = final_moisture[final_index]
			var biome_choice := _biome_choice(temperature_value, moisture_value)
			var profile_position: float = source_profile[source_index]
			var profile: int = clampi(floori(profile_position), TerrainProfileCatalog.PLAINS, TerrainProfileCatalog.RIDGED_MOUNTAINS)
			var profile_fraction: float = profile_position - floorf(profile_position)
			if profile == TerrainProfileCatalog.RIDGED_MOUNTAINS:
				profile_fraction = 0.0
			var continental: float = source_continental[source_index]
			var biome: int = _apply_biome_override(biome_choice.x, continental, final_value, river_value, profile)
			var secondary: int = biome_choice.y if biome == biome_choice.x else biome
			var biome_blend_value: int = biome_choice.z if biome == biome_choice.x else 0
			var dominant := biome
			field.continentalness[field_index] = continental
			field.raw_height[field_index] = raw_height[raw_index]
			field.base_height[field_index] = source_base[source_index]
			field.final_height[field_index] = final_value
			field.slope[field_index] = slope_value
			field.river[field_index] = river_value
			field.temperature[field_index] = temperature_value
			field.moisture[field_index] = moisture_value
			field.profile_id[field_index] = profile
			field.profile_blend[field_index] = roundi(profile_fraction * 255.0)
			field.biome_id[field_index] = biome
			field.biome_secondary_id[field_index] = secondary
			field.biome_blend[field_index] = biome_blend_value
			field.dominant_biome[field_index] = dominant
	field.seal()
	return field


## Diagnostic-friendly point query. Unlike build_field, this deliberately returns
## a Dictionary and may be used by tools, previews, or spawn inspection.
func sample_point(x: int, z: int) -> Dictionary:
	_ensure_configured()
	var continental: float = _continentalness_at(x, z)
	var base: float = _base_height_at(x, z, continental)
	var raw: float = _raw_height_at(x, z)
	var final_value: float = _final_height_at(x, z)
	var river_value: float = _river_at(x, z, continental)
	var climate := _climate_at(x, z, final_value, river_value)
	var temperature_value: float = climate.x
	var moisture_value: float = climate.y
	var profile_position: float = _profile_position_at(x, z, continental)
	var profile: int = clampi(floori(profile_position), TerrainProfileCatalog.PLAINS, TerrainProfileCatalog.RIDGED_MOUNTAINS)
	var choice := _biome_choice(temperature_value, moisture_value)
	var biome: int = _apply_biome_override(choice.x, continental, final_value, river_value, profile)
	var secondary: int = choice.y if biome == choice.x else biome
	var blend: int = choice.z if biome == choice.x else 0
	var dominant := biome
	return {
		"continentalness": continental,
		"base_height": base,
		"raw_height": raw,
		"final_height": final_value,
		"slope": _slope_at(x, z),
		"river": river_value,
		"temperature": temperature_value,
		"moisture": moisture_value,
		"profile_id": profile,
		"profile_blend": profile_position - floorf(profile_position),
		"biome_id": biome,
		"biome_secondary_id": secondary,
		"biome_blend": blend / 255.0,
		"dominant_biome_id": dominant,
	}


## Exact compact query for cross-chunk feature origins. Decorations only need
## surface Y and the dominant biome, so avoid sample_point's raw/slope work and
## Dictionary allocation in the hot population path.
func sample_decoration_ground(x: int, z: int) -> Vector2i:
	_ensure_configured()
	var continental := _continentalness_at(x, z)
	var final_value := _final_height_at(x, z)
	var river_value := _river_at(x, z, continental)
	var climate := _climate_at(x, z, final_value, river_value)
	var profile_position := _profile_position_at(x, z, continental)
	var profile := clampi(floori(profile_position), TerrainProfileCatalog.PLAINS, TerrainProfileCatalog.RIDGED_MOUNTAINS)
	var choice := _biome_choice(climate.x, climate.y)
	var biome := _apply_biome_override(choice.x, continental, final_value, river_value, profile)
	var dominant := biome
	return Vector2i(clampi(roundi(final_value), 2, VoxelDefsScript.WORLD_HEIGHT - 2), dominant)


## Lightweight regional-map query. At the overlay's coarse 32-block stride,
## resolving the full radius-four erosion and final slope graph for every pixel
## adds seconds without changing the useful macro view. This keeps the exact
## continent/profile/river/climate fields and uses the pre-erosion profile
## height; chunk generation and gameplay always use build_field() instead.
func sample_debug_point(mode: String, x: int, z: int) -> Dictionary:
	_ensure_configured()
	var continental := _continentalness_at(x, z)
	if mode == "continentalness":
		return {"continentalness": continental}
	var river_value := _river_at(x, z, continental)
	if mode == "river":
		return {"river": river_value}
	if mode == "raw_height":
		return {"raw_height": _raw_height_at(x, z)}
	var height := _height_without_regional_erosion(x, z)
	if mode == "height":
		return {"final_height": _final_height_at(x, z)}
	if mode == "slope":
		var dx := _height_without_regional_erosion(x + 1, z) - _height_without_regional_erosion(x - 1, z)
		var dz := _height_without_regional_erosion(x, z + 1) - _height_without_regional_erosion(x, z - 1)
		return {"slope": sqrt(dx * dx + dz * dz) * 0.5}
	var climate := _climate_at(x, z, height, river_value)
	if mode == "temperature":
		return {"temperature": climate.x}
	if mode == "moisture":
		return {"moisture": climate.y}
	var choice := _biome_choice(climate.x, climate.y)
	var profile_position := _profile_position_at(x, z, continental)
	var profile := clampi(floori(profile_position), TerrainProfileCatalog.PLAINS, TerrainProfileCatalog.RIDGED_MOUNTAINS)
	if mode == "profile":
		return {"profile_id": profile}
	var biome := _apply_biome_override(choice.x, continental, height, river_value, profile)
	var dominant := biome
	return {"dominant_biome_id": dominant}


func _copy_catalogs(profiles: TerrainProfileCatalog, biomes: BiomeCatalog) -> void:
	_profiles.resize((TerrainProfileCatalog.RIDGED_MOUNTAINS + 1) * TerrainProfileCatalog.FIELD_COUNT)
	for profile in range(TerrainProfileCatalog.RIDGED_MOUNTAINS + 1):
		for field in range(TerrainProfileCatalog.FIELD_COUNT):
			_profiles[profile * TerrainProfileCatalog.FIELD_COUNT + field] = profiles.value(profile, field)
	_biome_temperatures.resize(CLIMATE_BIOMES.size())
	_biome_moistures.resize(CLIMATE_BIOMES.size())
	for index in CLIMATE_BIOMES.size():
		var biome: int = CLIMATE_BIOMES[index]
		_biome_temperatures[index] = biomes.temperature_center(biome)
		_biome_moistures[index] = biomes.moisture_center(biome)


func _make_noise_channels() -> Array[FastNoiseLite]:
	var definitions: Array = [
		[FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 1.0, 2, 101],
		[FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 1.0, 2, 211],
		[FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 1.0, 2, 307],
		[FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 1.0, 2, 401],
		[FastNoiseLite.TYPE_SIMPLEX, 1.0, 2, 503],
		[FastNoiseLite.TYPE_SIMPLEX, 1.0, 3, 601],
		[FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 1.0, 2, 701],
		[FastNoiseLite.TYPE_PERLIN, 1.0, 2, 809],
		[FastNoiseLite.TYPE_PERLIN, 1.0, 2, 907],
	]
	var result: Array[FastNoiseLite] = []
	for definition in definitions:
		var noise := FastNoiseLite.new()
		noise.noise_type = definition[0]
		noise.frequency = definition[1]
		noise.fractal_octaves = definition[2]
		noise.fractal_lacunarity = 2.0
		noise.fractal_gain = 0.5
		noise.seed = WorldGenHash.hash_1d(_config.seed, definition[3])
		result.append(noise)
	return result


func _continentalness_at(x: int, z: int) -> float:
	if _config.world_type == WorldGenConfig.WORLD_TYPE_FLAT:
		return 1.0
	var warped := _macro_warp(x, z)
	var noise_value: float = _noises[CHANNEL_CONTINENT].get_noise_2d(
		warped.x / _config.macro_scale, warped.y / _config.macro_scale)
	return _smoothstep(-0.42, 0.40, noise_value)


func _base_height_at(x: int, z: int, continental: float) -> float:
	if _config.world_type == WorldGenConfig.WORLD_TYPE_FLAT:
		return float(VoxelDefsScript.SEA_LEVEL) + 2.0
	var profile_position: float = _profile_position_at(x, z, continental)
	var profile: int = clampi(floori(profile_position), 0, TerrainProfileCatalog.RIDGED_MOUNTAINS)
	var next_profile: int = mini(profile + 1, TerrainProfileCatalog.RIDGED_MOUNTAINS)
	var blend: float = profile_position - floorf(profile_position)
	var profile_base: float = lerpf(_profile_value(profile, TerrainProfileCatalog.FIELD_BASE_HEIGHT), _profile_value(next_profile, TerrainProfileCatalog.FIELD_BASE_HEIGHT), blend)
	var shoreline: float = _smoothstep(0.27, 0.52, continental)
	var ocean_floor: float = lerpf(float(VoxelDefsScript.SEA_LEVEL) - 17.0, float(VoxelDefsScript.SEA_LEVEL) - 2.5, _smoothstep(0.05, 0.36, continental))
	return lerpf(ocean_floor, profile_base, shoreline)


func _height_without_regional_erosion(x: int, z: int) -> float:
	var continental: float = _continentalness_at(x, z)
	var base: float = _base_height_at(x, z, continental)
	if _config.world_type == WorldGenConfig.WORLD_TYPE_FLAT:
		return base
	var profile_position: float = _profile_position_at(x, z, continental)
	var river_value: float = _river_at(x, z, continental)
	return _height_without_regional_erosion_from_samples(x, z, continental, base, profile_position, river_value)


## Computes the expensive, no-regional source height from values cached in the
## expanded grid. All arguments are scalar so point queries retain their API and
## exact coordinate behaviour.
func _height_without_regional_erosion_from_samples(
		x: int,
		z: int,
		continental: float,
		base: float,
		profile_position: float,
		river_value: float) -> float:
	if _config.world_type == WorldGenConfig.WORLD_TYPE_FLAT:
		return base
	var profile: int = clampi(floori(profile_position), 0, TerrainProfileCatalog.RIDGED_MOUNTAINS)
	var next_profile: int = mini(profile + 1, TerrainProfileCatalog.RIDGED_MOUNTAINS)
	var profile_blend: float = profile_position - floorf(profile_position)
	var warped := _macro_warp(x, z)
	var detail_frequency: float = _profile_value(profile, TerrainProfileCatalog.FIELD_DETAIL_FREQUENCY)
	var next_frequency: float = _profile_value(next_profile, TerrainProfileCatalog.FIELD_DETAIL_FREQUENCY)
	var detail_strength: float = lerpf(_profile_value(profile, TerrainProfileCatalog.FIELD_DETAIL_STRENGTH), _profile_value(next_profile, TerrainProfileCatalog.FIELD_DETAIL_STRENGTH), profile_blend)
	var relief: float = lerpf(_profile_value(profile, TerrainProfileCatalog.FIELD_RELIEF), _profile_value(next_profile, TerrainProfileCatalog.FIELD_RELIEF), profile_blend)
	var ridge_weight: float = lerpf(_profile_value(profile, TerrainProfileCatalog.FIELD_RIDGE_WEIGHT), _profile_value(next_profile, TerrainProfileCatalog.FIELD_RIDGE_WEIGHT), profile_blend)
	# Blend sampled values, not frequencies multiplied by world coordinates.
	# The latter compresses/stretchs noise increasingly far from the origin.
	var detail: float = lerpf(
		_noises[CHANNEL_DETAIL].get_noise_2d(float(x) * detail_frequency, float(z) * detail_frequency),
		_noises[CHANNEL_DETAIL].get_noise_2d(float(x) * next_frequency, float(z) * next_frequency),
		profile_blend) * detail_strength
	var ridge: float = 1.0 - absf(_noises[CHANNEL_RIDGE].get_noise_2d(
		warped.x / (_config.macro_scale * 0.65), warped.y / (_config.macro_scale * 0.65)))
	var land: float = _smoothstep(0.33, 0.52, continental)
	var relief_scale: float = _config.terrain_scale
	if _config.world_type == WorldGenConfig.WORLD_TYPE_AMPLIFIED:
		relief_scale *= 1.85
	var height: float = base + (detail + relief * ridge * ridge * ridge_weight) * land * relief_scale
	# Keep regional relief separate from small landforms. Fade these additions
	# at coasts; river carving below still owns the channel floor and waterline.
	height += _local_landform_detail(warped, profile, next_profile, profile_blend) \
		* _smoothstep(0.43, 0.60, continental) * relief_scale
	if river_value > 0.0:
		# A sea-connected lowland channel, not a knife cut through every peak.
		# Fade the carve before uplands and fill to one common water level later.
		var lowland: float = 1.0 - _smoothstep(float(VoxelDefsScript.SEA_LEVEL + 8), float(VoxelDefsScript.SEA_LEVEL + 24), height)
		height = lerpf(height, minf(height, float(VoxelDefsScript.SEA_LEVEL - 2)), river_value * lowland)
	return height


## Bounded, fixed-wavelength detail: shoulders/knolls, shallow tributary gullies,
## and small surface undulations. No profile selection, coordinate-dependent
## frequency, or per-column random height is involved, so this cannot turn a
## plain into a mountain or become rougher farther from the origin.
func _local_landform_detail(warped: Vector2, profile: int, next_profile: int, blend: float) -> float:
	var strength := lerpf(
		_profile_value(profile, TerrainProfileCatalog.FIELD_LOCAL_RELIEF),
		_profile_value(next_profile, TerrainProfileCatalog.FIELD_LOCAL_RELIEF), blend)
	var fine_strength := lerpf(
		_profile_value(profile, TerrainProfileCatalog.FIELD_SURFACE_DETAIL),
		_profile_value(next_profile, TerrainProfileCatalog.FIELD_SURFACE_DETAIL), blend)
	# Broader shoulders carry most of the local relief so land rolls instead of
	# stepping; knolls stay as a small secondary accent at a longer wavelength.
	var shoulders := _noises[CHANNEL_DETAIL].get_noise_2d(
		(warped.x + 173.0) / 80.0, (warped.y - 291.0) / 80.0)
	var knolls := _noises[CHANNEL_DETAIL].get_noise_2d(
		(warped.x - 419.0) / 32.0, (warped.y + 137.0) / 32.0)
	var gully_noise := absf(_noises[CHANNEL_RIDGE].get_noise_2d(
		(warped.x + 631.0) / 52.0, (warped.y + 853.0) / 52.0))
	var gullies := 1.0 - _smoothstep(0.03, 0.32, gully_noise)
	var upland := _smoothstep(0.7, 3.0, float(profile) + blend)
	var fine := _noises[CHANNEL_DETAIL].get_noise_2d(
		(warped.x - 967.0) / 13.0, (warped.y - 541.0) / 13.0)
	return strength * (shoulders * 0.85 + knolls * 0.15 - gullies * upland * 0.18) + fine * fine_strength


## Climate modifies profile output with smooth weights rather than replacing it:
## wetlands settle into basins, dry regions gain dunes/terraces, tropical land
## rolls more strongly, and cold mountain ridges retain sharper peaks.
func _apply_climate_terrain_shape(height: float, profile_position: float, gradient: float, local_relief: float, temperature: float, moisture: float) -> float:
	if _config.world_type == WorldGenConfig.WORLD_TYPE_FLAT:
		return height
	var lowland := 1.0 - _smoothstep(1.6, 2.8, profile_position)
	var wetland_weight := _smoothstep(0.32, 0.42, temperature) \
		* (1.0 - _smoothstep(0.68, 0.76, temperature)) \
		* _smoothstep(0.64, 0.72, moisture) * lowland
	var basin_height := minf(height, float(VoxelDefsScript.SEA_LEVEL) + 3.0)
	height = lerpf(height, basin_height, wetland_weight * 0.86)
	var dry_weight := _smoothstep(0.66, 0.82, temperature) * (1.0 - _smoothstep(0.25, 0.48, moisture))
	var dune := minf(local_relief * 1.8 + gradient * 0.22, 3.2)
	height += dune * dry_weight * lowland
	var badland_band := maxf(1.0 - absf(moisture - 0.31) / 0.14, 0.0) * _smoothstep(0.70, 0.84, temperature)
	var terraced := floorf(height / 3.0 + 0.5) * 3.0
	height = lerpf(height, terraced, badland_band * 0.48)
	var tropical_weight := _smoothstep(0.66, 0.80, temperature) * _smoothstep(0.68, 0.84, moisture)
	height += 2.0 * tropical_weight * _smoothstep(0.6, 2.0, profile_position)
	var cold_weight := 1.0 - _smoothstep(0.18, 0.36, temperature)
	height += 3.0 * cold_weight * _smoothstep(2.2, 3.8, profile_position)
	return clampf(height, MIN_TERRAIN_HEIGHT, float(VoxelDefsScript.WORLD_HEIGHT) - HEIGHT_MARGIN)


func _raw_height_at(x: int, z: int) -> float:
	var height: float = _height_with_regional_erosion(x, z)
	if _hydraulic_erosion != null and _config.world_type != WorldGenConfig.WORLD_TYPE_FLAT:
		height += _hydraulic_erosion.modifier(x, z, _hydraulic_height_source)
	return clampf(height, MIN_TERRAIN_HEIGHT, float(VoxelDefsScript.WORLD_HEIGHT) - HEIGHT_MARGIN)


## The analytic regional modifier remains the seam-safe foundation; the optional
## tile solve adds its delta afterwards and uses the unmodified analytic source.
func _height_with_regional_erosion(x: int, z: int) -> float:
	var height: float = _height_without_regional_erosion(x, z)
	if _config.world_type != WorldGenConfig.WORLD_TYPE_FLAT:
		height += _regional_erosion.modifier(x, z, _erosion_height_source)
	return clampf(height, MIN_TERRAIN_HEIGHT, float(VoxelDefsScript.WORLD_HEIGHT) - HEIGHT_MARGIN)


func _final_height_at(x: int, z: int) -> float:
	var raw: float = _raw_height_at(x, z)
	if _config.world_type == WorldGenConfig.WORLD_TYPE_FLAT:
		return raw
	var west: float = _raw_height_at(x - 1, z)
	var east: float = _raw_height_at(x + 1, z)
	var north: float = _raw_height_at(x, z - 1)
	var south: float = _raw_height_at(x, z + 1)
	var height := _final_from_raw_neighborhood(x, z, raw, west, east, north, south)
	var gradient := sqrt((east - west) * (east - west) + (south - north) * (south - north)) * 0.5
	var local_relief := absf(raw - (west + east + north + south) * 0.25)
	var continental := _continentalness_at(x, z)
	var river_value := _river_at(x, z, continental)
	var climate := _climate_at(x, z, height, river_value)
	var climate_altitude := maxf(height - float(VoxelDefsScript.SEA_LEVEL), 0.0)
	return _apply_climate_terrain_shape(
		height, _profile_position_at(x, z, continental), gradient, local_relief,
		climate.x + climate_altitude * 0.0035,
		climate.y + climate_altitude * 0.0015)


func _final_from_raw_neighborhood(x: int, z: int, raw: float, west: float, east: float, north: float, south: float) -> float:
	if _config.world_type == WorldGenConfig.WORLD_TYPE_FLAT:
		return raw
	var gradient: float = sqrt((east - west) * (east - west) + (south - north) * (south - north)) * 0.5
	var mean: float = (west + east + north + south) * 0.25
	var talus_weight: float = _smoothstep(0.6, 5.5, gradient) * _config.erosion_strength
	var talus: float = lerpf(raw, mean, talus_weight * 0.33)
	var continental: float = _continentalness_at(x, z)
	var profile_position: float = _profile_position_at(x, z, continental)
	# Terracing belongs on plateaus, not every hillside and mountain flank.
	var terrace_weight: float = maxf(1.0 - absf(profile_position - 2.0) * 2.0, 0.0) * _smoothstep(0.2, 2.0, gradient) * _config.erosion_strength
	var step: float = 2.0 + profile_position * 0.25
	var terraced: float = floorf(talus / step + 0.5) * step
	return clampf(lerpf(talus, terraced, terrace_weight * 0.22), MIN_TERRAIN_HEIGHT, float(VoxelDefsScript.WORLD_HEIGHT) - HEIGHT_MARGIN)


func _slope_at(x: int, z: int) -> float:
	var dx: float = _final_height_at(x + 1, z) - _final_height_at(x - 1, z)
	var dz: float = _final_height_at(x, z + 1) - _final_height_at(x, z - 1)
	return sqrt(dx * dx + dz * dz) * 0.5


func _profile_position_at(x: int, z: int, continental: float) -> float:
	if _config.world_type == WorldGenConfig.WORLD_TYPE_FLAT:
		return float(TerrainProfileCatalog.PLAINS)
	var warped := _macro_warp(x, z)
	var landform: float = _noises[CHANNEL_LANDFORM].get_noise_2d(
		warped.x / (_config.macro_scale * 1.25), warped.y / (_config.macro_scale * 1.25)) * 0.5 + 0.5
	# Broad landform regions choose the profile. Fine ridge detail must never
	# switch a plain into a mountain over a handful of columns.
	var position: float = _smoothstep(0.30, 0.82, landform) * 4.0
	position *= _smoothstep(0.44, 0.78, continental)
	return clampf(position, 0.0, float(TerrainProfileCatalog.RIDGED_MOUNTAINS))


func _river_at(x: int, z: int, continental: float) -> float:
	if _config.world_type == WorldGenConfig.WORLD_TYPE_FLAT or _config.river_density <= 0.0:
		return 0.0
	var warped := _macro_warp(x, z)
	var corridor: float = absf(_noises[CHANNEL_RIVER].get_noise_2d(
		warped.x / (_config.macro_scale * 0.70), warped.y / (_config.macro_scale * 0.70)))
	var width: float = lerpf(0.018, 0.105, clampf(_config.river_density * 0.25, 0.0, 1.0))
	var channel: float = 1.0 - _smoothstep(width, width * 2.4, corridor)
	return channel * _smoothstep(0.43, 0.60, continental)


func _climate_at(x: int, z: int, height: float, river_value: float) -> Vector2:
	var warped := _macro_warp(x, z)
	var temperature_value: float = _noises[CHANNEL_TEMPERATURE].get_noise_2d(
		warped.x / (_config.biome_scale * 1.08), warped.y / (_config.biome_scale * 1.08)) * 0.78 + 0.5
	temperature_value -= maxf(height - float(VoxelDefsScript.SEA_LEVEL), 0.0) * 0.0035
	var moisture_value: float = _noises[CHANNEL_MOISTURE].get_noise_2d(
		warped.x / (_config.biome_scale * 0.92), warped.y / (_config.biome_scale * 0.92)) * 0.78 + 0.5
	moisture_value += river_value * 0.14
	moisture_value -= maxf(height - float(VoxelDefsScript.SEA_LEVEL), 0.0) * 0.0015
	return Vector2(clampf(temperature_value, 0.0, 1.0), clampf(moisture_value, 0.0, 1.0))


## x=closest climate biome, y=second closest, z=blend weight toward y (0..255).
## ChunkTerrainData stores both choices for continuous tint blending. Discrete
## surfaces and decorations use the primary biome so borders form broad,
## coherent ecotones instead of one-block checkerboards.
func _biome_choice(temperature_value: float, moisture_value: float) -> Vector3i:
	var first: int = BiomeCatalog.PLAINS
	var second: int = BiomeCatalog.FOREST
	var first_distance: float = INF
	var second_distance: float = INF
	for index in CLIMATE_BIOMES.size():
		var biome: int = CLIMATE_BIOMES[index]
		var dt: float = temperature_value - _biome_temperatures[index]
		var dm: float = moisture_value - _biome_moistures[index]
		var distance: float = dt * dt + dm * dm
		if distance < first_distance:
			second = first
			second_distance = first_distance
			first = biome
			first_distance = distance
		elif distance < second_distance:
			second = biome
			second_distance = distance
	var blend: float = first_distance / maxf(first_distance + second_distance, 0.00001)
	return Vector3i(first, second, roundi(blend * 255.0))


func _apply_biome_override(climate_biome: int, continental: float, height: float, river_value: float, profile: int) -> int:
	if continental < 0.18:
		return BiomeCatalog.DEEP_OCEAN
	if continental < 0.34:
		return BiomeCatalog.OCEAN
	if river_value > 0.62 and continental >= 0.45 and height <= float(VoxelDefsScript.SEA_LEVEL) + 2.0:
		return BiomeCatalog.RIVER
	if height <= float(VoxelDefsScript.SEA_LEVEL) + 1.0:
		return BiomeCatalog.BEACH
	if profile >= TerrainProfileCatalog.MOUNTAINS and height > float(VoxelDefsScript.SEA_LEVEL) + 29.0:
		return BiomeCatalog.HIGHLANDS
	# Wet climate on uplands is forest, not swamp. Keeping swamp classification
	# near sea level gives its mud, shallow pools, reeds, and mangroves a coherent
	# terrain identity instead of scattering the label across wet mountains.
	if climate_biome == BiomeCatalog.SWAMP and height > float(VoxelDefsScript.SEA_LEVEL) + 10.0:
		return BiomeCatalog.FOREST
	return climate_biome


func _macro_warp(x: int, z: int) -> Vector2:
	var scale: float = _config.macro_scale
	var source_x: float = float(x) / (scale * 0.65)
	var source_z: float = float(z) / (scale * 0.65)
	var amount: float = scale * 0.19
	return Vector2(
		float(x) + _noises[CHANNEL_WARP_X].get_noise_2d(source_x, source_z) * amount,
		float(z) + _noises[CHANNEL_WARP_Z].get_noise_2d(source_x, source_z) * amount
	)


func _profile_value(profile: int, field: int) -> float:
	return _profiles[profile * TerrainProfileCatalog.FIELD_COUNT + field]


func _smoothstep(edge0: float, edge1: float, value: float) -> float:
	var t: float = clampf((value - edge0) / (edge1 - edge0), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


func _ensure_configured() -> void:
	if not _configured:
		configure(WorldGenConfig.new())
