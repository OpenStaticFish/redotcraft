## Immutable biome metadata stored in parallel packed arrays for hot generation lookups.
class_name BiomeCatalog
extends RefCounted

const PLAINS: int = 0
const FOREST: int = 1
const DESERT: int = 2
const SNOW: int = 3
const SWAMP: int = 4
const OCEAN: int = 5
const DEEP_OCEAN: int = 6
const BEACH: int = 7
const RIVER: int = 8
const JUNGLE: int = 9
const SAVANNA: int = 10
const TAIGA: int = 11
const BADLANDS: int = 12
const MEADOW: int = 13
const HIGHLANDS: int = 14

const DECORATION_NONE: int = 0
const DECORATION_GRASSLAND: int = 1
const DECORATION_FOREST: int = 2
const DECORATION_DESERT: int = 3
const DECORATION_WETLAND: int = 4
const DECORATION_TROPICAL: int = 5
const DECORATION_CONIFER: int = 6
const DECORATION_BADLANDS: int = 7
const DECORATION_ALPINE: int = 8
const DECORATION_PLAINS: int = 9
const DECORATION_MEADOW: int = 10
const DECORATION_SAVANNA: int = 11
const DECORATION_SWAMP: int = 12
const DECORATION_TAIGA: int = 13
const DECORATION_SNOWFIELD: int = 14
const DECORATION_RIVERBANK: int = 15
const DECORATION_BEACH: int = 16

const TYPE_NONE: int = 0
const TYPE_OAK: int = 1
const TYPE_BIRCH: int = 2
const TYPE_CACTUS: int = 3
const TYPE_REEDS: int = 4
const TYPE_JUNGLE_TREE: int = 5
const TYPE_ACACIA: int = 6
const TYPE_SPRUCE: int = 7
const TYPE_BOULDER: int = 8

const BLOCK_GRASS: int = 1
const BLOCK_DIRT: int = 2
const BLOCK_STONE: int = 3
const BLOCK_SAND: int = 7
const BLOCK_SNOW: int = 10
const BLOCK_GRAVEL: int = 12
const BLOCK_CLAY: int = 17
const BLOCK_MUD: int = 18
const BLOCK_RED_SAND: int = 19
const BLOCK_TERRACOTTA: int = 25

var _names: PackedStringArray = PackedStringArray()
var _temperature_centers: PackedFloat32Array = PackedFloat32Array()
var _moisture_centers: PackedFloat32Array = PackedFloat32Array()
var _surface_blocks: PackedByteArray = PackedByteArray()
var _subsurface_blocks: PackedByteArray = PackedByteArray()
var _underwater_blocks: PackedByteArray = PackedByteArray()
var _soil_depths: PackedByteArray = PackedByteArray()
var _foliage_colors: PackedColorArray = PackedColorArray()
var _decoration_sets: PackedByteArray = PackedByteArray()
var _decoration_types: PackedByteArray = PackedByteArray()


func _init() -> void:
	_add("plains", 0.55, 0.52, BLOCK_GRASS, BLOCK_DIRT, BLOCK_SAND, 3, Color("#78ae45"), DECORATION_PLAINS, TYPE_OAK)
	_add("forest", 0.56, 0.68, BLOCK_GRASS, BLOCK_DIRT, BLOCK_GRAVEL, 4, Color("#4d8c42"), DECORATION_FOREST, TYPE_OAK)
	_add("desert", 0.80, 0.16, BLOCK_SAND, BLOCK_SAND, BLOCK_SAND, 4, Color("#c8b45a"), DECORATION_DESERT, TYPE_CACTUS)
	_add("snow", 0.12, 0.58, BLOCK_SNOW, BLOCK_DIRT, BLOCK_GRAVEL, 3, Color("#c5d8d2"), DECORATION_SNOWFIELD, TYPE_SPRUCE)
	_add("swamp", 0.62, 0.88, BLOCK_MUD, BLOCK_DIRT, BLOCK_CLAY, 4, Color("#557a3c"), DECORATION_SWAMP, TYPE_REEDS)
	_add("ocean", 0.52, 0.62, BLOCK_SAND, BLOCK_SAND, BLOCK_GRAVEL, 3, Color("#4b8797"), DECORATION_NONE, TYPE_NONE)
	_add("deep_ocean", 0.46, 0.65, BLOCK_GRAVEL, BLOCK_STONE, BLOCK_GRAVEL, 2, Color("#3e7185"), DECORATION_NONE, TYPE_NONE)
	_add("beach", 0.62, 0.45, BLOCK_SAND, BLOCK_SAND, BLOCK_SAND, 3, Color("#b9ac62"), DECORATION_BEACH, TYPE_NONE)
	_add("river", 0.50, 0.70, BLOCK_SAND, BLOCK_DIRT, BLOCK_GRAVEL, 2, Color("#548c6b"), DECORATION_RIVERBANK, TYPE_REEDS)
	_add("jungle", 0.74, 0.80, BLOCK_GRASS, BLOCK_DIRT, BLOCK_MUD, 4, Color("#3d8d36"), DECORATION_TROPICAL, TYPE_JUNGLE_TREE)
	_add("savanna", 0.72, 0.38, BLOCK_GRASS, BLOCK_DIRT, BLOCK_SAND, 3, Color("#94a343"), DECORATION_SAVANNA, TYPE_ACACIA)
	_add("taiga", 0.28, 0.62, BLOCK_GRASS, BLOCK_DIRT, BLOCK_GRAVEL, 4, Color("#426c4d"), DECORATION_TAIGA, TYPE_SPRUCE)
	_add("badlands", 0.82, 0.32, BLOCK_RED_SAND, BLOCK_TERRACOTTA, BLOCK_RED_SAND, 5, Color("#b76b3f"), DECORATION_BADLANDS, TYPE_CACTUS)
	_add("meadow", 0.46, 0.66, BLOCK_GRASS, BLOCK_DIRT, BLOCK_GRAVEL, 3, Color("#7fb65b"), DECORATION_MEADOW, TYPE_BIRCH)
	_add("highlands", 0.34, 0.46, BLOCK_STONE, BLOCK_STONE, BLOCK_GRAVEL, 2, Color("#6f8e5d"), DECORATION_ALPINE, TYPE_BOULDER)


