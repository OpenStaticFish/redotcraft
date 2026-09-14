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
const CHANNEL_RIVER_WIDTH: int = 9
const CHANNEL_RIVER_BED: int = 10
const CHANNEL_REEF: int = 11
const CHANNEL_KELP: int = 12
const CHANNEL_SEAGRASS: int = 13
const CHANNEL_SEABED: int = 14
const CHANNEL_ECOTONE: int = 15
const CHANNEL_LARGE_ISLAND: int = 16
const CHANNEL_SMALL_ISLAND: int = 17
const CHANNEL_COUNT: int = 18

const MIN_TERRAIN_HEIGHT: float = 3.0
const HEIGHT_MARGIN: float = 8.0

# Underwater split. The same continental band shapes the seabed depth curve,
# so a sea biome's label and its geometry cannot disagree. Patch fields decide
# coral, kelp, and seagrass regions instead of hard depth stripes. The shelf
# deliberately owns most of the ocean band: an abyss-only sea leaves the
# biome-specific seafloors too rare to encounter.
const OCEAN_CONTINENTAL: float = 0.34
const SLOPE_START: float = 0.12
const SLOPE_END: float = 0.24
const SHORE_SHELF_START: float = 0.24
const SHORE_SHELF_END: float = 0.36
const ABYSSAL_DEPTH: float = 19.0
const SHELF_DEPTH: float = 7.0
const SHORE_DEPTH: float = 2.5
const DEEP_SEA_DEPTH: float = 13.0
const FROZEN_SEA_TEMPERATURE: float = 0.22
const CORAL_REEF_TEMPERATURE: float = 0.60
const CORAL_REEF_DEPTH: float = 12.0
const KELP_FOREST_TEMPERATURE: float = 0.55
const KELP_FOREST_MIN_DEPTH: float = 4.0
const SEAGRASS_TEMPERATURE: float = 0.40
const SEAGRASS_DEPTH: float = 12.0
const SEABED_PATCH_THRESHOLD: float = 0.40
const REEF_MOUND_HEIGHT: float = 6.5
const SEABED_RELIEF_HEIGHT: float = 2.4
const REEF_PATCH_SCALE: float = 150.0
const KELP_PATCH_SCALE: float = 140.0
const SEAGRASS_PATCH_SCALE: float = 220.0
const SEABED_RELIEF_SCALE: float = 96.0
# River cross-section geometry in world blocks. The bed sits a few blocks below
# sea level at the centreline, banks taper over RIVER_BANK_WIDTH, and the
# floodplain grades back into natural terrain over RIVER_FLOODPLAIN_WIDTH.
# Distances come from a gradient-normalized corridor field, so these are real
# widths instead of noise-value bands whose extent depends on the local noise
# gradient (which made channels pinch, fan out, and read as angular cuts).
const RIVER_CHANNEL_HALF_MIN: float = 4.0
const RIVER_CHANNEL_HALF_MAX: float = 12.0
const RIVER_BANK_WIDTH: float = 10.0
const RIVER_FLOODPLAIN_WIDTH: float = 22.0
const RIVER_BED_DEPTH: float = 2.8
const RIVER_BED_DEPTH_VARIATION: float = 0.8
const RIVER_FLOODPLAIN_RISE: float = 2.0
const RIVER_WIDTH_SCALE_MIN: float = 0.72
const RIVER_WIDTH_SCALE_MAX: float = 1.75
const RIVER_WIDTH_VARIATION: float = 0.10
const RIVER_MIN_GRADIENT: float = 0.000001
# Corridor-space extent of the floodplain relief damping. The corridor is
# sampled at macro_scale * 0.70 and a typical noise gradient is order one, so
# 0.12 is roughly a 32-block apron at the default macro scale.
const RIVER_FLOODPLAIN_CORRIDOR: float = 0.12
# Meander warp, as fractions of macro_scale: wavelength and lateral amplitude.
const RIVER_MEANDER_SCALE: float = 0.34
const RIVER_MEANDER_AMOUNT: float = 0.12
# Independent sparse peak fields raise effective continentalness offshore. Their
# absolute scales are intentional: islands remain recognizable exploration-scale
# landmarks when the continent-size slider changes. A large-scale channel creates
# substantial landmasses and a short-scale channel adds islets; both fade before
# the mainland coast so continents remain intact.
const LARGE_ISLAND_SCALE: float = 720.0
const SMALL_ISLAND_SCALE: float = 135.0
# Ecotones likewise use an absolute walk-scale: changing biome territory size
# should not turn transition vegetation into continent-sized monocultures. The
# independent field avoids per-column hashes and forms broad organic patches.
const ECOTONE_PATCH_SCALE: float = 160.0
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
# The river corridor grid extends one cell past the source grid so the forward
# difference in +x and +z exists at every source cell. That keeps the
# gradient-normalized distance identical from every chunk and point query.
const CORRIDOR_MIN: int = SOURCE_MIN
const CORRIDOR_MAX: int = SOURCE_MAX + 1
const CORRIDOR_SIDE: int = CORRIDOR_MAX - CORRIDOR_MIN + 1
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

	var corridor := PackedFloat64Array()
	corridor.resize(CORRIDOR_SIDE * CORRIDOR_SIDE)
	var skip_rivers: bool = _config.world_type == WorldGenConfig.WORLD_TYPE_FLAT or _config.river_density <= 0.0
	if skip_rivers:
		corridor.fill(10.0)
	else:
		for local_z in range(CORRIDOR_MIN, CORRIDOR_MAX + 1):
			var corridor_z: int = origin_z + local_z
			var corridor_row: int = (local_z - CORRIDOR_MIN) * CORRIDOR_SIDE
			for local_x in range(CORRIDOR_MIN, CORRIDOR_MAX + 1):
				corridor[corridor_row + local_x - CORRIDOR_MIN] = _river_corridor_at(origin_x + local_x, corridor_z)

	var source_height := PackedFloat64Array()
	var source_continental := PackedFloat64Array()
	var source_mainland := PackedFloat64Array()
	var source_base := PackedFloat64Array()
	var source_river := PackedFloat64Array()
	var source_profile := PackedFloat64Array()
	var source_count: int = SOURCE_SIDE * SOURCE_SIDE
	source_height.resize(source_count)
	source_continental.resize(source_count)
	source_mainland.resize(source_count)
	source_base.resize(source_count)
	source_river.resize(source_count)
	source_profile.resize(source_count)
	for local_z in range(SOURCE_MIN, SOURCE_MAX + 1):
		var world_z: int = origin_z + local_z
		var row: int = (local_z - SOURCE_MIN) * SOURCE_SIDE
		var corridor_row: int = (local_z - CORRIDOR_MIN) * CORRIDOR_SIDE
		for local_x in range(SOURCE_MIN, SOURCE_MAX + 1):
			var world_x: int = origin_x + local_x
			var source_index: int = row + local_x - SOURCE_MIN
			var corridor_index: int = corridor_row + local_x - CORRIDOR_MIN
			var mainland: float = _mainland_continentalness_at(world_x, world_z)
			var continental: float = _continentalness_from_mainland(world_x, world_z, mainland)
			var base: float = _base_height_at(world_x, world_z, continental)
			var profile_position: float = _profile_position_at(world_x, world_z, continental)
			var river_distance: float = _river_distance_from_corridor(
				corridor[corridor_index],
				corridor[corridor_index + 1],
				corridor[corridor_index + CORRIDOR_SIDE])
			var river_width_scale: float = _river_width_scale_at(world_x, world_z)
			source_continental[source_index] = continental
			source_mainland[source_index] = mainland
			source_profile[source_index] = profile_position
			source_base[source_index] = base
			source_river[source_index] = _river_strength_from_distance(river_distance, mainland, river_width_scale)
			source_height[source_index] = _height_without_regional_erosion_from_samples(
				world_x, world_z, continental, mainland, base, profile_position, corridor[corridor_index])

	var raw_height := PackedFloat64Array()
	raw_height.resize(RAW_SIDE * RAW_SIDE)
	for local_z in range(RAW_MIN, RAW_MAX + 1):
		var world_z: int = origin_z + local_z
		var raw_row: int = (local_z - RAW_MIN) * RAW_SIDE
		var source_row: int = (local_z - SOURCE_MIN) * SOURCE_SIDE
		var corridor_row: int = (local_z - CORRIDOR_MIN) * CORRIDOR_SIDE
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
				# The channel is carved after hillslope erosion so the whole
				# downstream profile is re-shaped once, and so the many height
				# evaluations inside regional erosion do not pay for a river
				# distance query each.
				var corridor_index: int = corridor_row + local_x - CORRIDOR_MIN
				var river_distance: float = _river_distance_from_corridor(
					corridor[corridor_index],
					corridor[corridor_index + 1],
					corridor[corridor_index + CORRIDOR_SIDE])
				raw_value = _apply_river_carve(
					world_x, world_z, raw_value, river_distance,
					source_mainland[source_index], _river_width_scale_at(world_x, world_z))
			raw_height[raw_index] = clampf(raw_value, MIN_TERRAIN_HEIGHT, float(VoxelDefsScript.WORLD_HEIGHT) - HEIGHT_MARGIN)

	var final_height := PackedFloat64Array()
	final_height.resize(FINAL_SIDE * FINAL_SIDE)
	for local_z in range(FINAL_MIN, FINAL_MAX + 1):
		var world_z: int = origin_z + local_z
		var final_row: int = (local_z - FINAL_MIN) * FINAL_SIDE
		var raw_row: int = (local_z - RAW_MIN) * RAW_SIDE
		var source_row: int = (local_z - SOURCE_MIN) * SOURCE_SIDE
		for local_x in range(FINAL_MIN, FINAL_MAX + 1):
			var raw_index: int = raw_row + local_x - RAW_MIN
			var source_index: int = source_row + local_x - SOURCE_MIN
			final_height[final_row + local_x - FINAL_MIN] = _final_from_raw_neighborhood_with_profile(
				raw_height[raw_index],
				raw_height[raw_index - 1], raw_height[raw_index + 1],
				raw_height[raw_index - RAW_SIDE], raw_height[raw_index + RAW_SIDE],
				source_profile[source_index])
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
			var world_x: int = origin_x + local_x
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
			var biome: int = _apply_biome_override(
				biome_choice.x, continental, final_value, river_value, profile,
				temperature_value, world_x, world_z)
			var secondary: int = biome_choice.y if biome == biome_choice.x else biome
			var transition := _ecotone_choice(
				biome, secondary, biome_choice.z if biome == biome_choice.x else 0,
				world_x, world_z, final_value, profile)
			var dominant: int = transition.x
			var biome_blend_value: int = transition.y
			var ecotone_value: int = transition.z
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
			field.ecotone_strength[field_index] = ecotone_value
			field.dominant_biome[field_index] = dominant
	field.seal()
	return field


