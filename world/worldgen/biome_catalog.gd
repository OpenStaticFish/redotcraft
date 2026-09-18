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
## Underwater split. OCEAN/DEEP_OCEAN keep their original IDs so existing
## references and saved worlds stay valid; the climate/depth companions are
## appended. Selection lives in TerrainSampler._underwater_biome().
const KELP_FOREST: int = 15
const SEAGRASS_MEADOW: int = 16
const CORAL_REEF: int = 17
const FROZEN_OCEAN: int = 18
## Underground regions are appended to preserve every surface/ocean ID. They
## are classified in three dimensions and never participate in surface climate
## selection; VoxelPopulator uses them only on exposed cave surfaces.
const LUSH_CAVES: int = 19
const DEEP_DARK: int = 20
const DRIPSTONE_CAVES: int = 21
## V11 surface variants selected by the third climate channel. Appending keeps
## every persisted v1-v10 biome ID stable.
const SNOWY_TAIGA: int = 22
const WOODED_BADLANDS: int = 23
const STONY_SHORE: int = 24
const CAVE_BIOME_NONE: int = -1
## V1-v10 used these horizontal cells directly. V11 keeps their fixed global
## footprint, but samples their hashed corners as a continuous 3D field.
const CAVE_REGION_SIZE: int = 96
const CAVE_REGION_HEIGHT: int = 48
const CAVE_HASH_MAX: float = 2147483647.0

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
## Underwater species sets. The land lottery ignores these, so the sea keeps a
## decoration identity without stamping land features into water.
const DECORATION_SHELF: int = 17
const DECORATION_REEF: int = 18
const DECORATION_KELP: int = 19
const DECORATION_SEAGRASS: int = 20
const DECORATION_ABYSSAL: int = 21
const DECORATION_FROZEN_SEA: int = 22

const TYPE_NONE: int = 0
const TYPE_OAK: int = 1
const TYPE_BIRCH: int = 2
const TYPE_CACTUS: int = 3
const TYPE_REEDS: int = 4
const TYPE_JUNGLE_TREE: int = 5
const TYPE_ACACIA: int = 6
const TYPE_SPRUCE: int = 7
const TYPE_BOULDER: int = 8

