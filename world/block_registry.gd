class_name BlockRegistry
extends RefCounted

const BLOCK_AIR := 0
const BLOCK_GRASS := 1
const BLOCK_DIRT := 2
const BLOCK_STONE := 3
const BLOCK_COBBLESTONE := 4
const BLOCK_LOG := 5
const BLOCK_LEAVES := 6
const BLOCK_SAND := 7
const BLOCK_GLASS := 8
const BLOCK_GLOWSTONE := 9
const BLOCK_SNOW := 10
const BLOCK_BEDROCK := 11
const BLOCK_GRAVEL := 12
const BLOCK_COAL_ORE := 13
const BLOCK_IRON_ORE := 14
const BLOCK_GOLD_ORE := 15
const BLOCK_WATER := 16
const BLOCK_CLAY := 17
const BLOCK_MUD := 18
const BLOCK_RED_SAND := 19
const BLOCK_CACTUS := 20
const BLOCK_SPRUCE_LOG := 21
const BLOCK_SPRUCE_LEAVES := 22
const BLOCK_BIRCH_LOG := 23
const BLOCK_BIRCH_LEAVES := 24
const BLOCK_TERRACOTTA := 25
const BLOCK_MYCELIUM := 26
const BLOCK_TORCH := 27
const BLOCK_WATER_FLOW_7 := 28
const BLOCK_WATER_FLOW_6 := 29
const BLOCK_WATER_FLOW_5 := 30
const BLOCK_WATER_FLOW_4 := 31
const BLOCK_WATER_FLOW_3 := 32
const BLOCK_WATER_FLOW_2 := 33
const BLOCK_WATER_FLOW_1 := 34
const BLOCK_TALL_GRASS := 35
const BLOCK_YELLOW_FLOWER := 36
const BLOCK_RED_FLOWER := 37
const BLOCK_DEAD_BUSH := 38
const BLOCK_BAMBOO := 39
const BLOCK_VINE := 40
const BLOCK_ACACIA_LOG := 41
const BLOCK_ACACIA_LEAVES := 42
const BLOCK_JUNGLE_LOG := 43
const BLOCK_JUNGLE_LEAVES := 44
const BLOCK_MANGROVE_LOG := 45
const BLOCK_MANGROVE_LEAVES := 46
const BLOCK_MANGROVE_ROOTS := 47
const BLOCK_LAVA := 48
const BLOCK_BROWN_MUSHROOM := 49
const BLOCK_RED_MUSHROOM := 50
const BLOCK_MELON := 51
const BLOCK_CORAL_SUBSTRATE := 52
const BLOCK_SEAGRASS := 53
const BLOCK_KELP := 54
const BLOCK_CORAL_FAN := 55
const BLOCK_CORAL_BRANCH := 56
const BLOCK_SPONGE := 57
const BLOCK_ANEMONE := 58
const BLOCK_TNT := 59
const BLOCK_NUKE := 60
const BLOCK_DRIPSTONE := 61
const BLOCK_MOSS := 62
const BLOCK_CAVE_MOSS := 63
const BLOCK_DEEPSTONE := 64
const BLOCK_SCULK := 65
const BLOCK_CALCITE := 66
const BLOCK_GEODE_SHELL := 67
const BLOCK_AMETHYST := 68
const BLOCK_CRYSTAL_BUD := 69
const BLOCK_FIRE := 70
const BLOCK_CRAFTING_TABLE := 71
const BLOCK_CHEST := 72
const BLOCK_FURNACE := 73
const BLOCK_PLANKS := 74

## State-backed wooden building blocks. IDs 0..74 are part of the persistent
## world format and must never move. The first ID in each group is the item and
## canonical block ID; the remaining IDs are voxel-only placement states.
const BLOCK_WOOD_STAIRS := 75
const BLOCK_WOOD_STAIRS_EAST := 76
const BLOCK_WOOD_STAIRS_SOUTH := 77
const BLOCK_WOOD_STAIRS_WEST := 78
const BLOCK_WOOD_SLAB := 79
const BLOCK_WOOD_SLAB_TOP := 80
const BLOCK_WOOD_DOOR := 81
const BLOCK_WOOD_DOOR_LAST := 96
const BLOCK_WOOD_LADDER := 97
const BLOCK_WOOD_LADDER_LAST := 100
const BLOCK_WOOD_SIGN := 101
const BLOCK_WOOD_SIGN_LAST := 104
const BLOCK_WOOD_BED := 105
const BLOCK_WOOD_BED_LAST := 108

const FACING_NORTH := 0
const FACING_EAST := 1
const FACING_SOUTH := 2
const FACING_WEST := 3

const SHAPE_CUBE := 0
const SHAPE_STAIRS := 1
const SHAPE_SLAB := 2
const SHAPE_DOOR := 3
const SHAPE_LADDER := 4
const SHAPE_SIGN := 5
const SHAPE_BED := 6

const FLAG_OPAQUE := 1
const FLAG_CUTOUT := 2
const FLAG_UNBREAKABLE := 4
const FLAG_LEAVES := 8
const FLAG_EMISSIVE := 16
const FLAG_CROSS := 32
const FLAG_TINTED := 64
## Burnable fuel for the fire simulation. Logs, leaves, and dry plants carry it;
## the flag is independent of opacity so burning a tree can cascade through
## both its trunk and its canopy.
const FLAG_FLAMMABLE := 128