## Diagnostic-friendly point query. Unlike build_field, this deliberately returns
## a Dictionary and may be used by tools, previews, or spawn inspection.
func sample_point(x: int, z: int) -> Dictionary:
	_ensure_configured()
	var mainland: float = _mainland_continentalness_at(x, z)
	var continental: float = _continentalness_from_mainland(x, z, mainland)
	var base: float = _base_height_at(x, z, continental)
	var raw: float = _raw_height_at(x, z)
	var final_value: float = _final_height_at(x, z)
	var river_value: float = _river_at(x, z, mainland)
	var climate := _climate_at(x, z, final_value, river_value)
	var temperature_value: float = climate.x
	var moisture_value: float = climate.y
	var profile_position: float = _profile_position_at(x, z, continental)
	var profile: int = clampi(floori(profile_position), TerrainProfileCatalog.PLAINS, TerrainProfileCatalog.RIDGED_MOUNTAINS)
	var choice := _biome_choice(temperature_value, moisture_value)
	var biome: int = _apply_biome_override(
		choice.x, continental, final_value, river_value, profile, temperature_value, x, z)
	var secondary: int = choice.y if biome == choice.x else biome
	var transition := _ecotone_choice(
		biome, secondary, choice.z if biome == choice.x else 0,
		x, z, final_value, profile)
	var dominant: int = transition.x
	return {
		"continentalness": continental,
		"mainland_continentalness": mainland,
		"island_strength": maxf(continental - mainland, 0.0),
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
		"biome_blend": transition.y / 255.0,
		"ecotone_strength": transition.z / 255.0,
		"dominant_biome_id": dominant,
	}


