## Immutable, data-driven decoration weights.  The populator owns placement;
## this catalog deliberately contains no scene or mutable random state.
class_name DecorationCatalog
extends RefCounted

const FEATURE_OAK: int = 1
const FEATURE_BIRCH: int = 2
const FEATURE_SPRUCE: int = 3
const FEATURE_ACACIA: int = 4
const FEATURE_JUNGLE: int = 5
const FEATURE_MANGROVE: int = 6
const FEATURE_CACTUS: int = 7
const FEATURE_TALL_GRASS: int = 8
const FEATURE_YELLOW_FLOWER: int = 9
const FEATURE_RED_FLOWER: int = 10
const FEATURE_DEAD_BUSH: int = 11
const FEATURE_BAMBOO: int = 12
const FEATURE_VINE: int = 13
const FEATURE_BOULDER: int = 14
const FEATURE_FALLEN_LOG: int = 15
const FEATURE_MELON: int = 16
const FEATURE_BROWN_MUSHROOM: int = 17
const FEATURE_RED_MUSHROOM: int = 18
## There is no separate reed block. The populator renders reeds using the
## tall-grass cross block, which is the closest supported registry asset.
const FEATURE_REEDS: int = 19
## A short leaf block cluster that sits between ground cover and trees.
const FEATURE_BUSH: int = 20
## Deliberate small props (as opposed to the random debris removed earlier).
const FEATURE_PEBBLE: int = 21
const FEATURE_ROCK_OUTCROP: int = 22
const FEATURE_STUMP: int = 23
const FEATURE_DEAD_TREE: int = 24
const FEATURE_LARGE_TREE: int = 25
const FEATURE_DRIFTWOOD: int = 26
## Grove interiors only: a tall old broadleaf that never appears in the
## ordinary species lottery.
const FEATURE_ANCIENT_TREE: int = 27
## Seabed species, used by VoxelPopulator._decorate_underwater().
const FEATURE_SEAGRASS: int = 28
const FEATURE_KELP: int = 29
const FEATURE_CORAL_FAN: int = 30
const FEATURE_CORAL_BRANCH: int = 31
const FEATURE_SPONGE: int = 32
const FEATURE_ANEMONE: int = 33

const FLAG_TREE: int = 1
const FLAG_WATER_EDGE: int = 2
const FLAG_DRY_GROUND: int = 4
const FLAG_SHADE: int = 8

var _sets: Dictionary = {}
## Underwater species tables, keyed by BiomeCatalog.DECORATION_*. The land
## lottery deliberately never reads these (it would stamp them on dry ground),
## so the seabed pass owns all water placement.
var _underwater_sets: Dictionary = {}


