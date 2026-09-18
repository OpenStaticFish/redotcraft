## Validated, value-only settings used by the deterministic world-generation pipeline.
## Treat instances as immutable after construction.
class_name WorldGenConfig
extends RefCounted

const CURRENT_VERSION: int = 14
const SPLINE_TERRAIN_VERSION: int = 10
const VARIANT_WORLDGEN_VERSION: int = 11
const CAVE_INDEPENDENT_ORES_VERSION: int = 14

const WORLD_TYPE_NORMAL: int = 0
const WORLD_TYPE_FLAT: int = 1
const WORLD_TYPE_AMPLIFIED: int = 2

const DEFAULT_SEED: int = 0
const DEFAULT_WORLD_TYPE: int = WORLD_TYPE_NORMAL
const DEFAULT_TERRAIN_SCALE: float = 1.0
const DEFAULT_TREE_DENSITY: float = 1.0
const DEFAULT_MACRO_SCALE: float = 384.0
const DEFAULT_BIOME_SCALE: float = 3072.0
const DEFAULT_RIVER_DENSITY: float = 1.0
const DEFAULT_EROSION_STRENGTH: float = 0.55
const DEFAULT_REGIONAL_EROSION: float = 0.5
const DEFAULT_HYDRAULIC_EROSION: bool = false
const DEFAULT_CAVE_DENSITY: float = 1.0
const DEFAULT_DECORATION_DENSITY: float = 1.0
const DEFAULT_SPLINE_TERRAIN: bool = false
const DEFAULT_ELEVATED_HYDROLOGY: bool = false
const DEFAULT_CLIMATE_VARIANTS: bool = true
const DEFAULT_REGION_STRUCTURES: bool = true

const MIN_TERRAIN_SCALE: float = 0.25
const MAX_TERRAIN_SCALE: float = 2.0
const MIN_TREE_DENSITY: float = 0.0
const MAX_TREE_DENSITY: float = 4.0
const MIN_MACRO_SCALE: float = 32.0
const MAX_MACRO_SCALE: float = 8192.0
const MIN_BIOME_SCALE: float = 128.0
const MAX_BIOME_SCALE: float = 8192.0
const MIN_RIVER_DENSITY: float = 0.0
const MAX_RIVER_DENSITY: float = 4.0
const MIN_EROSION_STRENGTH: float = 0.0
const MAX_EROSION_STRENGTH: float = 1.0
const MIN_CAVE_DENSITY: float = 0.0
const MAX_CAVE_DENSITY: float = 4.0
const MIN_DECORATION_DENSITY: float = 0.0
const MAX_DECORATION_DENSITY: float = 4.0

# Shared generation semantics. These are named compatibility values, not extra
# UI controls; changing one requires a versioned generation path.
const RIVER_CHANNEL_THRESHOLD: float = 0.62
const RIVER_DENSITY_NORMALIZATION: float = 0.25
const RIVER_CORRIDOR_SCALE: float = 0.70
const RIVER_UNDERGROUND_CLEARANCE: int = 3

var seed: int
var world_type: int
var terrain_scale: float
var tree_density: float
var worldgen_version: int
var macro_scale: float
var biome_scale: float
var river_density: float
var erosion_strength: float
var regional_erosion: float
var hydraulic_erosion: bool
var cave_density: float
var decoration_density: float
var spline_terrain: bool
var elevated_hydrology: bool
var climate_variants: bool
var region_structures: bool


func _init(source: Dictionary = {}) -> void:
	seed = int(source.get("seed", DEFAULT_SEED))
	world_type = clampi(int(source.get("world_type", DEFAULT_WORLD_TYPE)), WORLD_TYPE_NORMAL, WORLD_TYPE_AMPLIFIED)
	terrain_scale = clampf(float(source.get("terrain_scale", DEFAULT_TERRAIN_SCALE)), MIN_TERRAIN_SCALE, MAX_TERRAIN_SCALE)
	tree_density = clampf(float(source.get("tree_density", DEFAULT_TREE_DENSITY)), MIN_TREE_DENSITY, MAX_TREE_DENSITY)
	worldgen_version = clampi(int(source.get("worldgen_version", CURRENT_VERSION)), 1, CURRENT_VERSION)
	macro_scale = clampf(float(source.get("macro_scale", DEFAULT_MACRO_SCALE)), MIN_MACRO_SCALE, MAX_MACRO_SCALE)
	biome_scale = clampf(float(source.get("biome_scale", DEFAULT_BIOME_SCALE)), MIN_BIOME_SCALE, MAX_BIOME_SCALE)
	river_density = clampf(float(source.get("river_density", DEFAULT_RIVER_DENSITY)), MIN_RIVER_DENSITY, MAX_RIVER_DENSITY)
	erosion_strength = clampf(float(source.get("erosion_strength", DEFAULT_EROSION_STRENGTH)), MIN_EROSION_STRENGTH, MAX_EROSION_STRENGTH)
	regional_erosion = clampf(float(source.get("regional_erosion", DEFAULT_REGIONAL_EROSION)), MIN_EROSION_STRENGTH, MAX_EROSION_STRENGTH)
	hydraulic_erosion = bool(source.get("hydraulic_erosion", DEFAULT_HYDRAULIC_EROSION))
	cave_density = clampf(float(source.get("cave_density", DEFAULT_CAVE_DENSITY)), MIN_CAVE_DENSITY, MAX_CAVE_DENSITY)
	decoration_density = clampf(float(source.get("decoration_density", DEFAULT_DECORATION_DENSITY)), MIN_DECORATION_DENSITY, MAX_DECORATION_DENSITY)
	spline_terrain = worldgen_version >= SPLINE_TERRAIN_VERSION \
		and bool(source.get("spline_terrain", DEFAULT_SPLINE_TERRAIN))
	elevated_hydrology = worldgen_version >= SPLINE_TERRAIN_VERSION \
		and bool(source.get("elevated_hydrology", DEFAULT_ELEVATED_HYDROLOGY))
	climate_variants = worldgen_version >= VARIANT_WORLDGEN_VERSION \
		and bool(source.get("climate_variants", DEFAULT_CLIMATE_VARIANTS))
	region_structures = worldgen_version >= VARIANT_WORLDGEN_VERSION \
		and bool(source.get("region_structures", DEFAULT_REGION_STRUCTURES))


static func from_dictionary(source: Dictionary) -> WorldGenConfig:
	return WorldGenConfig.new(source)


static func default_dictionary() -> Dictionary:
	return WorldGenConfig.new().to_dictionary()


func to_dictionary() -> Dictionary:
	return {
		"seed": seed,
		"world_type": world_type,
		"terrain_scale": terrain_scale,
		"tree_density": tree_density,
		"worldgen_version": worldgen_version,
		"macro_scale": macro_scale,
		"biome_scale": biome_scale,
		"river_density": river_density,
		"erosion_strength": erosion_strength,
		"regional_erosion": regional_erosion,
		"hydraulic_erosion": hydraulic_erosion,
		"cave_density": cave_density,
		"decoration_density": decoration_density,
		"spline_terrain": spline_terrain,
		"elevated_hydrology": elevated_hydrology,
		"climate_variants": climate_variants,
		"region_structures": region_structures,
	}