## Rows: id, name, top, side, bottom, flags, hardness, preferred tool, required tier.
const BLOCK_DEFS := [
	[0, "AIR", "", "", "", 0, -1.0, "", 0],
	[1, "GRASS", "grass_top.png", "grass_side.png", "dirt.png", FLAG_OPAQUE | FLAG_TINTED, 0.6, "shovel", 0],
	[2, "DIRT", "dirt.png", "dirt.png", "dirt.png", FLAG_OPAQUE, 0.5, "shovel", 0],
	[3, "STONE", "stone.png", "stone.png", "stone.png", FLAG_OPAQUE, 1.5, "pickaxe", 1],
	[4, "COBBLESTONE", "cobblestone.png", "cobblestone.png", "cobblestone.png", FLAG_OPAQUE, 2.0, "pickaxe", 1],
	[5, "OAK LOG", "wood_top.png", "wood_side.png", "wood_top.png", FLAG_OPAQUE | FLAG_FLAMMABLE, 2.0, "axe", 0],
	[6, "OAK LEAVES", "leaves.png", "leaves.png", "leaves.png", FLAG_CUTOUT | FLAG_LEAVES | FLAG_TINTED | FLAG_FLAMMABLE, 0.2, "axe", 0],
	[7, "SAND", "sand.png", "sand.png", "sand.png", FLAG_OPAQUE, 0.5, "shovel", 0],
	[8, "GLASS", "glass.png", "glass.png", "glass.png", FLAG_CUTOUT, 0.3, "", 0],
	[9, "GLOWSTONE", "glowstone.png", "glowstone.png", "glowstone.png", FLAG_OPAQUE | FLAG_EMISSIVE, 0.3, "pickaxe", 0],
	[10, "SNOW", "snow_block.png", "snow_block.png", "snow_block.png", FLAG_OPAQUE, 0.2, "shovel", 0],
	[11, "BEDROCK", "bedrock.png", "bedrock.png", "bedrock.png", FLAG_OPAQUE | FLAG_UNBREAKABLE, -1.0, "", 0],
	[12, "GRAVEL", "gravel.png", "gravel.png", "gravel.png", FLAG_OPAQUE, 0.6, "shovel", 0],
	[13, "COAL ORE", "coal_ore.png", "coal_ore.png", "coal_ore.png", FLAG_OPAQUE, 3.0, "pickaxe", 1],
	[14, "IRON ORE", "iron_ore.png", "iron_ore.png", "iron_ore.png", FLAG_OPAQUE, 3.0, "pickaxe", 2],
	[15, "GOLD ORE", "gold_ore.png", "gold_ore.png", "gold_ore.png", FLAG_OPAQUE, 3.0, "pickaxe", 3],
	[16, "WATER", "water.png", "water.png", "water.png", 0, -1.0, "", 0],
	[17, "CLAY", "clay.png", "clay.png", "clay.png", FLAG_OPAQUE, 0.6, "shovel", 0],
	[18, "MUD", "mud.png", "mud.png", "mud.png", FLAG_OPAQUE, 0.5, "shovel", 0],
	[19, "RED SAND", "red_sand.png", "red_sand.png", "red_sand.png", FLAG_OPAQUE, 0.5, "shovel", 0],
	[20, "CACTUS", "cactus_top.png", "cactus_side.png", "cactus_top.png", FLAG_OPAQUE, 0.4, "axe", 0],
	[21, "SPRUCE LOG", "spruce_log_top.png", "spruce_log_side.png", "spruce_log_top.png", FLAG_OPAQUE | FLAG_FLAMMABLE, 2.0, "axe", 0],
	[22, "SPRUCE LEAVES", "spruce_leaves.png", "spruce_leaves.png", "spruce_leaves.png", FLAG_CUTOUT | FLAG_LEAVES | FLAG_TINTED | FLAG_FLAMMABLE, 0.2, "axe", 0],
	[23, "BIRCH LOG", "birch_log_top.png", "birch_log_side.png", "birch_log_top.png", FLAG_OPAQUE | FLAG_FLAMMABLE, 2.0, "axe", 0],
	[24, "BIRCH LEAVES", "birch_leaves.png", "birch_leaves.png", "birch_leaves.png", FLAG_CUTOUT | FLAG_LEAVES | FLAG_TINTED | FLAG_FLAMMABLE, 0.2, "axe", 0],
	[25, "TERRACOTTA", "terracotta.png", "terracotta.png", "terracotta.png", FLAG_OPAQUE, 1.25, "pickaxe", 1],
	[26, "MYCELIUM", "mycelium_top.png", "mycelium_side.png", "dirt.png", FLAG_OPAQUE, 0.6, "shovel", 0],
	[27, "TORCH", "torch.png", "torch.png", "torch.png", FLAG_CUTOUT | FLAG_CROSS | FLAG_EMISSIVE, 0.0, "", 0],
	[28, "WATER FLOW 7", "water.png", "water.png", "water.png", 0, -1.0, "", 0],
	[29, "WATER FLOW 6", "water.png", "water.png", "water.png", 0, -1.0, "", 0],
	[30, "WATER FLOW 5", "water.png", "water.png", "water.png", 0, -1.0, "", 0],
	[31, "WATER FLOW 4", "water.png", "water.png", "water.png", 0, -1.0, "", 0],
	[32, "WATER FLOW 3", "water.png", "water.png", "water.png", 0, -1.0, "", 0],
	[33, "WATER FLOW 2", "water.png", "water.png", "water.png", 0, -1.0, "", 0],
	[34, "WATER FLOW 1", "water.png", "water.png", "water.png", 0, -1.0, "", 0],
	[35, "TALL GRASS", "tall_grass.png", "tall_grass.png", "tall_grass.png", FLAG_CUTOUT | FLAG_CROSS | FLAG_TINTED | FLAG_FLAMMABLE, 0.0, "", 0],
	[36, "YELLOW FLOWER", "flower_yellow.png", "flower_yellow.png", "flower_yellow.png", FLAG_CUTOUT | FLAG_CROSS | FLAG_FLAMMABLE, 0.0, "", 0],
	[37, "RED FLOWER", "flower_red.png", "flower_red.png", "flower_red.png", FLAG_CUTOUT | FLAG_CROSS | FLAG_FLAMMABLE, 0.0, "", 0],
	[38, "DEAD BUSH", "dead_bush.png", "dead_bush.png", "dead_bush.png", FLAG_CUTOUT | FLAG_CROSS | FLAG_FLAMMABLE, 0.0, "", 0],
	[39, "BAMBOO", "bamboo.png", "bamboo.png", "bamboo.png", FLAG_CUTOUT | FLAG_CROSS | FLAG_TINTED | FLAG_FLAMMABLE, 1.0, "axe", 0],
	[40, "VINE", "vine.png", "vine.png", "vine.png", FLAG_CUTOUT | FLAG_CROSS | FLAG_TINTED | FLAG_FLAMMABLE, 0.2, "axe", 0],
	[41, "ACACIA LOG", "acacia_log_top.png", "acacia_log_side.png", "acacia_log_top.png", FLAG_OPAQUE | FLAG_FLAMMABLE, 2.0, "axe", 0],
	[42, "ACACIA LEAVES", "acacia_leaves.png", "acacia_leaves.png", "acacia_leaves.png", FLAG_CUTOUT | FLAG_LEAVES | FLAG_TINTED | FLAG_FLAMMABLE, 0.2, "axe", 0],
	[43, "JUNGLE LOG", "jungle_log_top.png", "jungle_log_side.png", "jungle_log_top.png", FLAG_OPAQUE | FLAG_FLAMMABLE, 2.0, "axe", 0],
	[44, "JUNGLE LEAVES", "jungle_leaves.png", "jungle_leaves.png", "jungle_leaves.png", FLAG_CUTOUT | FLAG_LEAVES | FLAG_TINTED | FLAG_FLAMMABLE, 0.2, "axe", 0],
	[45, "MANGROVE LOG", "mangrove_log_top.png", "mangrove_log_side.png", "mangrove_log_top.png", FLAG_OPAQUE | FLAG_FLAMMABLE, 2.0, "axe", 0],
	[46, "MANGROVE LEAVES", "mangrove_leaves.png", "mangrove_leaves.png", "mangrove_leaves.png", FLAG_CUTOUT | FLAG_LEAVES | FLAG_TINTED | FLAG_FLAMMABLE, 0.2, "axe", 0],
	[47, "MANGROVE ROOTS", "mangrove_roots.png", "mangrove_roots.png", "mangrove_roots.png", FLAG_OPAQUE | FLAG_FLAMMABLE, 0.7, "axe", 0],
	[48, "LAVA", "lava.png", "lava.png", "lava.png", FLAG_OPAQUE | FLAG_EMISSIVE, 1.0, "pickaxe", 0],
	[49, "BROWN MUSHROOM", "brown_mushroom_block.png", "brown_mushroom_block.png", "mushroom_stem.png", FLAG_CUTOUT | FLAG_CROSS | FLAG_FLAMMABLE, 0.0, "", 0],
	[50, "RED MUSHROOM", "red_mushroom_block.png", "red_mushroom_block.png", "mushroom_stem.png", FLAG_CUTOUT | FLAG_CROSS | FLAG_FLAMMABLE, 0.0, "", 0],
	[51, "MELON", "melon_top.png", "melon_side.png", "melon_side.png", FLAG_OPAQUE | FLAG_FLAMMABLE, 1.0, "axe", 0],
	[52, "CORAL SUBSTRATE", "coral_substrate.png", "coral_substrate.png", "coral_substrate.png", FLAG_OPAQUE, 1.5, "pickaxe", 1],
	[53, "SEAGRASS", "seagrass.png", "seagrass.png", "seagrass.png", FLAG_CUTOUT | FLAG_CROSS, 0.0, "", 0],
	[54, "KELP", "kelp.png", "kelp.png", "kelp.png", FLAG_CUTOUT | FLAG_CROSS, 0.0, "", 0],
	[55, "CORAL FAN", "coral_fan.png", "coral_fan.png", "coral_fan.png", FLAG_CUTOUT | FLAG_CROSS, 0.0, "", 0],
	[56, "CORAL BRANCH", "coral_branch.png", "coral_branch.png", "coral_branch.png", FLAG_CUTOUT | FLAG_CROSS, 0.0, "", 0],
	[57, "SPONGE", "sponge.png", "sponge.png", "sponge.png", FLAG_OPAQUE, 0.6, "", 0],
	[58, "ANEMONE", "anemone.png", "anemone.png", "anemone.png", FLAG_CUTOUT | FLAG_CROSS, 0.0, "", 0],
	[59, "TNT", "tnt_top.png", "tnt_side.png", "tnt_bottom.png", FLAG_OPAQUE, 0.0, "", 0],
	[60, "NUKE", "nuke_top.png", "nuke_side.png", "nuke_bottom.png", FLAG_OPAQUE, 0.0, "", 0],
	[61, "DRIPSTONE", "dripstone.png", "dripstone.png", "dripstone.png", FLAG_OPAQUE, 1.5, "pickaxe", 1],
	[62, "MOSS", "moss.png", "moss.png", "moss.png", FLAG_OPAQUE, 0.1, "shovel", 0],
	[63, "CAVE MOSS", "cave_moss.png", "cave_moss.png", "cave_moss.png", FLAG_CUTOUT | FLAG_CROSS, 0.0, "", 0],
	[64, "DEEPSTONE", "deepstone.png", "deepstone.png", "deepstone.png", FLAG_OPAQUE, 3.0, "pickaxe", 1],
	[65, "SCULK", "sculk.png", "sculk.png", "sculk.png", FLAG_OPAQUE | FLAG_EMISSIVE, 0.2, "", 0],
	[66, "CALCITE", "calcite.png", "calcite.png", "calcite.png", FLAG_OPAQUE, 0.75, "pickaxe", 1],
	[67, "GEODE SHELL", "geode_shell.png", "geode_shell.png", "geode_shell.png", FLAG_OPAQUE, 1.5, "pickaxe", 1],
	[68, "AMETHYST", "amethyst.png", "amethyst.png", "amethyst.png", FLAG_OPAQUE | FLAG_EMISSIVE, 1.5, "pickaxe", 1],
	[69, "CRYSTAL BUD", "crystal_bud.png", "crystal_bud.png", "crystal_bud.png", FLAG_CUTOUT | FLAG_CROSS | FLAG_EMISSIVE, 1.5, "pickaxe", 1],
	[70, "FIRE", "fire.png", "fire.png", "fire.png", FLAG_CUTOUT | FLAG_CROSS | FLAG_EMISSIVE, 0.0, "", 0],
	[71, "CRAFTING TABLE", "crafting_top.png", "crafting_side.png", "crafting_bottom.png", FLAG_OPAQUE | FLAG_FLAMMABLE, 2.5, "axe", 0],
	[72, "CHEST", "chest_top.png", "chest_side.png", "chest_bottom.png", FLAG_OPAQUE | FLAG_FLAMMABLE, 2.5, "axe", 0],
	[73, "FURNACE", "furnace_top.png", "furnace_side.png", "furnace_bottom.png", FLAG_OPAQUE, 3.5, "pickaxe", 1],
	[74, "PLANKS", "planks.png", "planks.png", "planks.png", FLAG_OPAQUE | FLAG_FLAMMABLE, 2.0, "axe", 0],
	[75, "WOOD STAIRS", "planks.png", "planks.png", "planks.png", FLAG_FLAMMABLE, 2.0, "axe", 0],
	[76, "WOOD STAIRS EAST", "planks.png", "planks.png", "planks.png", FLAG_FLAMMABLE, 2.0, "axe", 0],
	[77, "WOOD STAIRS SOUTH", "planks.png", "planks.png", "planks.png", FLAG_FLAMMABLE, 2.0, "axe", 0],
	[78, "WOOD STAIRS WEST", "planks.png", "planks.png", "planks.png", FLAG_FLAMMABLE, 2.0, "axe", 0],
	[79, "WOOD SLAB", "planks.png", "planks.png", "planks.png", FLAG_FLAMMABLE, 2.0, "axe", 0],
	[80, "WOOD SLAB TOP", "planks.png", "planks.png", "planks.png", FLAG_FLAMMABLE, 2.0, "axe", 0],
	[81, "WOOD DOOR", "door_lower.png", "door_lower.png", "door_lower.png", FLAG_FLAMMABLE, 2.0, "axe", 0],
	[82, "WOOD DOOR EAST", "door_lower.png", "door_lower.png", "door_lower.png", FLAG_FLAMMABLE, 2.0, "axe", 0],
	[83, "WOOD DOOR SOUTH", "door_lower.png", "door_lower.png", "door_lower.png", FLAG_FLAMMABLE, 2.0, "axe", 0],
	[84, "WOOD DOOR WEST", "door_lower.png", "door_lower.png", "door_lower.png", FLAG_FLAMMABLE, 2.0, "axe", 0],
	[85, "WOOD DOOR OPEN", "door_lower.png", "door_lower.png", "door_lower.png", FLAG_FLAMMABLE, 2.0, "axe", 0],
	[86, "WOOD DOOR EAST OPEN", "door_lower.png", "door_lower.png", "door_lower.png", FLAG_FLAMMABLE, 2.0, "axe", 0],
	[87, "WOOD DOOR SOUTH OPEN", "door_lower.png", "door_lower.png", "door_lower.png", FLAG_FLAMMABLE, 2.0, "axe", 0],
	[88, "WOOD DOOR WEST OPEN", "door_lower.png", "door_lower.png", "door_lower.png", FLAG_FLAMMABLE, 2.0, "axe", 0],
	[89, "WOOD DOOR UPPER", "door_upper.png", "door_upper.png", "door_upper.png", FLAG_FLAMMABLE, 2.0, "axe", 0],
	[90, "WOOD DOOR EAST UPPER", "door_upper.png", "door_upper.png", "door_upper.png", FLAG_FLAMMABLE, 2.0, "axe", 0],
	[91, "WOOD DOOR SOUTH UPPER", "door_upper.png", "door_upper.png", "door_upper.png", FLAG_FLAMMABLE, 2.0, "axe", 0],
	[92, "WOOD DOOR WEST UPPER", "door_upper.png", "door_upper.png", "door_upper.png", FLAG_FLAMMABLE, 2.0, "axe", 0],
	[93, "WOOD DOOR OPEN UPPER", "door_upper.png", "door_upper.png", "door_upper.png", FLAG_FLAMMABLE, 2.0, "axe", 0],
	[94, "WOOD DOOR EAST OPEN UPPER", "door_upper.png", "door_upper.png", "door_upper.png", FLAG_FLAMMABLE, 2.0, "axe", 0],
	[95, "WOOD DOOR SOUTH OPEN UPPER", "door_upper.png", "door_upper.png", "door_upper.png", FLAG_FLAMMABLE, 2.0, "axe", 0],
	[96, "WOOD DOOR WEST OPEN UPPER", "door_upper.png", "door_upper.png", "door_upper.png", FLAG_FLAMMABLE, 2.0, "axe", 0],
	[97, "WOOD LADDER", "ladder.png", "ladder.png", "ladder.png", FLAG_FLAMMABLE, 1.0, "axe", 0],
	[98, "WOOD LADDER EAST", "ladder.png", "ladder.png", "ladder.png", FLAG_FLAMMABLE, 1.0, "axe", 0],
	[99, "WOOD LADDER SOUTH", "ladder.png", "ladder.png", "ladder.png", FLAG_FLAMMABLE, 1.0, "axe", 0],
	[100, "WOOD LADDER WEST", "ladder.png", "ladder.png", "ladder.png", FLAG_FLAMMABLE, 1.0, "axe", 0],
	[101, "WOOD SIGN", "sign.png", "sign.png", "sign.png", FLAG_FLAMMABLE, 1.0, "axe", 0],
	[102, "WOOD SIGN EAST", "sign.png", "sign.png", "sign.png", FLAG_FLAMMABLE, 1.0, "axe", 0],
	[103, "WOOD SIGN SOUTH", "sign.png", "sign.png", "sign.png", FLAG_FLAMMABLE, 1.0, "axe", 0],
	[104, "WOOD SIGN WEST", "sign.png", "sign.png", "sign.png", FLAG_FLAMMABLE, 1.0, "axe", 0],
	[105, "WOOD BED", "bed_top.png", "bed_side.png", "bed_bottom.png", FLAG_FLAMMABLE, 0.2, "axe", 0],
	[106, "WOOD BED EAST", "bed_top.png", "bed_side.png", "bed_bottom.png", FLAG_FLAMMABLE, 0.2, "axe", 0],
	[107, "WOOD BED SOUTH", "bed_top.png", "bed_side.png", "bed_bottom.png", FLAG_FLAMMABLE, 0.2, "axe", 0],
	[108, "WOOD BED WEST", "bed_top.png", "bed_side.png", "bed_bottom.png", FLAG_FLAMMABLE, 0.2, "axe", 0],
]