## Exact compact query for cross-chunk feature origins. Decorations only need
## surface Y and the dominant biome, so avoid sample_point's raw/slope work and
## Dictionary allocation in the hot population path.
func sample_decoration_ground(x: int, z: int) -> Vector2i:
	_ensure_configured()
	var mainland := _mainland_continentalness_at(x, z)
	var continental := _continentalness_from_mainland(x, z, mainland)
	var final_value := _final_height_at(x, z)
	var river_value := _river_at(x, z, mainland)
	var climate := _climate_at(x, z, final_value, river_value)
	var profile_position := _profile_position_at(x, z, continental)
	var profile := clampi(floori(profile_position), TerrainProfileCatalog.PLAINS, TerrainProfileCatalog.RIDGED_MOUNTAINS)
	var choice := _biome_choice(climate.x, climate.y)
	var biome := _apply_biome_override(
		choice.x, continental, final_value, river_value, profile, climate.x, x, z)
	var secondary: int = choice.y if biome == choice.x else biome
	var transition := _ecotone_choice(
		biome, secondary, choice.z if biome == choice.x else 0,
		x, z, final_value, profile)
	var dominant: int = transition.x
	return Vector2i(clampi(roundi(final_value), 2, VoxelDefsScript.WORLD_HEIGHT - 2), dominant)


