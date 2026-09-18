## Immutable definitions for sparse, region-scale surface POIs.
##
## Owner cells select candidates globally; the populator clips their fixed bounds
## into every affected chunk. This catalog holds no per-generation state.
class_name StructureCatalog
extends RefCounted

const BlockRegistryScript = preload("res://world/block_registry.gd")
const WorldGenHashScript = preload("res://world/worldgen/world_gen_hash.gd")

const OWNER_CELL_SIZE: int = 160
const HORIZONTAL_HALO: int = 3
const CLEAR_HEIGHT: int = 14
const TYPE_ABANDONED_CAMP: int = 0
const TYPE_STONE_WATCHTOWER: int = 1


class Candidate:
	var kind: int
	var anchor: Vector2i
	var orientation: int
	var hash_value: int

	func _init(kind_value: int, anchor_value: Vector2i, orientation_value: int, hash_value: int) -> void:
		kind = kind_value
		anchor = anchor_value
		orientation = orientation_value
		self.hash_value = hash_value


## One candidate is owned by each 160-block cell. The admission lottery keeps
## landmarks rare while retaining a fixed, deterministic anchor/orientation/type.
static func candidate_for(seed: int, owner_x: int, owner_z: int) -> Candidate:
	var hash_value: int = WorldGenHashScript.hash_2d(seed + 1601, owner_x, owner_z)
	if hash_value % 5 >= 3:
		return null
	var anchor := Vector2i(
		owner_x * OWNER_CELL_SIZE + 20 + hash_value % (OWNER_CELL_SIZE - 40),
		owner_z * OWNER_CELL_SIZE + 20 + (hash_value / 37) % (OWNER_CELL_SIZE - 40))
	return Candidate.new((hash_value / 97) % 2, anchor, (hash_value / 211) % 4, hash_value)


static func clear_radius(_kind: int) -> int:
	return HORIZONTAL_HALO


static func max_height(kind: int) -> int:
	return 6 if kind == TYPE_STONE_WATCHTOWER else 3


## Returns the generated block at an anchor-relative world offset. The compact
## definitions intentionally have supported vertical columns: their LOD top and
## immediate-below material can be reproduced without materializing a chunk.
static func block_at(kind: int, orientation: int, offset_x: int, local_y: int, offset_z: int) -> int:
	var local := _unrotate(offset_x, offset_z, orientation)
	var u: int = local.x
	var v: int = local.y
	if kind == TYPE_ABANDONED_CAMP:
		if local_y == 1 and absi(u) <= 3 and absi(v) <= 2:
			return BlockRegistryScript.BLOCK_COBBLESTONE
		if absi(u) == 3 and absi(v) == 2 and local_y >= 2 and local_y <= 3:
			return BlockRegistryScript.BLOCK_LOG
		if u == 0 and v == 0 and local_y == 2:
			return BlockRegistryScript.BLOCK_TORCH
		return BlockRegistryScript.BLOCK_AIR
	# A compact, roofless stone watchtower: continuous perimeter walls retain a
	# readable silhouette while the open centre keeps it from becoming a bunker.
	if absi(u) <= 2 and absi(v) <= 2:
		if local_y == 1:
			return BlockRegistryScript.BLOCK_COBBLESTONE
		if (absi(u) == 2 or absi(v) == 2) and local_y >= 2 and local_y <= 6:
			return BlockRegistryScript.BLOCK_LOG if absi(u) == 2 and absi(v) == 2 and local_y < 6 else BlockRegistryScript.BLOCK_COBBLESTONE
		if u == 0 and v == 0 and local_y == 2:
			return BlockRegistryScript.BLOCK_TORCH
	return BlockRegistryScript.BLOCK_AIR


static func _unrotate(offset_x: int, offset_z: int, orientation: int) -> Vector2i:
	match orientation & 3:
		0:
			return Vector2i(offset_x, offset_z)
		1:
			return Vector2i(offset_z, -offset_x)
		2:
			return Vector2i(-offset_x, -offset_z)
		_:
			return Vector2i(-offset_z, offset_x)