const TEXTURE_ROOT := "res://assets/placeholders/zigcraft/default/"
## RedotCraft-generated placeholders live beside the copied ZigCraft set so the
## upstream directory stays an unmodified copy.
const UNDERWATER_TEXTURE_ROOT := "res://assets/placeholders/underwater/"
const EXPLOSIVE_TEXTURE_ROOT := "res://assets/placeholders/explosives/"
const CAVE_TEXTURE_ROOT := "res://assets/placeholders/caves/"
const FIRE_TEXTURE_ROOT := "res://assets/placeholders/fire/"
const FUNCTIONAL_TEXTURE_ROOT := "res://assets/placeholders/functional/"
const EXTRA_TEXTURE_PATHS := {
	"crafting_top.png": FUNCTIONAL_TEXTURE_ROOT + "crafting_top.png",
	"crafting_side.png": FUNCTIONAL_TEXTURE_ROOT + "crafting_side.png",
	"crafting_bottom.png": FUNCTIONAL_TEXTURE_ROOT + "crafting_bottom.png",
	"chest_top.png": FUNCTIONAL_TEXTURE_ROOT + "chest_top.png",
	"chest_side.png": FUNCTIONAL_TEXTURE_ROOT + "chest_side.png",
	"chest_bottom.png": FUNCTIONAL_TEXTURE_ROOT + "chest_bottom.png",
	"furnace_top.png": FUNCTIONAL_TEXTURE_ROOT + "furnace_top.png",
	"furnace_side.png": FUNCTIONAL_TEXTURE_ROOT + "furnace_side.png",
	"furnace_bottom.png": FUNCTIONAL_TEXTURE_ROOT + "furnace_bottom.png",
	"door_lower.png": FUNCTIONAL_TEXTURE_ROOT + "door_lower.png",
	"door_upper.png": FUNCTIONAL_TEXTURE_ROOT + "door_upper.png",
	"ladder.png": FUNCTIONAL_TEXTURE_ROOT + "ladder.png",
	"sign.png": FUNCTIONAL_TEXTURE_ROOT + "sign.png",
	"bed_top.png": FUNCTIONAL_TEXTURE_ROOT + "bed_top.png",
	"bed_side.png": FUNCTIONAL_TEXTURE_ROOT + "bed_side.png",
	"bed_bottom.png": FUNCTIONAL_TEXTURE_ROOT + "bed_bottom.png",
	"coral_substrate.png": UNDERWATER_TEXTURE_ROOT + "coral_substrate.png",
	"seagrass.png": UNDERWATER_TEXTURE_ROOT + "seagrass.png",
	"kelp.png": UNDERWATER_TEXTURE_ROOT + "kelp.png",
	"coral_fan.png": UNDERWATER_TEXTURE_ROOT + "coral_fan.png",
	"coral_branch.png": UNDERWATER_TEXTURE_ROOT + "coral_branch.png",
	"sponge.png": UNDERWATER_TEXTURE_ROOT + "sponge.png",
	"anemone.png": UNDERWATER_TEXTURE_ROOT + "anemone.png",
	"tnt_top.png": EXPLOSIVE_TEXTURE_ROOT + "tnt_top.png",
	"tnt_side.png": EXPLOSIVE_TEXTURE_ROOT + "tnt_side.png",
	"tnt_bottom.png": EXPLOSIVE_TEXTURE_ROOT + "tnt_bottom.png",
	"nuke_top.png": EXPLOSIVE_TEXTURE_ROOT + "nuke_top.png",
	"nuke_side.png": EXPLOSIVE_TEXTURE_ROOT + "nuke_side.png",
	"nuke_bottom.png": EXPLOSIVE_TEXTURE_ROOT + "nuke_bottom.png",
	"dripstone.png": CAVE_TEXTURE_ROOT + "dripstone.png",
	"moss.png": CAVE_TEXTURE_ROOT + "moss.png",
	"cave_moss.png": CAVE_TEXTURE_ROOT + "cave_moss.png",
	"deepstone.png": CAVE_TEXTURE_ROOT + "deepstone.png",
	"sculk.png": CAVE_TEXTURE_ROOT + "sculk.png",
	"calcite.png": CAVE_TEXTURE_ROOT + "calcite.png",
	"geode_shell.png": CAVE_TEXTURE_ROOT + "geode_shell.png",
	"amethyst.png": CAVE_TEXTURE_ROOT + "amethyst.png",
	"crystal_bud.png": CAVE_TEXTURE_ROOT + "crystal_bud.png",
	"fire.png": FIRE_TEXTURE_ROOT + "fire.png",
}
const WATER_TEXTURE_PATH := TEXTURE_ROOT + "water.png"
const WATER_SHADER_PATH := "res://assets/placeholders/zigcraft/water.gdshader"
const BLOCK_SHADER_PATH := "res://world/block.gdshader"
const TILE_PX := 64
# These placeholder images include transparent margins for an inset cactus
# model. Our cactus is an opaque cube: map its solid body across each face,
# otherwise the shared cutout shader opens slits along every cube edge.
const SOLID_TEXTURE_REGIONS := {
	"cactus_side.png": Rect2i(4, 0, 56, 64),
	"cactus_top.png": Rect2i(4, 4, 56, 56),
}
const MAX_LIGHT_LEVEL := 15
const EMISSIVE_COLORS := {
	BLOCK_GLOWSTONE: Color(1.0, 0.78, 0.52),
	BLOCK_TORCH: Color(0.93, 0.68, 0.44),
	BLOCK_LAVA: Color(1.0, 0.3, 0.06),
	BLOCK_SCULK: Color(0.08, 0.34, 0.42),
	BLOCK_AMETHYST: Color(0.48, 0.24, 0.72),
	BLOCK_CRYSTAL_BUD: Color(0.72, 0.42, 1.0),
	BLOCK_FIRE: Color(1.0, 0.55, 0.14),
}
const ATTENUATION_LEAVES := 3
# Light drops 3 per water block so sky light stops fading in within ~5 blocks of
# the surface; at 2 the shallow ocean banks stayed near-white and read as
# glowing "fins" against the dark abyssal floor.
const ATTENUATION_WATER := 3
const TEXTURE_TINTS := {
	"grass_top.png": Color(0.44, 0.84, 0.34),
	"leaves.png": Color(0.62, 1.15, 0.5),
	"spruce_leaves.png": Color(0.5, 1.05, 0.6),
	"birch_leaves.png": Color(0.78, 1.3, 0.55),
	"tall_grass.png": Color(0.5, 0.95, 0.38),
	"vine.png": Color(0.45, 0.9, 0.36),
	"acacia_leaves.png": Color(0.8, 1.12, 0.5),
	"jungle_leaves.png": Color(0.52, 1.08, 0.45),
	"mangrove_leaves.png": Color(0.55, 0.9, 0.48),
	"mycelium_top.png": Color(0.82, 0.68, 0.9),
	"sand.png": Color(0.98, 0.9, 0.64),
	"red_sand.png": Color(1.0, 0.84, 0.72),
}

