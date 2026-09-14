## Validated, value-only settings used by the deterministic world-generation pipeline.
## Treat instances as immutable after construction.
class_name WorldGenConfig
extends RefCounted

const CURRENT_VERSION: int = 6

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


func _init(source: Dictionary = {}) -> void:
	seed = int(source.get("seed", DEFAULT_SEED))
	world_type = clampi(int(source.get("world_type", DEFAULT_WORLD_TYPE)), WORLD_TYPE_NORMAL, WORLD_TYPE_AMPLIFIED)
	terrain_scale = clampf(float(source.get("terrain_scale", DEFAULT_TERRAIN_SCALE)), 0.25, 4.0)
	tree_density = clampf(float(source.get("tree_density", DEFAULT_TREE_DENSITY)), 0.0, 4.0)
	worldgen_version = max(1, int(source.get("worldgen_version", CURRENT_VERSION)))
	macro_scale = clampf(float(source.get("macro_scale", DEFAULT_MACRO_SCALE)), 32.0, 8192.0)
	biome_scale = clampf(float(source.get("biome_scale", DEFAULT_BIOME_SCALE)), 128.0, 8192.0)
	river_density = clampf(float(source.get("river_density", DEFAULT_RIVER_DENSITY)), 0.0, 4.0)
	erosion_strength = clampf(float(source.get("erosion_strength", DEFAULT_EROSION_STRENGTH)), 0.0, 1.0)
	regional_erosion = clampf(float(source.get("regional_erosion", DEFAULT_REGIONAL_EROSION)), 0.0, 1.0)
	hydraulic_erosion = bool(source.get("hydraulic_erosion", DEFAULT_HYDRAULIC_EROSION))
	cave_density = clampf(float(source.get("cave_density", DEFAULT_CAVE_DENSITY)), 0.0, 4.0)
	decoration_density = clampf(float(source.get("decoration_density", DEFAULT_DECORATION_DENSITY)), 0.0, 4.0)


static func from_dictionary(source: Dictionary) -> WorldGenConfig:
	return WorldGenConfig.new(source)


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
	}