## Lightweight regional-map query. At the overlay's coarse 32-block stride,
## resolving the full radius-four erosion and final slope graph for every pixel
## adds seconds without changing the useful macro view. This keeps the exact
## continent/profile/river/climate fields and uses the pre-erosion profile
## height; chunk generation and gameplay always use build_field() instead.
func sample_debug_point(mode: String, x: int, z: int) -> Dictionary:
	_ensure_configured()
	var mainland := _mainland_continentalness_at(x, z)
	var continental := _continentalness_from_mainland(x, z, mainland)
	if mode == "continentalness":
		return {"continentalness": continental}
	var river_value := _river_at(x, z, mainland)
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
	# The cheap climate modes above intentionally use pre-erosion terrain. The
	# biome map must match generated ecotone ownership, whose terrain affinity is
	# based on final height, so pay for the exact query only on this mode.
	height = _final_height_at(x, z)
	climate = _climate_at(x, z, height, river_value)
	var choice := _biome_choice(climate.x, climate.y)
	var profile_position := _profile_position_at(x, z, continental)
	var profile := clampi(floori(profile_position), TerrainProfileCatalog.PLAINS, TerrainProfileCatalog.RIDGED_MOUNTAINS)
	if mode == "profile":
		return {"profile_id": profile}
	var biome := _apply_biome_override(
		choice.x, continental, height, river_value, profile, climate.x, x, z)
	var secondary: int = choice.y if biome == choice.x else biome
	var dominant: int = _ecotone_choice(
		biome, secondary, choice.z if biome == choice.x else 0,
		x, z, height, profile).x
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
		[FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 1.0, 2, 1201],
		[FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 1.0, 2, 1301],
		[FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 1.0, 2, 1013],
		[FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 1.0, 2, 1109],
		[FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 1.0, 2, 1409],
		[FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 1.0, 2, 1303],
		[FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 1.0, 2, 1601],
		[FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 1.0, 2, 1709],
		[FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 1.0, 2, 1801],
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
	# The channel meander uses FastNoiseLite's native domain warp instead of
	# GDScript warp channels. Point queries evaluate the corridor many times per
	# decoration, so the native single-pass warp keeps that path affordable.
	var river_noise: FastNoiseLite = result[CHANNEL_RIVER]
	var sample_scale: float = _config.macro_scale * 0.70
	river_noise.domain_warp_enabled = true
	river_noise.domain_warp_type = FastNoiseLite.DOMAIN_WARP_SIMPLEX
	river_noise.domain_warp_amplitude = (_config.macro_scale * RIVER_MEANDER_AMOUNT) / sample_scale
	river_noise.domain_warp_frequency = sample_scale / (_config.macro_scale * RIVER_MEANDER_SCALE)
	river_noise.domain_warp_fractal_type = FastNoiseLite.DOMAIN_WARP_FRACTAL_NONE
	river_noise.domain_warp_fractal_octaves = 1
	return result


func _continentalness_at(x: int, z: int) -> float:
	if _config.world_type == WorldGenConfig.WORLD_TYPE_FLAT:
		return 1.0
	var mainland: float = _mainland_continentalness_at(x, z)
	return _continentalness_from_mainland(x, z, mainland)


func _mainland_continentalness_at(x: int, z: int) -> float:
	if _config.world_type == WorldGenConfig.WORLD_TYPE_FLAT:
		return 1.0
	var warped := _macro_warp(x, z)
	var noise_value: float = _noises[CHANNEL_CONTINENT].get_noise_2d(
		warped.x / _config.macro_scale, warped.y / _config.macro_scale)
	return _smoothstep(-0.42, 0.40, noise_value)


func _continentalness_from_mainland(x: int, z: int, mainland: float) -> float:
	if mainland >= 0.38:
		return mainland
	var large_value: float = _noises[CHANNEL_LARGE_ISLAND].get_noise_2d(
		float(x) / LARGE_ISLAND_SCALE, float(z) / LARGE_ISLAND_SCALE) * 0.5 + 0.5
	var small_value: float = _noises[CHANNEL_SMALL_ISLAND].get_noise_2d(
		float(x) / SMALL_ISLAND_SCALE, float(z) / SMALL_ISLAND_SCALE) * 0.5 + 0.5
	var large_island: float = _smoothstep(0.66, 0.82, large_value) * 0.70
	var small_island: float = _smoothstep(0.72, 0.86, small_value) * 0.58
	var coast_fade: float = 1.0 - _smoothstep(0.24, 0.34, mainland)
	return maxf(mainland, maxf(large_island, small_island) * coast_fade)