var material: Material
var water_material: Material
var texture_array: Texture2DArray

var _flags: PackedByteArray = PackedByteArray()
var _opaque: PackedByteArray = PackedByteArray()
var _layer_top: PackedInt32Array = PackedInt32Array()
var _layer_side: PackedInt32Array = PackedInt32Array()
var _layer_bottom: PackedInt32Array = PackedInt32Array()
var _names: PackedStringArray = PackedStringArray()
var _fire_layer := -1


func _init() -> void:
	var tile_lookup := _build_texture_array()
	_build_block_tables(tile_lookup)
	_load_water_material()


static func shape_type(block_id: int) -> int:
	if block_id >= BLOCK_WOOD_STAIRS and block_id <= BLOCK_WOOD_STAIRS_WEST:
		return SHAPE_STAIRS
	if block_id >= BLOCK_WOOD_SLAB and block_id <= BLOCK_WOOD_SLAB_TOP:
		return SHAPE_SLAB
	if is_door(block_id):
		return SHAPE_DOOR
	if is_ladder(block_id):
		return SHAPE_LADDER
	if is_sign(block_id):
		return SHAPE_SIGN
	if is_bed(block_id):
		return SHAPE_BED
	return SHAPE_CUBE


## Horizontal state direction. Non-directional blocks deliberately resolve to
## north so callers can use one helper for every placeable block.
static func facing(block_id: int) -> int:
	if block_id >= BLOCK_WOOD_STAIRS and block_id <= BLOCK_WOOD_STAIRS_WEST:
		return block_id - BLOCK_WOOD_STAIRS
	if is_door(block_id):
		return (block_id - BLOCK_WOOD_DOOR) % 4
	if is_ladder(block_id):
		return block_id - BLOCK_WOOD_LADDER
	if is_sign(block_id):
		return block_id - BLOCK_WOOD_SIGN
	if is_bed(block_id):
		return block_id - BLOCK_WOOD_BED
	return FACING_NORTH