func _init() -> void:
	# Entries are [feature type, relative weight, independent occurrence chance,
	# placement flags]. The occurrence chance is multiplied by world settings.
	_sets = {
		BiomeCatalog.DECORATION_PLAINS: [
			[FEATURE_OAK, 8, 0.14, FLAG_TREE], [FEATURE_BIRCH, 2, 0.08, FLAG_TREE],
			[FEATURE_YELLOW_FLOWER, 18, 0.72, 0], [FEATURE_RED_FLOWER, 14, 0.66, 0],
			[FEATURE_BUSH, 6, 0.14, 0], [FEATURE_PEBBLE, 4, 0.06, 0], [FEATURE_MELON, 2, 0.04, 0],
		],
		BiomeCatalog.DECORATION_MEADOW: [
			[FEATURE_BIRCH, 4, 0.12, FLAG_TREE],
			[FEATURE_YELLOW_FLOWER, 30, 0.85, 0], [FEATURE_RED_FLOWER, 26, 0.82, 0],
			[FEATURE_BUSH, 8, 0.18, 0], [FEATURE_PEBBLE, 3, 0.05, 0],
		],
		BiomeCatalog.DECORATION_SAVANNA: [
			[FEATURE_ACACIA, 24, 0.40, FLAG_TREE], [FEATURE_DEAD_BUSH, 18, 0.44, 0],
			[FEATURE_TALL_GRASS, 28, 0.62, 0], [FEATURE_BUSH, 4, 0.10, 0],
			[FEATURE_PEBBLE, 4, 0.07, 0], [FEATURE_DEAD_TREE, 3, 0.06, 0],
		],
		BiomeCatalog.DECORATION_FOREST: [
			[FEATURE_OAK, 30, 0.44, FLAG_TREE], [FEATURE_BIRCH, 15, 0.30, FLAG_TREE],
			[FEATURE_LARGE_TREE, 7, 0.0, FLAG_TREE],
			[FEATURE_YELLOW_FLOWER, 5, 0.35, 0], [FEATURE_RED_FLOWER, 5, 0.35, 0],
			[FEATURE_BUSH, 10, 0.24, 0], [FEATURE_PEBBLE, 3, 0.05, 0],
			[FEATURE_FALLEN_LOG, 6, 0.14, 0], [FEATURE_STUMP, 5, 0.12, 0],
			[FEATURE_BROWN_MUSHROOM, 8, 0.40, FLAG_SHADE], [FEATURE_RED_MUSHROOM, 3, 0.20, FLAG_SHADE],
		],
		BiomeCatalog.DECORATION_DESERT: [
			[FEATURE_CACTUS, 24, 0.38, FLAG_DRY_GROUND], [FEATURE_DEAD_BUSH, 42, 0.62, FLAG_DRY_GROUND],
			[FEATURE_PEBBLE, 8, 0.16, FLAG_DRY_GROUND],
		],
		BiomeCatalog.DECORATION_SWAMP: [
			[FEATURE_MANGROVE, 28, 0.72, FLAG_TREE | FLAG_WATER_EDGE], [FEATURE_REEDS, 48, 0.90, FLAG_WATER_EDGE],
			[FEATURE_VINE, 20, 0.70, FLAG_WATER_EDGE], [FEATURE_BROWN_MUSHROOM, 8, 0.42, FLAG_SHADE],
			[FEATURE_RED_MUSHROOM, 4, 0.24, FLAG_SHADE], [FEATURE_DRIFTWOOD, 5, 0.14, FLAG_WATER_EDGE],
			[FEATURE_STUMP, 3, 0.10, 0],
		],
		BiomeCatalog.DECORATION_RIVERBANK: [
			[FEATURE_REEDS, 58, 0.92, FLAG_WATER_EDGE], [FEATURE_YELLOW_FLOWER, 8, 0.36, FLAG_WATER_EDGE],
			[FEATURE_RED_FLOWER, 6, 0.32, FLAG_WATER_EDGE], [FEATURE_DRIFTWOOD, 8, 0.20, FLAG_WATER_EDGE],
			[FEATURE_PEBBLE, 5, 0.12, FLAG_WATER_EDGE],
		],
		BiomeCatalog.DECORATION_BEACH: [
			[FEATURE_DRIFTWOOD, 12, 0.26, 0], [FEATURE_PEBBLE, 10, 0.22, 0],
			[FEATURE_REEDS, 8, 0.16, FLAG_WATER_EDGE],
		],
		BiomeCatalog.DECORATION_TROPICAL: [
			[FEATURE_JUNGLE, 34, 0.62, FLAG_TREE], [FEATURE_LARGE_TREE, 6, 0.0, FLAG_TREE],
			[FEATURE_BAMBOO, 28, 0.80, 0],
			[FEATURE_VINE, 22, 0.75, 0], [FEATURE_BUSH, 10, 0.22, 0], [FEATURE_MELON, 10, 0.30, 0],
			[FEATURE_FALLEN_LOG, 5, 0.12, 0], [FEATURE_STUMP, 4, 0.10, 0],
		],
		BiomeCatalog.DECORATION_TAIGA: [
			[FEATURE_SPRUCE, 48, 0.62, FLAG_TREE], [FEATURE_BUSH, 6, 0.16, 0],
			[FEATURE_BROWN_MUSHROOM, 10, 0.38, FLAG_SHADE], [FEATURE_RED_MUSHROOM, 4, 0.20, FLAG_SHADE],
			[FEATURE_STUMP, 6, 0.14, 0], [FEATURE_FALLEN_LOG, 6, 0.14, 0],
			[FEATURE_DEAD_TREE, 3, 0.07, 0], [FEATURE_PEBBLE, 3, 0.06, 0],
		],
		BiomeCatalog.DECORATION_SNOWFIELD: [
			[FEATURE_SPRUCE, 18, 0.20, FLAG_TREE],
			[FEATURE_ROCK_OUTCROP, 4, 0.10, 0], [FEATURE_PEBBLE, 4, 0.10, 0],
		],
		BiomeCatalog.DECORATION_BADLANDS: [
			[FEATURE_CACTUS, 20, 0.34, FLAG_DRY_GROUND], [FEATURE_DEAD_BUSH, 38, 0.56, FLAG_DRY_GROUND],
			[FEATURE_PEBBLE, 10, 0.20, FLAG_DRY_GROUND], [FEATURE_ROCK_OUTCROP, 6, 0.14, FLAG_DRY_GROUND],
			[FEATURE_DEAD_TREE, 3, 0.08, FLAG_DRY_GROUND],
		],
		BiomeCatalog.DECORATION_ALPINE: [
			[FEATURE_SPRUCE, 12, 0.18, FLAG_TREE],
			[FEATURE_ROCK_OUTCROP, 8, 0.18, 0], [FEATURE_PEBBLE, 6, 0.14, 0],
		],
	}
	# Entry shape matches the land sets: [feature, weight, chance, flags].
	_underwater_sets = {
		BiomeCatalog.DECORATION_SHELF: [
			[FEATURE_SEAGRASS, 30, 0.95, 0], [FEATURE_KELP, 10, 0.70, 0],
			[FEATURE_ANEMONE, 5, 0.35, 0],
		],
		BiomeCatalog.DECORATION_REEF: [
			[FEATURE_CORAL_FAN, 30, 0.95, 0], [FEATURE_CORAL_BRANCH, 26, 0.95, 0],
			[FEATURE_SEAGRASS, 22, 0.85, 0], [FEATURE_ANEMONE, 12, 0.70, 0],
			[FEATURE_SPONGE, 8, 0.55, 0],
		],
		BiomeCatalog.DECORATION_KELP: [
			[FEATURE_KELP, 42, 0.98, 0], [FEATURE_SEAGRASS, 14, 0.85, 0],
			[FEATURE_ANEMONE, 4, 0.40, 0],
		],
		BiomeCatalog.DECORATION_SEAGRASS: [
			[FEATURE_SEAGRASS, 50, 0.98, 0], [FEATURE_ANEMONE, 8, 0.50, 0],
			[FEATURE_CORAL_FAN, 5, 0.40, 0],
		],
		BiomeCatalog.DECORATION_ABYSSAL: [
			[FEATURE_ANEMONE, 8, 0.55, 0], [FEATURE_SPONGE, 4, 0.35, 0],
		],
		BiomeCatalog.DECORATION_FROZEN_SEA: [
			[FEATURE_SEAGRASS, 12, 0.65, 0], [FEATURE_ANEMONE, 3, 0.30, 0],
		],
	}