func _base_height_at(x: int, z: int, continental: float) -> float:
	if _config.world_type == WorldGenConfig.WORLD_TYPE_FLAT:
		return float(VoxelDefsScript.SEA_LEVEL) + 2.0
	var profile_position: float = _profile_position_at(x, z, continental)
	var profile: int = clampi(floori(profile_position), 0, TerrainProfileCatalog.RIDGED_MOUNTAINS)
	var next_profile: int = mini(profile + 1, TerrainProfileCatalog.RIDGED_MOUNTAINS)
	var blend: float = profile_position - floorf(profile_position)
	var profile_base: float = lerpf(_profile_value(profile, TerrainProfileCatalog.FIELD_BASE_HEIGHT), _profile_value(next_profile, TerrainProfileCatalog.FIELD_BASE_HEIGHT), blend)
	var shoreline: float = _smoothstep(0.27, 0.52, continental)
	return lerpf(_ocean_floor_at(x, z, continental), profile_base, shoreline)


## Seabed shape: a broad shelf across most of the ocean band, a steeper
## continental slope, and a narrower abyssal basin. The depth curve uses the
## same continental band that classifies ocean biomes, so the geometry and its
## label always agree. Reef mounds and low sediment banks are added on top and
## the result is clamped so the floor never breaks the water surface.
func _ocean_floor_at(x: int, z: int, continental: float) -> float:
	var slope: float = _smoothstep(SLOPE_START, SLOPE_END, continental)
	var shore: float = _smoothstep(SHORE_SHELF_START, SHORE_SHELF_END, continental)
	var floor_height: float = lerpf(
		lerpf(float(VoxelDefsScript.SEA_LEVEL) - ABYSSAL_DEPTH,
			float(VoxelDefsScript.SEA_LEVEL) - SHELF_DEPTH, slope),
		float(VoxelDefsScript.SEA_LEVEL) - SHORE_DEPTH, shore)
	var depth: float = float(VoxelDefsScript.SEA_LEVEL) - floor_height
	# Reef mounds grow on the mid-depth shelf. The depth gate keeps them off
	# the beach and out of the abyssal plain even where the patch mask peaks.
	var mound: float = _seabed_patch_strength(x, z, CHANNEL_REEF, REEF_PATCH_SCALE) * REEF_MOUND_HEIGHT \
		* _smoothstep(3.0, 6.0, depth) * (1.0 - _smoothstep(12.0, 16.0, depth))
	var relief: float = _noises[CHANNEL_SEABED].get_noise_2d(
		float(x) / SEABED_RELIEF_SCALE, float(z) / SEABED_RELIEF_SCALE) * SEABED_RELIEF_HEIGHT
	return minf(floor_height + mound + relief, float(VoxelDefsScript.SEA_LEVEL) - SHORE_DEPTH)


## Positive-only patch field in [0, 1]. Shared by the seabed mound/bank
## shaping and the underwater biome split so a patch's geometry and its biome
## cannot disagree.
func _seabed_patch_strength(x: int, z: int, channel: int, scale: float) -> float:
	var value: float = _noises[channel].get_noise_2d(float(x) / scale, float(z) / scale)
	return _smoothstep(-0.05, 0.45, value)


func _height_without_regional_erosion(x: int, z: int) -> float:
	var mainland: float = _mainland_continentalness_at(x, z)
	var continental: float = _continentalness_from_mainland(x, z, mainland)
	var base: float = _base_height_at(x, z, continental)
	if _config.world_type == WorldGenConfig.WORLD_TYPE_FLAT:
		return base
	var profile_position: float = _profile_position_at(x, z, continental)
	return _height_without_regional_erosion_from_samples(
		x, z, continental, mainland, base,
		profile_position, _river_corridor_at(x, z))


## Computes the expensive, no-regional source height from values cached in the
## expanded grid. All arguments are scalar so point queries retain their API and
## exact coordinate behaviour. Terrain shaping only needs the raw corridor value
## (for floodplain damping); the channel carve runs later on the eroded height.
func _height_without_regional_erosion_from_samples(
		x: int,
		z: int,
		continental: float,
		mainland: float,
		base: float,
		profile_position: float,
		river_corridor: float) -> float:
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
	# Floodplain grading: damp broad relief and fine detail near the channel so
	# the cut blends into graded ground instead of stopping at a natural hill.
	# The mask is corridor-space rather than distance-space: the carve owns the
	# exact channel width, while this only needs a coherent low-relief apron.
	var floodplain: float = _river_floodplain_weight(river_corridor, mainland)
	var relief_gain: float = 1.0 - floodplain * 0.45
	var height: float = base + (detail * relief_gain + relief * ridge * ridge * ridge_weight * relief_gain) * land * relief_scale
	# Keep regional relief separate from small landforms. Fade these additions
	# at coasts; the channel carve later still owns the floor and waterline.
	height += _local_landform_detail(warped, profile, next_profile, profile_blend) \
		* _smoothstep(0.43, 0.60, continental) * relief_scale * (1.0 - floodplain * 0.7)
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
	if _config.world_type != WorldGenConfig.WORLD_TYPE_FLAT:
		height = _apply_river_carve(
			x, z, height, _river_distance_at(x, z),
			_mainland_continentalness_at(x, z), _river_width_scale_at(x, z))
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
	var mainland := _mainland_continentalness_at(x, z)
	var continental := _continentalness_from_mainland(x, z, mainland)
	var river_value := _river_at(x, z, mainland)
	var climate := _climate_at(x, z, height, river_value)
	var climate_altitude := maxf(height - float(VoxelDefsScript.SEA_LEVEL), 0.0)
	return _apply_climate_terrain_shape(
		height, _profile_position_at(x, z, continental), gradient, local_relief,
		climate.x + climate_altitude * 0.0035,
		climate.y + climate_altitude * 0.0015)