## Maps every persisted state to its inventory/crafting ID.
static func canonical_id(block_id: int) -> int:
	match shape_type(block_id):
		SHAPE_STAIRS:
			return BLOCK_WOOD_STAIRS
		SHAPE_SLAB:
			return BLOCK_WOOD_SLAB
		SHAPE_DOOR:
			return BLOCK_WOOD_DOOR
		SHAPE_LADDER:
			return BLOCK_WOOD_LADDER
		SHAPE_SIGN:
			return BLOCK_WOOD_SIGN
		SHAPE_BED:
			return BLOCK_WOOD_BED
	return block_id


## State IDs remain valid world blocks but must never appear as inventory items.
static func is_inventory_block(block_id: int) -> bool:
	return block_id > BLOCK_AIR and block_id < BLOCK_DEFS.size() and canonical_id(block_id) == block_id


## Selects the state written to voxel bytes for a placement. `normal` is the
## face normal that was clicked; only slabs distinguish upper/lower placement.
static func placement_variant(canonical: int, direction: int, normal: Vector3i = Vector3i.UP) -> int:
	var state_facing := posmod(direction, 4)
	match canonical_id(canonical):
		BLOCK_WOOD_STAIRS:
			return BLOCK_WOOD_STAIRS + state_facing
		BLOCK_WOOD_SLAB:
			return BLOCK_WOOD_SLAB_TOP if normal.y < 0 else BLOCK_WOOD_SLAB
		BLOCK_WOOD_DOOR:
			return door_state(state_facing, false, false)
		BLOCK_WOOD_LADDER:
			if normal.x > 0:
				state_facing = FACING_WEST
			elif normal.x < 0:
				state_facing = FACING_EAST
			elif normal.z > 0:
				state_facing = FACING_NORTH
			elif normal.z < 0:
				state_facing = FACING_SOUTH
			return BLOCK_WOOD_LADDER + state_facing
		BLOCK_WOOD_SIGN:
			return BLOCK_WOOD_SIGN + state_facing
		BLOCK_WOOD_BED:
			return BLOCK_WOOD_BED + state_facing
	return canonical