## Waterline sediment stays depth-led so a sand beach never meets a different
## substrate at the waterline; the old biome-dither rule began gravel directly
## beside a beach.
const SHELF_SAND_DEPTH: int = 6

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
const BLOCK_CORAL_SUBSTRATE: int = 52
const BLOCK_MOSS: int = 62
const BLOCK_DEEPSTONE: int = 64
const BLOCK_SCULK: int = 65
const BLOCK_CALCITE: int = 66

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
	_add("shelf_sea", 0.52, 0.62, BLOCK_SAND, BLOCK_SAND, BLOCK_GRAVEL, 3, Color("#4b8797"), DECORATION_SHELF, TYPE_NONE)
	_add("deep_sea", 0.46, 0.65, BLOCK_GRAVEL, BLOCK_STONE, BLOCK_GRAVEL, 2, Color("#3e7185"), DECORATION_ABYSSAL, TYPE_NONE)
	_add("beach", 0.62, 0.45, BLOCK_SAND, BLOCK_SAND, BLOCK_SAND, 3, Color("#b9ac62"), DECORATION_BEACH, TYPE_NONE)
	_add("river", 0.50, 0.70, BLOCK_SAND, BLOCK_DIRT, BLOCK_GRAVEL, 2, Color("#548c6b"), DECORATION_RIVERBANK, TYPE_REEDS)
	_add("jungle", 0.74, 0.80, BLOCK_GRASS, BLOCK_DIRT, BLOCK_MUD, 4, Color("#3d8d36"), DECORATION_TROPICAL, TYPE_JUNGLE_TREE)
	_add("savanna", 0.72, 0.38, BLOCK_GRASS, BLOCK_DIRT, BLOCK_SAND, 3, Color("#94a343"), DECORATION_SAVANNA, TYPE_ACACIA)
	_add("taiga", 0.28, 0.62, BLOCK_GRASS, BLOCK_DIRT, BLOCK_GRAVEL, 4, Color("#426c4d"), DECORATION_TAIGA, TYPE_SPRUCE)
	_add("badlands", 0.82, 0.32, BLOCK_RED_SAND, BLOCK_TERRACOTTA, BLOCK_RED_SAND, 5, Color("#b76b3f"), DECORATION_BADLANDS, TYPE_CACTUS)
	_add("meadow", 0.46, 0.66, BLOCK_GRASS, BLOCK_DIRT, BLOCK_GRAVEL, 3, Color("#7fb65b"), DECORATION_MEADOW, TYPE_BIRCH)
	_add("highlands", 0.34, 0.46, BLOCK_STONE, BLOCK_STONE, BLOCK_GRAVEL, 2, Color("#6f8e5d"), DECORATION_ALPINE, TYPE_BOULDER)
	_add("kelp_forest", 0.32, 0.72, BLOCK_GRAVEL, BLOCK_STONE, BLOCK_GRAVEL, 2, Color("#3f6b5a"), DECORATION_KELP, TYPE_NONE)
	_add("seagrass_meadow", 0.58, 0.70, BLOCK_SAND, BLOCK_CLAY, BLOCK_SAND, 3, Color("#4f9c7a"), DECORATION_SEAGRASS, TYPE_NONE)
	_add("coral_reef", 0.74, 0.70, BLOCK_SAND, BLOCK_CLAY, BLOCK_SAND, 3, Color("#3fae9a"), DECORATION_REEF, TYPE_NONE)
	_add("frozen_sea", 0.08, 0.60, BLOCK_GRAVEL, BLOCK_STONE, BLOCK_GRAVEL, 2, Color("#9fc6d4"), DECORATION_FROZEN_SEA, TYPE_NONE)
	_add("lush_caves", 0.52, 1.0, BLOCK_MOSS, BLOCK_STONE, BLOCK_STONE, 2, Color("#67a855"), DECORATION_NONE, TYPE_NONE)
	_add("deep_dark", 0.18, 0.38, BLOCK_DEEPSTONE, BLOCK_SCULK, BLOCK_DEEPSTONE, 2, Color("#24525a"), DECORATION_NONE, TYPE_NONE)
	_add("dripstone_caves", 0.42, 0.35, BLOCK_CALCITE, BLOCK_STONE, BLOCK_STONE, 2, Color("#8f765d"), DECORATION_NONE, TYPE_NONE)
	_add("snowy_taiga", 0.22, 0.60, BLOCK_SNOW, BLOCK_DIRT, BLOCK_GRAVEL, 3, Color("#78958a"), DECORATION_TAIGA, TYPE_SPRUCE)
	_add("wooded_badlands", 0.76, 0.38, BLOCK_RED_SAND, BLOCK_TERRACOTTA, BLOCK_RED_SAND, 5, Color("#9f7045"), DECORATION_SAVANNA, TYPE_ACACIA)
	_add("stony_shore", 0.45, 0.48, BLOCK_GRAVEL, BLOCK_STONE, BLOCK_GRAVEL, 2, Color("#7d8978"), DECORATION_BEACH, TYPE_NONE)


func biome_count() -> int:
	return _names.size()


func name_for(biome: int) -> String:
	return _names[_safe_id(biome)]


func id_for_name(biome_name: String) -> int:
	for biome in _names.size():
		if _names[biome] == biome_name:
			return biome
	return PLAINS


## Every biome that classifies open water. Spawn search, cave entrances, and
## decoration exclusions share this so a new sea biome cannot be forgotten.
func is_ocean_biome(biome: int) -> bool:
	match _safe_id(biome):
		OCEAN, DEEP_OCEAN, KELP_FOREST, SEAGRASS_MEADOW, CORAL_REEF, FROZEN_OCEAN:
			return true
	return false


## Cold biomes fall as snow (not rain) and carry a wind ambience bed. The set
## is intentionally small and explicit so a new biome opts in rather than
## inheriting a guess from its temperature center. Static so the weather poll
## can classify a biome id without constructing a catalog.
static func is_cold_biome(biome: int) -> bool:
	match biome:
		SNOW, TAIGA, SNOWY_TAIGA, HIGHLANDS, FROZEN_OCEAN:
			return true
	return false


## Wetland biomes get low ground mist particles. Swamps are the only land
## biome with standing water and dense cover today.
static func is_wetland_biome(biome: int) -> bool:
	return biome == SWAMP