func biome_count() -> int:
	return _names.size()


func name_for(biome: int) -> String:
	return _names[_safe_id(biome)]


func id_for_name(biome_name: String) -> int:
	for biome in _names.size():
		if _names[biome] == biome_name:
			return biome
	return PLAINS


func temperature_center(biome: int) -> float:
	return _temperature_centers[_safe_id(biome)]


func moisture_center(biome: int) -> float:
	return _moisture_centers[_safe_id(biome)]


func surface_block(biome: int) -> int:
	return _surface_blocks[_safe_id(biome)]


func subsurface_block(biome: int) -> int:
	return _subsurface_blocks[_safe_id(biome)]


func underwater_block(biome: int) -> int:
	return _underwater_blocks[_safe_id(biome)]


## A depth-led sediment rule keeps a sandy coastal shelf continuous when a
## climate biome gives way to ocean. Biome IDs are deliberately not used for
## shallow water: their dithered/coast-transition boundary previously made
## gravel begin immediately beside a sand beach.
func seabed_block(biome: int, water_depth: int) -> int:
	var depth := maxi(water_depth, 0)
	if depth <= 11:
		return BLOCK_SAND
	if _safe_id(biome) == RIVER and depth <= 14:
		return BLOCK_CLAY
	return BLOCK_GRAVEL


## Thick enough to keep normal shelf faces sedimentary rather than exposing a
## short stone layer beneath every one-block seabed step.
func seabed_depth(water_depth: int) -> int:
	return 7 if water_depth <= 11 else 5


func soil_depth(biome: int) -> int:
	return _soil_depths[_safe_id(biome)]


func foliage_color(biome: int) -> Color:
	return _foliage_colors[_safe_id(biome)]


## Multipliers consumed by the water mesh's vertex color. Keeping this in the
## biome catalog makes regional water grading configurable without materials.
func water_tint(biome: int) -> Color:
	match _safe_id(biome):
		DEEP_OCEAN:
			return Color(0.72, 0.84, 1.08, 1.0)
		OCEAN:
			return Color(0.82, 0.94, 1.08, 1.0)
		SWAMP:
			return Color(0.68, 0.86, 0.62, 1.0)
		RIVER:
			return Color(0.82, 1.04, 1.08, 1.0)
		SNOW, TAIGA:
			return Color(0.82, 1.02, 1.12, 1.0)
		DESERT, BADLANDS:
			return Color(1.08, 1.03, 0.84, 1.0)
		_:
			return Color.WHITE


func decoration_set(biome: int) -> int:
	return _decoration_sets[_safe_id(biome)]


func decoration_type(biome: int) -> int:
	return _decoration_types[_safe_id(biome)]


func _add(name: String, temp: float, wetness: float, surface: int, subsurface: int, underwater: int, soil_depth: int, foliage: Color, decoration_set_value: int, decoration_type_value: int) -> void:
	_names.append(name)
	_temperature_centers.append(temp)
	_moisture_centers.append(wetness)
	_surface_blocks.append(surface)
	_subsurface_blocks.append(subsurface)
	_underwater_blocks.append(underwater)
	_soil_depths.append(soil_depth)
	_foliage_colors.append(foliage)
	_decoration_sets.append(decoration_set_value)
	_decoration_types.append(decoration_type_value)


func _safe_id(biome: int) -> int:
	return clampi(biome, 0, _names.size() - 1)