static func is_door(block_id: int) -> bool:
	return block_id >= BLOCK_WOOD_DOOR and block_id <= BLOCK_WOOD_DOOR_LAST


static func door_upper(block_id: int) -> bool:
	return is_door(block_id) and block_id - BLOCK_WOOD_DOOR >= 8


static func door_open(block_id: int) -> bool:
	return is_door(block_id) and (int((block_id - BLOCK_WOOD_DOOR) / 4) % 2) == 1


## Converts door state fields to the compact voxel ID. The order is facing,
## open, upper: 4 facings x closed/open x lower/upper.
static func door_state(direction: int, opened: bool = false, upper: bool = false) -> int:
	return BLOCK_WOOD_DOOR + posmod(direction, 4) + (4 if opened else 0) + (8 if upper else 0)


static func door_with_upper(block_id: int, upper: bool) -> int:
	return door_state(facing(block_id), door_open(block_id), upper)


static func door_with_open(block_id: int, opened: bool) -> int:
	return door_state(facing(block_id), opened, door_upper(block_id))


static func is_ladder(block_id: int) -> bool:
	return block_id >= BLOCK_WOOD_LADDER and block_id <= BLOCK_WOOD_LADDER_LAST


static func is_sign(block_id: int) -> bool:
	return block_id >= BLOCK_WOOD_SIGN and block_id <= BLOCK_WOOD_SIGN_LAST