## Coherent 3D cave-region identity. Surface biomes remain a 2D climate layer;
## callers must additionally verify that the queried voxel is underground air.
## V1-v10 intentionally retain their exact column classifier for persisted
## worlds. V11 samples a stateless, global value-noise field, so labels change
## gradually across voxel and chunk boundaries rather than at cell edges.
static func cave_biome_at(seed: int, world_x: int, y: int, world_z: int,
		worldgen_version: int = 9) -> int:
	if y < 5 or y > 78:
		return CAVE_BIOME_NONE
	if worldgen_version <= 10:
		return _legacy_cave_biome_at(seed, world_x, y, world_z, worldgen_version)
	var region_value := cave_region_value_at(seed, world_x, y, world_z)
	var depth := clampf(float(78 - y) / 73.0, 0.0, 1.0)
	# Deep dark progressively recedes before the middle cave band, avoiding a
	# horizontal biome shelf while reserving the lowest caverns for sculk.
	var deep_dark_threshold := 0.38 * _smooth_curve(clampf(float(42 - y) / 37.0, 0.0, 1.0))
	# Damp lush regions are more common with depth. Dripstone occupies the
	# higher-valued portion of the same smooth field, with its upper limit also
	# varying by depth so it does not form a vertical column.
	var lush_threshold := 0.68 + depth * 0.12
	var dripstone_threshold := 0.87 + depth * 0.07
	if region_value < deep_dark_threshold:
		return DEEP_DARK
	if region_value < lush_threshold:
		return LUSH_CAVES
	if region_value < dripstone_threshold:
		return DRIPSTONE_CAVES
	return CAVE_BIOME_NONE


## Stateless 3D value noise used by v11+ cave classification. Exposing the
## scalar lets verification assert continuity without coupling to thresholds.
static func cave_region_value_at(seed: int, world_x: int, y: int, world_z: int) -> float:
	var cell_x := floori(float(world_x) / float(CAVE_REGION_SIZE))
	var cell_y := floori(float(y) / float(CAVE_REGION_HEIGHT))
	var cell_z := floori(float(world_z) / float(CAVE_REGION_SIZE))
	var x_fraction := float(world_x - cell_x * CAVE_REGION_SIZE) / float(CAVE_REGION_SIZE)
	var y_fraction := float(y - cell_y * CAVE_REGION_HEIGHT) / float(CAVE_REGION_HEIGHT)
	var z_fraction := float(world_z - cell_z * CAVE_REGION_SIZE) / float(CAVE_REGION_SIZE)
	var x_weight := _smooth_curve(x_fraction)
	var y_weight := _smooth_curve(y_fraction)
	var z_weight := _smooth_curve(z_fraction)
	var low_front := _lerp_cave_corners(seed, cell_x, cell_y, cell_z, x_weight, z_weight)
	var high_front := _lerp_cave_corners(seed, cell_x, cell_y + 1, cell_z, x_weight, z_weight)
	return lerpf(low_front, high_front, y_weight)


static func _legacy_cave_biome_at(seed: int, world_x: int, y: int, world_z: int,
		worldgen_version: int) -> int:
	var cell_x := floori(float(world_x) / float(CAVE_REGION_SIZE))
	var cell_z := floori(float(world_z) / float(CAVE_REGION_SIZE))
	var hash_value := _cave_hash(seed, cell_x, cell_z)
	var roll := hash_value % 100
	if worldgen_version <= 8:
		if y <= 34:
			if roll < 45:
				return DEEP_DARK
			if roll < 90:
				return LUSH_CAVES
		elif roll < 90:
			return LUSH_CAVES
		return CAVE_BIOME_NONE
	if y <= 34:
		if roll < 45:
			return DEEP_DARK
		if roll < 65:
			return DRIPSTONE_CAVES
		if roll < 90:
			return LUSH_CAVES
	else:
		if roll < 70:
			return LUSH_CAVES
		if roll < 90:
			return DRIPSTONE_CAVES
	return CAVE_BIOME_NONE


static func _lerp_cave_corners(seed: int, cell_x: int, cell_y: int, cell_z: int,
		x_weight: float, z_weight: float) -> float:
	var front_low := float(_cave_hash_3d(seed, cell_x, cell_y, cell_z)) / CAVE_HASH_MAX
	var front_high := float(_cave_hash_3d(seed, cell_x + 1, cell_y, cell_z)) / CAVE_HASH_MAX
	var back_low := float(_cave_hash_3d(seed, cell_x, cell_y, cell_z + 1)) / CAVE_HASH_MAX
	var back_high := float(_cave_hash_3d(seed, cell_x + 1, cell_y, cell_z + 1)) / CAVE_HASH_MAX
	return lerpf(lerpf(front_low, front_high, x_weight), lerpf(back_low, back_high, x_weight), z_weight)


static func _smooth_curve(value: float) -> float:
	return value * value * (3.0 - 2.0 * value)


static func is_cave_biome(biome: int) -> bool:
	return biome == LUSH_CAVES or biome == DEEP_DARK or biome == DRIPSTONE_CAVES