func _final_from_raw_neighborhood(x: int, z: int, raw: float, west: float, east: float, north: float, south: float) -> float:
	if _config.world_type == WorldGenConfig.WORLD_TYPE_FLAT:
		return raw
	var continental: float = _continentalness_at(x, z)
	var profile_position: float = _profile_position_at(x, z, continental)
	return _final_from_raw_neighborhood_with_profile(
		raw, west, east, north, south, profile_position)


## Chunk fields already cache profile position in the expanded source grid; use
## it here to avoid re-sampling mainland plus both island channels during the
## smoothing pass. Point queries retain the exact wrapper above.
func _final_from_raw_neighborhood_with_profile(raw: float, west: float, east: float,
		north: float, south: float,
		profile_position: float) -> float:
	if _config.world_type == WorldGenConfig.WORLD_TYPE_FLAT:
		return raw
	var gradient: float = sqrt((east - west) * (east - west) + (south - north) * (south - north)) * 0.5
	var mean: float = (west + east + north + south) * 0.25
	var talus_weight: float = _smoothstep(0.6, 5.5, gradient) * _config.erosion_strength
	var talus: float = lerpf(raw, mean, talus_weight * 0.33)
	# Flatten isolated one-to-two block deviations from the local mean. On a
	# consistent slope raw is already close to the mean, so this only removes
	# the single-block bumps that read as rice terraces on gentle ground.
	var micro: float = talus - mean
	if absf(micro) <= 1.8:
		talus = mean + micro * 0.35
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


## Raw river corridor field: absolute value of a warped low-frequency noise.
## Its zero level set is the channel centreline. The noise carries a native
## domain warp that bends the corridor into meanders instead of tracing the raw
## level set, whose long straight segments and sharp corners read as artificial.
func _river_corridor_at(x: int, z: int) -> float:
	if _config.world_type == WorldGenConfig.WORLD_TYPE_FLAT or _config.river_density <= 0.0:
		return 10.0
	var warped := _macro_warp(x, z)
	var sample_scale: float = _config.macro_scale * 0.70
	return absf(_noises[CHANNEL_RIVER].get_noise_2d(
		warped.x / sample_scale, warped.y / sample_scale))


## |n| / |grad n| is the first-order distance to the zero level set, in blocks.
## Forward differences need only two neighbour samples, which keeps point
## queries affordable; both chunk fields and point queries use the same formula.
func _river_distance_from_corridor(center: float, east: float, south: float) -> float:
	var dx: float = east - center
	var dz: float = south - center
	var gradient: float = sqrt(dx * dx + dz * dz)
	return center / maxf(gradient, RIVER_MIN_GRADIENT)


func _river_distance_at(x: int, z: int) -> float:
	return _river_distance_from_corridor(
		_river_corridor_at(x, z),
		_river_corridor_at(x + 1, z),
		_river_corridor_at(x, z + 1))


## Channel width scales with the river-density control and a slow along-channel
## variation, so reaches widen into pools and narrow into riffles instead of
## staying perfectly uniform.
func _river_width_scale_at(x: int, z: int) -> float:
	var density_norm: float = clampf(_config.river_density * 0.25, 0.0, 1.0)
	var base_scale: float = lerpf(RIVER_WIDTH_SCALE_MIN, RIVER_WIDTH_SCALE_MAX, density_norm)
	if _config.world_type == WorldGenConfig.WORLD_TYPE_FLAT or _config.river_density <= 0.0:
		return base_scale
	# Sampled unwarped: the width variation only needs to be coherent, and the
	# extra macro-warp evaluation would be paid by every point query.
	var variation: float = _noises[CHANNEL_RIVER_WIDTH].get_noise_2d(
		float(x) / (_config.macro_scale * 0.50), float(z) / (_config.macro_scale * 0.50))
	return base_scale * (1.0 + variation * RIVER_WIDTH_VARIATION)


func _channel_half_width(width_scale: float) -> float:
	return lerpf(RIVER_CHANNEL_HALF_MIN, RIVER_CHANNEL_HALF_MAX, clampf(_config.river_density * 0.25, 0.0, 1.0)) * width_scale