static func is_bed(block_id: int) -> bool:
	return block_id >= BLOCK_WOOD_BED and block_id <= BLOCK_WOOD_BED_LAST


## Wrong or under-tier tools can destroy a block, but cannot harvest its drops.
static func break_seconds(block_id: int, tool_id: int = 0) -> float:
	if block_id <= BLOCK_AIR or block_id >= BLOCK_DEFS.size():
		return -1.0
	var def: Array = BLOCK_DEFS[block_id]
	if float(def[6]) < 0.0 or (int(def[5]) & FLAG_UNBREAKABLE) != 0:
		return -1.0
	var speed := 1.0
	if not String(def[7]).is_empty() and ItemRegistry.tool_kind(tool_id) == def[7]:
		speed = float(ItemRegistry.tool_tier(tool_id) * 2)
	return float(def[6]) * (1.5 if can_harvest(block_id, tool_id) else 5.0) / speed


static func can_harvest(block_id: int, tool_id: int = 0) -> bool:
	if block_id <= BLOCK_AIR or block_id >= BLOCK_DEFS.size():
		return false
	var def: Array = BLOCK_DEFS[block_id]
	if float(def[6]) < 0.0 or (int(def[5]) & FLAG_UNBREAKABLE) != 0:
		return false
	return int(def[8]) == 0 or (ItemRegistry.tool_kind(tool_id) == def[7] and ItemRegistry.tool_tier(tool_id) >= int(def[8]))


func is_valid_id(block_id: int) -> bool:
	return block_id > BLOCK_AIR and block_id < _names.size()


func get_block_name(block_id: int) -> String:
	if not is_valid_id(block_id):
		return "AIR"
	return _names[block_id]


func is_opaque(block_id: int) -> bool:
	return block_id >= 0 and block_id < _opaque.size() and _opaque[block_id] == 1


func has_flag(block_id: int, flag: int) -> bool:
	return block_id >= 0 and block_id < _flags.size() and (_flags[block_id] & flag) != 0


## Fuel for the fire simulation: logs, leaves, and dry plants.
func is_flammable(block_id: int) -> bool:
	return has_flag(block_id, FLAG_FLAMMABLE)


## Blocks whose settled position is resolved by VoxelWorld's persisted gravity
## simulation. Red sand shares sand's material behavior without consuming a
## format flag bit (block IDs and flags are persisted in compact bytes).
func is_gravity_block(block_id: int) -> bool:
	return block_id == BLOCK_SAND or block_id == BLOCK_RED_SAND or block_id == BLOCK_GRAVEL


func is_water_id(block_id: int) -> bool:
	return block_id == BLOCK_WATER or (block_id >= BLOCK_WATER_FLOW_7 and block_id <= BLOCK_WATER_FLOW_1)


## 8 for a source block, 7..1 for flowing water, 0 for anything else.
func water_level(block_id: int) -> int:
	if block_id == BLOCK_WATER:
		return 8
	if block_id >= BLOCK_WATER_FLOW_7 and block_id <= BLOCK_WATER_FLOW_1:
		return BLOCK_WATER_FLOW_1 - block_id + 1
	return 0


func water_id_for_level(level: int) -> int:
	if level <= 0:
		return BLOCK_AIR
	if level >= 8:
		return BLOCK_WATER
	return BLOCK_WATER_FLOW_1 - level + 1


func is_breakable(block_id: int) -> bool:
	if not is_valid_id(block_id):
		return false
	if is_water_id(block_id):
		return false
	return not has_flag(block_id, FLAG_UNBREAKABLE)