static func cave_surface_block(biome: int, selector: int = 0) -> int:
	if biome == LUSH_CAVES:
		return BLOCK_MOSS
	if biome == DEEP_DARK:
		return BLOCK_SCULK if selector % 5 == 0 else BLOCK_DEEPSTONE
	if biome == DRIPSTONE_CAVES:
		return BLOCK_CALCITE
	return BLOCK_STONE


static func cave_ambience_color(biome: int) -> Color:
	if biome == LUSH_CAVES:
		return Color("#315c3e")
	if biome == DEEP_DARK:
		return Color("#102b35")
	if biome == DRIPSTONE_CAVES:
		return Color("#59483b")
	return Color("#242936")


static func cave_display_name(biome: int) -> String:
	if biome == LUSH_CAVES:
		return "LUSH CAVES"
	if biome == DEEP_DARK:
		return "DEEP DARK"
	if biome == DRIPSTONE_CAVES:
		return "DRIPSTONE CAVES"
	return "CAVES"


static func _cave_hash(seed: int, x: int, z: int) -> int:
	var value: int = seed ^ (x * 73856093) ^ (z * 19349663) ^ 0x35A4D19
	value = ((value ^ (value >> 16)) * 0x45D9F3B) & 0x7fffffff
	value = ((value ^ (value >> 16)) * 0x45D9F3B) & 0x7fffffff
	return (value ^ (value >> 16)) & 0x7fffffff


static func _cave_hash_3d(seed: int, x: int, y: int, z: int) -> int:
	var value: int = seed ^ (x * 73856093) ^ (y * 83492791) ^ (z * 19349663) ^ 0x51EAD5B
	value = ((value ^ (value >> 16)) * 0x45D9F3B) & 0x7fffffff
	value = ((value ^ (value >> 16)) * 0x45D9F3B) & 0x7fffffff
	return (value ^ (value >> 16)) & 0x7fffffff


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


## Past the shelf edge each sea biome lays down its own sediment: living coral
## substrate, fine meadow silt, rocky kelp ground, and abyssal ooze. The
## waterline stays depth-led so a sand beach never meets a foreign substrate.
func seabed_block(biome: int, water_depth: int) -> int:
	var depth := maxi(water_depth, 0)
	if depth <= SHELF_SAND_DEPTH:
		return BLOCK_SAND
	match _safe_id(biome):
		CORAL_REEF:
			return BLOCK_SAND if depth <= 8 else BLOCK_CORAL_SUBSTRATE
		SEAGRASS_MEADOW:
			return BLOCK_SAND if depth <= 10 else BLOCK_CLAY
		KELP_FOREST:
			return BLOCK_GRAVEL
		FROZEN_OCEAN:
			return BLOCK_CLAY if depth <= 10 else BLOCK_GRAVEL
		DEEP_OCEAN:
			return BLOCK_CLAY
	if depth <= 11:
		return BLOCK_SAND
	if _safe_id(biome) == RIVER and depth <= 14:
		return BLOCK_CLAY
	return BLOCK_GRAVEL


## Substrate directly below the surface layer. Sedimentary seafloors keep a
## distinct buried layer (sand over clay, silt over gravel) so exposed seabed
## steps read as layered ground, while reef rock and kelp ground stay solid.
func seabed_subsurface(biome: int, water_depth: int) -> int:
	var depth := maxi(water_depth, 0)
	match _safe_id(biome):
		CORAL_REEF:
			return BLOCK_CORAL_SUBSTRATE
		KELP_FOREST:
			return BLOCK_STONE
		SEAGRASS_MEADOW:
			return BLOCK_CLAY
		FROZEN_OCEAN:
			return BLOCK_GRAVEL
		DEEP_OCEAN:
			return BLOCK_GRAVEL
		OCEAN:
			return BLOCK_CLAY if depth > SHELF_SAND_DEPTH else BLOCK_SAND
	return seabed_block(biome, water_depth)


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
		CORAL_REEF:
			return Color(0.68, 1.10, 1.02, 1.0)
		SEAGRASS_MEADOW:
			return Color(0.78, 1.06, 0.94, 1.0)
		KELP_FOREST:
			return Color(0.70, 0.96, 0.88, 1.0)
		FROZEN_OCEAN:
			return Color(0.80, 0.98, 1.18, 1.0)
		SWAMP:
			return Color(0.68, 0.86, 0.62, 1.0)
		RIVER:
			return Color(0.82, 1.04, 1.08, 1.0)
		SNOW, TAIGA, SNOWY_TAIGA:
			return Color(0.82, 1.02, 1.12, 1.0)
		DESERT, BADLANDS, WOODED_BADLANDS:
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