func entries_for_set(decoration_set: int) -> Array:
	return _sets.get(decoration_set, [])


func underwater_entries_for_set(decoration_set: int) -> Array:
	return _underwater_sets.get(decoration_set, [])


func choose_underwater(decoration_set: int, selector: float) -> Array:
	return _choose_from(underwater_entries_for_set(decoration_set), selector)


## Successful anchor cells per set: x = cell success chance, y/z = minimum and
## maximum plants stamped in that cell. Chances multiply world settings.
func underwater_density(decoration_set: int) -> Vector3:
	match decoration_set:
		BiomeCatalog.DECORATION_REEF:
			return Vector3(0.85, 3.0, 6.0)
		BiomeCatalog.DECORATION_KELP:
			return Vector3(0.65, 2.0, 4.0)
		BiomeCatalog.DECORATION_SEAGRASS:
			return Vector3(0.95, 3.0, 5.0)
		BiomeCatalog.DECORATION_SHELF:
			return Vector3(0.20, 1.0, 3.0)
		BiomeCatalog.DECORATION_ABYSSAL:
			return Vector3(0.06, 1.0, 1.0)
		BiomeCatalog.DECORATION_FROZEN_SEA:
			return Vector3(0.10, 1.0, 2.0)
	return Vector3.ZERO


## Tree groves choose their species separately from incidental decorations.
## Keeping this selection here preserves the catalog as the one source of
## species weights while allowing the populator to make trees spatially coherent.
func tree_entries_for_set(decoration_set: int) -> Array:
	var trees: Array = []
	for entry in entries_for_set(decoration_set):
		if (int(entry[3]) & FLAG_TREE) != 0:
			trees.append(entry)
	return trees


func choose_tree(decoration_set: int, selector: float) -> Array:
	return _choose_from(tree_entries_for_set(decoration_set), selector)


func choose_non_tree(decoration_set: int, selector: float) -> Array:
	var decorations: Array = []
	for entry in entries_for_set(decoration_set):
		if (int(entry[3]) & FLAG_TREE) == 0:
			decorations.append(entry)
	return _choose_from(decorations, selector)


## Ground cover is populated independently of the one-feature-per-cell lottery.
## A successful cover cell produces a 3-6 grass tuft over an 8x8 area, layered
## under flowers, bushes, and trees rather than carpeting every grass block.
func ground_cover_chance(decoration_set: int) -> float:
	match decoration_set:
		BiomeCatalog.DECORATION_PLAINS:
			return 0.90
		BiomeCatalog.DECORATION_SEAGRASS:
			return 0.96
		BiomeCatalog.DECORATION_SAVANNA:
			return 0.70
		BiomeCatalog.DECORATION_FOREST:
			return 0.70
		BiomeCatalog.DECORATION_TROPICAL:
			return 0.85
		BiomeCatalog.DECORATION_TAIGA:
			return 0.45
		BiomeCatalog.DECORATION_SWAMP:
			return 0.35
	return 0.0


func choose(decoration_set: int, selector: float) -> Array:
	return _choose_from(entries_for_set(decoration_set), selector)


func _choose_from(entries: Array, selector: float) -> Array:
	if entries.is_empty():
		return []
	var total_weight := 0
	for entry in entries:
		total_weight += int(entry[1])
	var target := clampf(selector, 0.0, 0.999999) * float(total_weight)
	var running := 0.0
	for entry in entries:
		running += float(entry[1])
		if target < running:
			return entry
	return entries[entries.size() - 1]