func light_attenuation(block_id: int) -> int:
	if is_opaque(block_id):
		return MAX_LIGHT_LEVEL
	if is_water_id(block_id):
		return ATTENUATION_WATER
	if has_flag(block_id, FLAG_LEAVES):
		return ATTENUATION_LEAVES
	return 0


func emission_color(block_id: int) -> Color:
	return EMISSIVE_COLORS.get(block_id, Color.BLACK)


func is_emissive(block_id: int) -> bool:
	return (has_flag(block_id, FLAG_EMISSIVE) or EMISSIVE_COLORS.has(block_id)) and is_valid_id(block_id)


func layer_for(block_id: int, face: int) -> int:
	if block_id < 0 or block_id >= _layer_top.size():
		return 0
	if face == 0:
		return _layer_top[block_id]
	if face == 1:
		return _layer_bottom[block_id]
	return _layer_side[block_id]


func _build_texture_array() -> Dictionary:
	var texture_names: PackedStringArray = PackedStringArray()
	for def in BLOCK_DEFS:
		for index in range(2, 5):
			var name: String = def[index]
			if name != "" and not texture_names.has(name):
				texture_names.append(name)
	var images: Array[Image] = []
	var tile_lookup := {}
	for index in texture_names.size():
		var texture_name := texture_names[index]
		var image := _load_image(_texture_path(texture_name))
		image = _prepare_solid_texture(image, texture_name)
		if image.get_width() != TILE_PX or image.get_height() != TILE_PX:
			image.resize(TILE_PX, TILE_PX, Image.INTERPOLATE_NEAREST)
		if TEXTURE_TINTS.has(texture_name):
			_tint_image(image, TEXTURE_TINTS[texture_name])
		image.fix_alpha_edges()
		image.generate_mipmaps()
		images.append(image)
		tile_lookup[texture_name] = index
	texture_array = Texture2DArray.new()
	texture_array.create_from_images(images)
	_fire_layer = tile_lookup.get("fire.png", -1)
	_build_material(texture_array, images[0] if not images.is_empty() else null)
	return tile_lookup


func _texture_path(texture_name: String) -> String:
	return EXTRA_TEXTURE_PATHS.get(texture_name, TEXTURE_ROOT + texture_name)


func _prepare_solid_texture(image: Image, texture_name: String) -> Image:
	if SOLID_TEXTURE_REGIONS.has(texture_name):
		return image.get_region(SOLID_TEXTURE_REGIONS[texture_name])
	return image


func _build_material(array_texture: Texture2DArray, fallback_image: Image) -> void:
	var shader := load(BLOCK_SHADER_PATH) as Shader
	if shader:
		var shader_material := ShaderMaterial.new()
		shader_material.shader = shader
		shader_material.set_shader_parameter("albedo_texture", array_texture)
		shader_material.set_shader_parameter("fire_layer", float(_fire_layer))
		material = shader_material
		return
	var fallback_texture: Texture2D = null
	if fallback_image != null:
		fallback_texture = ImageTexture.create_from_image(fallback_image)
	material = StandardMaterial3D.new()
	material.albedo_texture = fallback_texture
	material.albedo_color = Color.WHITE
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	material.alpha_scissor_threshold = 0.5
	material.vertex_color_use_as_albedo = true
	material.roughness = 1.0
	material.metallic = 0.0
	material.metallic_specular = 0.05


func _load_image(path: String) -> Image:
	if path == TEXTURE_ROOT + "planks.png":
		var planks := Image.create(TILE_PX, TILE_PX, false, Image.FORMAT_RGBA8)
		for y in TILE_PX:
			for x in TILE_PX:
				var seam := y % 16 == 0 or (x + (y / 16) * 24) % 48 == 0
				var grain := float((x * 13 + (y / 3) * 7) % 11) / 100.0
				planks.set_pixel(x, y, Color("715033") if seam else Color("b98c54").darkened(grain))
		return planks
	var texture := load(path) as Texture2D
	if texture == null:
		push_warning("Block texture missing, using placeholder: %s" % path)
		var fallback := Image.create(TILE_PX, TILE_PX, false, Image.FORMAT_RGBA8)
		fallback.fill(Color.MAGENTA)
		return fallback
	var image := texture.get_image()
	if image.is_compressed():
		image.decompress()
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	return image


func _tint_image(image: Image, tint: Color) -> void:
	for y in image.get_height():
		for x in image.get_width():
			var pixel := image.get_pixel(x, y)
			image.set_pixel(x, y, Color(pixel.r * tint.r, pixel.g * tint.g, pixel.b * tint.b, pixel.a))


func _build_block_tables(tile_lookup: Dictionary) -> void:
	var max_id := BLOCK_DEFS.size()
	_flags.resize(max_id)
	_opaque.resize(max_id)
	_layer_top.resize(max_id)
	_layer_side.resize(max_id)
	_layer_bottom.resize(max_id)
	_names.resize(max_id)
	for def in BLOCK_DEFS:
		var id: int = def[0]
		_names[id] = def[1]
		_flags[id] = def[5]
		_opaque[id] = 1 if (int(def[5]) & FLAG_OPAQUE) != 0 else 0
		_layer_top[id] = tile_lookup.get(def[2], 0)
		_layer_side[id] = tile_lookup.get(def[3], 0)
		_layer_bottom[id] = tile_lookup.get(def[4], 0)


func _load_water_material() -> void:
	var shader := load(WATER_SHADER_PATH) as Shader
	var texture := load(WATER_TEXTURE_PATH) as Texture2D
	if shader:
		var shader_material := ShaderMaterial.new()
		shader_material.shader = shader
		if texture:
			shader_material.set_shader_parameter("water_texture", texture)
		water_material = shader_material
		return
	var fallback := StandardMaterial3D.new()
	fallback.albedo_color = Color("#3f8fdd")
	if texture:
		fallback.albedo_texture = texture
	fallback.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fallback.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	water_material = fallback
