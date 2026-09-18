## Ordered ore selection rules. Rule order and cumulative roll thresholds are
## part of deterministic world compatibility; do not convert this to a map.
class_name OreCatalog
extends RefCounted

const BlockRegistryScript = preload("res://world/block_registry.gd")

const LEGACY_VERSION_MAX := 13


class OreRule extends RefCounted:
	var block_id: int
	var max_anchor_y_exclusive: int
	var roll_exclusive: int

	func _init(p_block_id: int, p_max_anchor_y_exclusive: int, p_roll_exclusive: int) -> void:
		block_id = p_block_id
		max_anchor_y_exclusive = p_max_anchor_y_exclusive
		roll_exclusive = p_roll_exclusive


var rules: Array[OreRule] = []


func _init(worldgen_version: int) -> void:
	# Version 8 is the first cataloged layout. Later versions change other systems;
	# all supported revisions retain this layout until a distinct ore catalog exists.
	assert(worldgen_version >= 1 and worldgen_version <= LEGACY_VERSION_MAX)
	rules = _legacy_v8_rules()


func select(hash_value: int, anchor_y: int) -> int:
	var roll := hash_value % 100
	for rule in rules:
		if anchor_y < rule.max_anchor_y_exclusive and roll < rule.roll_exclusive:
			return rule.block_id
	return BlockRegistryScript.BLOCK_AIR


static func _legacy_v8_rules() -> Array[OreRule]:
	var result: Array[OreRule] = []
	result.append(OreRule.new(BlockRegistryScript.BLOCK_GOLD_ORE, 32, 17))
	result.append(OreRule.new(BlockRegistryScript.BLOCK_IRON_ORE, 58, 34))
	result.append(OreRule.new(BlockRegistryScript.BLOCK_COAL_ORE, 90, 57))
	return result
