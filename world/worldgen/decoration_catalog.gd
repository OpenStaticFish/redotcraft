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

const FLAG_TREE: int = 1
const FLAG_WATER_EDGE: int = 2
const FLAG_DRY_GROUND: int = 4
const FLAG_SHADE: int = 8

var _sets: Dictionary = {}


func _init() -> void:
	# Entries are [feature type, relative weight, independent occurrence chance,
	# placement flags]. The occurrence chance is multiplied by world settings.
	_sets = {
		BiomeCatalog.DECORATION_PLAINS: [
			[FEATURE_OAK, 8, 0.08, FLAG_TREE], [FEATURE_BIRCH, 2, 0.04, FLAG_TREE],
			[FEATURE_YELLOW_FLOWER, 18, 0.52, 0], [FEATURE_RED_FLOWER, 14, 0.46, 0],
			[FEATURE_MELON, 2, 0.04, 0],
		],
		BiomeCatalog.DECORATION_MEADOW: [
			[FEATURE_BIRCH, 4, 0.08, FLAG_TREE],
			[FEATURE_YELLOW_FLOWER, 30, 0.72, 0], [FEATURE_RED_FLOWER, 26, 0.68, 0],
		],
		BiomeCatalog.DECORATION_SAVANNA: [
			[FEATURE_ACACIA, 24, 0.30, FLAG_TREE], [FEATURE_DEAD_BUSH, 18, 0.34, 0],
			[FEATURE_TALL_GRASS, 28, 0.48, 0],
		],
		BiomeCatalog.DECORATION_FOREST: [
			[FEATURE_OAK, 30, 0.44, FLAG_TREE], [FEATURE_BIRCH, 15, 0.30, FLAG_TREE],
			[FEATURE_YELLOW_FLOWER, 5, 0.18, 0], [FEATURE_RED_FLOWER, 5, 0.18, 0],
			[FEATURE_BROWN_MUSHROOM, 8, 0.26, FLAG_SHADE], [FEATURE_RED_MUSHROOM, 3, 0.12, FLAG_SHADE],
		],
		BiomeCatalog.DECORATION_DESERT: [
			[FEATURE_CACTUS, 24, 0.38, FLAG_DRY_GROUND], [FEATURE_DEAD_BUSH, 42, 0.58, FLAG_DRY_GROUND],
		],
		BiomeCatalog.DECORATION_SWAMP: [
			[FEATURE_MANGROVE, 28, 0.72, FLAG_TREE | FLAG_WATER_EDGE], [FEATURE_REEDS, 48, 0.82, FLAG_WATER_EDGE],
			[FEATURE_VINE, 20, 0.52, FLAG_WATER_EDGE], [FEATURE_BROWN_MUSHROOM, 8, 0.28, FLAG_SHADE],
			[FEATURE_RED_MUSHROOM, 4, 0.16, FLAG_SHADE],
		],
		BiomeCatalog.DECORATION_RIVERBANK: [
			[FEATURE_REEDS, 58, 0.86, FLAG_WATER_EDGE], [FEATURE_YELLOW_FLOWER, 8, 0.24, FLAG_WATER_EDGE],
			[FEATURE_RED_FLOWER, 6, 0.20, FLAG_WATER_EDGE],
		],
		BiomeCatalog.DECORATION_TROPICAL: [
			[FEATURE_JUNGLE, 34, 0.62, FLAG_TREE], [FEATURE_BAMBOO, 28, 0.66, 0],
			[FEATURE_VINE, 22, 0.56, 0], [FEATURE_MELON, 10, 0.22, 0],
		],
		BiomeCatalog.DECORATION_TAIGA: [
			[FEATURE_SPRUCE, 48, 0.62, FLAG_TREE],
			[FEATURE_BROWN_MUSHROOM, 10, 0.24, FLAG_SHADE], [FEATURE_RED_MUSHROOM, 4, 0.12, FLAG_SHADE],
		],
		BiomeCatalog.DECORATION_SNOWFIELD: [
			[FEATURE_SPRUCE, 18, 0.12, FLAG_TREE],
		],
		BiomeCatalog.DECORATION_BADLANDS: [
			[FEATURE_CACTUS, 20, 0.34, FLAG_DRY_GROUND], [FEATURE_DEAD_BUSH, 38, 0.52, FLAG_DRY_GROUND],
		],
		BiomeCatalog.DECORATION_ALPINE: [
			[FEATURE_SPRUCE, 12, 0.10, FLAG_TREE],
		],
	}


func entries_for_set(decoration_set: int) -> Array:
	return _sets.get(decoration_set, [])


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
## Values are deliberately modest; a successful cover cell produces a 2-4 grass
## tuft over a 10x10 area rather than carpeting every grass block.
func ground_cover_chance(decoration_set: int) -> float:
	match decoration_set:
		BiomeCatalog.DECORATION_PLAINS:
			return 0.82
		BiomeCatalog.DECORATION_MEADOW:
			return 0.94
		BiomeCatalog.DECORATION_SAVANNA:
			return 0.58
		BiomeCatalog.DECORATION_FOREST:
			return 0.52
		BiomeCatalog.DECORATION_TROPICAL:
			return 0.72
		BiomeCatalog.DECORATION_TAIGA:
			return 0.30
		BiomeCatalog.DECORATION_SWAMP:
			return 0.24
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