## Strength of the floodplain grading mask, 0 outside the river corridor and 1
## at the channel centre. Damping terrain amplitudes here lets the carve blend
## into the surroundings rather than ending at a cliff of natural relief. The
## corridor-space extent is a tuning constant rather than a true width; the
## distance-normalized carve owns the actual channel geometry.
func _river_floodplain_weight(river_corridor: float, continental: float) -> float:
	if _config.world_type == WorldGenConfig.WORLD_TYPE_FLAT or _config.river_density <= 0.0:
		return 0.0
	var density_norm: float = clampf(_config.river_density * 0.25, 0.0, 1.0)
	var extent: float = RIVER_FLOODPLAIN_CORRIDOR * lerpf(RIVER_WIDTH_SCALE_MIN, RIVER_WIDTH_SCALE_MAX, density_norm)
	return _smoothstep(0.43, 0.60, continental) \
		* (1.0 - _smoothstep(extent * 0.05, extent, river_corridor))


## Channel strength 0..1: used for climate moisture, biome selection, the voxel
## surface rules, cave protection, and the debug river map. It follows the same
## cross-channel distance as the carve so the water body and its bank share one
## shape.
func _river_strength_from_distance(distance: float, continental: float, width_scale: float) -> float:
	if _config.world_type == WorldGenConfig.WORLD_TYPE_FLAT or _config.river_density <= 0.0:
		return 0.0
	var channel_half: float = _channel_half_width(width_scale)
	# The biome/moisture band deliberately reaches the waterline (about 73% of
	# the bank run), so wet cells read as RIVER instead of a fragmented BEACH
	# ribbon and the strength stays monotonic along the cross-section.
	var bank_half: float = channel_half + RIVER_BANK_WIDTH * width_scale * 1.6
	if distance >= bank_half:
		return 0.0
	return (1.0 - _smoothstep(channel_half, bank_half, distance)) * _smoothstep(0.43, 0.60, continental)


func _river_at(x: int, z: int, continental: float) -> float:
	return _river_strength_from_distance(_river_distance_at(x, z), continental, _river_width_scale_at(x, z))


## Pool-and-riffle bed variation so the deepest line is not a constant-depth
## trench. Sampled unwarped to keep the carve path cheap.
func _river_bed_depth_at(x: int, z: int) -> float:
	var variation: float = _noises[CHANNEL_RIVER_BED].get_noise_2d(
		float(x) / (_config.macro_scale * 0.45), float(z) / (_config.macro_scale * 0.45))
	return RIVER_BED_DEPTH + variation * RIVER_BED_DEPTH_VARIATION


## Carves a smooth channel cross-section instead of dropping every corridor
## column to one sea-relative floor. The bed follows a smoothstep from its
## centreline depth up to a bank crest, then the floodplain fades the carve back
## into natural terrain over a wider span. The lowland gate keeps channels
## sea-connected and prevents cuts through uplands; only downward motion is
## applied so a natural hollow is never filled.
func _apply_river_carve(x: int, z: int, height: float, distance: float, continental: float, width_scale: float) -> float:
	var channel_half: float = _channel_half_width(width_scale)
	var bank_half: float = channel_half + RIVER_BANK_WIDTH * width_scale
	var flood_half: float = bank_half + RIVER_FLOODPLAIN_WIDTH * width_scale
	if distance >= flood_half:
		return height
	var lowland: float = 1.0 - _smoothstep(float(VoxelDefsScript.SEA_LEVEL + 8), float(VoxelDefsScript.SEA_LEVEL + 24), height)
	var gate: float = _smoothstep(0.43, 0.60, continental) * lowland
	if gate <= 0.0:
		return height
	var bed: float = float(VoxelDefsScript.SEA_LEVEL) - _river_bed_depth_at(x, z)
	var flood: float = float(VoxelDefsScript.SEA_LEVEL) + RIVER_FLOODPLAIN_RISE
	# A dished cross-section: nearly flat at the thalweg (zero slope at the
	# centre), then a steeper bank run up to the floodplain. The previous
	# smoothstep profile made the deepest line a single point and left wide,
	# ankle-deep pans at the edges.
	var t: float = clampf(distance / bank_half, 0.0, 1.0)
	var target: float = lerpf(bed, flood, pow(t, 1.6))
	var weight: float = gate * (1.0 - _smoothstep(bank_half, flood_half, distance))
	return lerpf(height, minf(height, target), weight)


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
## surfaces and decorations use the coherent dominant biome chosen by
## _ecotone_choice() instead of one-block dithering.
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


## Expands the nearest-climate boundary into an ecotone and chooses broad
## secondary-biome patches inside it. The climate distance still owns the mix;
## profile/elevation suitability only bends the boundary, and coherent noise
## prevents a checkerboard of surface blocks and species.
## Returns dominant biome, tint blend (0..255), and ecotone strength (0..255).
func _ecotone_choice(primary: int, secondary: int, raw_blend: int, world_x: int,
		world_z: int, height: float, profile: int) -> Vector3i:
	if primary == secondary or raw_blend <= 0:
		return Vector3i(primary, 0, 0)
	var climate_closeness: float = clampf(float(raw_blend) / 127.5, 0.0, 1.0)
	# The old tint-only blend used half this climate ratio directly. Starting the
	# material ecotone before the exact tie creates a broad shoulder while the
	# lower gate protects the middle of large biome territories.
	var strength: float = _smoothstep(0.18, 0.88, climate_closeness)
	var organic: float = _noises[CHANNEL_ECOTONE].get_noise_2d(
		float(world_x) / ECOTONE_PATCH_SCALE, float(world_z) / ECOTONE_PATCH_SCALE) * 0.5 + 0.5
	var primary_affinity: float = _biome_terrain_affinity(primary, height, profile)
	var secondary_affinity: float = _biome_terrain_affinity(secondary, height, profile)
	var terrain_bias: float = clampf((secondary_affinity - primary_affinity) * 0.16, -0.12, 0.12)
	var secondary_share: float = clampf(strength * 0.24 + terrain_bias * strength, 0.0, 0.34)
	var dominant: int = secondary if organic < secondary_share else primary
	var tint_blend: int = roundi(minf(0.5, climate_closeness * 0.64) * 255.0)
	return Vector3i(dominant, tint_blend, roundi(strength * 255.0))


func _biome_terrain_affinity(biome: int, height: float, profile: int) -> float:
	var altitude: float = maxf(height - float(VoxelDefsScript.SEA_LEVEL), 0.0)
	var lowland: float = 1.0 - _smoothstep(5.0, 17.0, altitude)
	var upland: float = _smoothstep(1.0, 3.0, float(profile))
	match biome:
		BiomeCatalog.SWAMP:
			return lowland * (1.0 - upland)
		BiomeCatalog.MEADOW, BiomeCatalog.PLAINS:
			return 1.0 - upland * 0.45
		BiomeCatalog.FOREST, BiomeCatalog.TAIGA, BiomeCatalog.JUNGLE:
			return 0.45 + upland * 0.35
		BiomeCatalog.SNOW:
			return clampf(altitude / 34.0, 0.0, 1.0)
		BiomeCatalog.BADLANDS:
			return 0.35 + upland * 0.45
	return 0.5


func _apply_biome_override(climate_biome: int, continental: float, height: float, river_value: float, profile: int, temperature: float, world_x: int, world_z: int) -> int:
	# Only water the seabed actually covers becomes a sea biome; a rare raised
	# ocean-floor column falls through to the waterline checks below.
	if continental < OCEAN_CONTINENTAL and height <= float(VoxelDefsScript.SEA_LEVEL):
		return _underwater_biome(height, temperature, world_x, world_z)
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


## Depth- and climate-appropriate underwater biome chosen from the same final
## height and patch fields the seabed geometry uses. Cold water wins first,
## then the abyssal plain, then coral/kelp/seagrass patches cover the shelf;
## plain shelf sea remains the fallback so the split never gaps.
func _underwater_biome(height: float, temperature: float, world_x: int, world_z: int) -> int:
	var depth: float = float(VoxelDefsScript.SEA_LEVEL) - height
	if temperature <= FROZEN_SEA_TEMPERATURE:
		return BiomeCatalog.FROZEN_OCEAN
	if depth >= DEEP_SEA_DEPTH:
		return BiomeCatalog.DEEP_OCEAN
	if temperature >= CORAL_REEF_TEMPERATURE and depth <= CORAL_REEF_DEPTH \
			and _seabed_patch_strength(world_x, world_z, CHANNEL_REEF, REEF_PATCH_SCALE) >= SEABED_PATCH_THRESHOLD:
		return BiomeCatalog.CORAL_REEF
	if temperature <= KELP_FOREST_TEMPERATURE and depth >= KELP_FOREST_MIN_DEPTH \
			and _seabed_patch_strength(world_x, world_z, CHANNEL_KELP, KELP_PATCH_SCALE) >= SEABED_PATCH_THRESHOLD:
		return BiomeCatalog.KELP_FOREST
	if temperature >= SEAGRASS_TEMPERATURE and depth <= SEAGRASS_DEPTH \
			and _seabed_patch_strength(world_x, world_z, CHANNEL_SEAGRASS, SEAGRASS_PATCH_SCALE) >= SEABED_PATCH_THRESHOLD:
		return BiomeCatalog.SEAGRASS_MEADOW
	return BiomeCatalog.OCEAN


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
