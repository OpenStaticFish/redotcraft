extends SceneTree

var failures := 0


func _init() -> void:
	_verify_registry_states()
	_verify_shape_meshes()
	_verify_recipes_and_drops()
	_verify_sleep_clock_and_threat_hook()
	_verify_indoor_bed_spawn()
	if failures == 0:
		print("functional_blocks_verify: PASS")
		quit(0)
	else:
		push_error("functional_blocks_verify: %d failure(s)" % failures)
		quit(1)


func _verify_registry_states() -> void:
	_check(BlockRegistry.BLOCK_DEFS.size() == BlockRegistry.BLOCK_WOOD_BED_LAST + 1,
		"state IDs stay contiguous")
	for direction in 4:
		var stair := BlockRegistry.placement_variant(BlockRegistry.BLOCK_WOOD_STAIRS, direction)
		_check(BlockRegistry.facing(stair) == direction, "stairs preserve facing %d" % direction)
		_check(BlockRegistry.canonical_id(stair) == BlockRegistry.BLOCK_WOOD_STAIRS,
			"stairs map to their inventory ID")
		var lower := BlockRegistry.door_state(direction, false, false)
		var upper := BlockRegistry.door_with_upper(lower, true)
		_check(BlockRegistry.door_upper(upper), "door upper state %d" % direction)
		_check(BlockRegistry.door_open(BlockRegistry.door_with_open(lower, true)),
			"door open state %d" % direction)
		_check(BlockRegistry.facing(upper) == direction, "door halves share facing %d" % direction)
	_check(BlockRegistry.placement_variant(BlockRegistry.BLOCK_WOOD_SLAB, 0, Vector3i.DOWN)
		== BlockRegistry.BLOCK_WOOD_SLAB_TOP, "underside placement creates a top slab")
	_check(BlockRegistry.placement_variant(BlockRegistry.BLOCK_WOOD_LADDER, 0, Vector3i.RIGHT)
		== BlockRegistry.BLOCK_WOOD_LADDER + BlockRegistry.FACING_WEST,
		"ladder faces away from its east support")
	_check(not BlockRegistry.is_inventory_block(BlockRegistry.BLOCK_WOOD_STAIRS_EAST),
		"voxel-only states stay out of inventories")
	_check(BlockRegistry.BLOCK_DEFS[BlockRegistry.BLOCK_CRAFTING_TABLE][2] == "crafting_top.png",
		"crafting table has a dedicated texture set")
	_check(BlockRegistry.BLOCK_DEFS[BlockRegistry.BLOCK_CHEST][3] == "chest_side.png",
		"chest has a dedicated texture set")
	_check(BlockRegistry.BLOCK_DEFS[BlockRegistry.BLOCK_FURNACE][3] == "furnace_side.png",
		"furnace has a dedicated texture set")
	_check(BlockRegistry.BLOCK_DEFS[BlockRegistry.BLOCK_WOOD_DOOR][3] == "door_lower.png",
		"door lower half has a dedicated texture")
	_check(BlockRegistry.BLOCK_DEFS[BlockRegistry.BLOCK_WOOD_DOOR + 8][3] == "door_upper.png",
		"door upper half has a dedicated texture")
	_check(BlockRegistry.BLOCK_DEFS[BlockRegistry.BLOCK_WOOD_LADDER][3] == "ladder.png",
		"ladder has a dedicated texture")
	_check(BlockRegistry.BLOCK_DEFS[BlockRegistry.BLOCK_WOOD_SIGN][3] == "sign.png",
		"sign has a dedicated texture")
	_check(BlockRegistry.BLOCK_DEFS[BlockRegistry.BLOCK_WOOD_BED][3] == "bed_side.png",
		"bed has a dedicated texture set")


func _verify_shape_meshes() -> void:
	var blocks := BlockRegistry.new()
	var mesher := ChunkMesher.new(blocks)
	for block_id in [BlockRegistry.BLOCK_WOOD_STAIRS, BlockRegistry.BLOCK_WOOD_SLAB,
			BlockRegistry.BLOCK_WOOD_DOOR, BlockRegistry.BLOCK_WOOD_SIGN,
			BlockRegistry.BLOCK_WOOD_BED]:
		var result := _mesh_single(mesher, block_id)
		_check(not result.verts.is_empty(), "%s emits geometry" % blocks.get_block_name(block_id))
		_check(not result.collision.is_empty(), "%s emits collision" % blocks.get_block_name(block_id))
	var ladder := _mesh_single(mesher, BlockRegistry.BLOCK_WOOD_LADDER)
	_check(not ladder.verts.is_empty(), "ladder emits geometry")
	_check(ladder.collision.is_empty(), "ladder remains pass-through for climbing")
	var north_stairs := mesher.make_block_mesh(BlockRegistry.BLOCK_WOOD_STAIRS)
	var east_stairs := mesher.make_block_mesh(BlockRegistry.BLOCK_WOOD_STAIRS_EAST)
	_check(north_stairs != null and east_stairs != null, "rotated preview meshes are available")
	_check(north_stairs.get_aabb().size.length_squared() > 0.0, "stair preview has bounds")


func _mesh_single(mesher: ChunkMesher, block_id: int) -> ChunkMesher.MeshResult:
	var data := PackedByteArray()
	data.resize(VoxelDefs.CHUNK_AREA * VoxelDefs.WORLD_HEIGHT)
	data[1 + VoxelDefs.DATA_STRIDE_Z + VoxelDefs.DATA_STRIDE_Y] = block_id
	var heights := PackedInt32Array()
	heights.resize(VoxelDefs.CHUNK_AREA)
	heights.fill(-1)
	heights[1 + VoxelDefs.DATA_STRIDE_Z] = 1
	var tints := PackedColorArray()
	tints.resize(VoxelDefs.CHUNK_AREA)
	tints.fill(Color.WHITE)
	return mesher.build(data, 1, heights, tints, tints, ChunkMesher.NeighborSet.new(), true)


func _verify_recipes_and_drops() -> void:
	for recipe_id in ["wood_stairs", "wood_slabs", "wood_door", "wood_ladders",
			"wood_signs", "wood_bed"]:
		_check(not CraftingRecipes.get_recipe(recipe_id).is_empty(), "%s recipe exists" % recipe_id)
	_check(ItemRegistry.harvest_drop(BlockRegistry.BLOCK_WOOD_STAIRS_EAST).get("id", 0)
		== BlockRegistry.BLOCK_WOOD_STAIRS, "rotated states drop their canonical item")
	_check(ItemRegistry.is_valid(BlockRegistry.BLOCK_WOOD_BED), "bed is an inventory item")
	_check(not ItemRegistry.is_valid(BlockRegistry.BLOCK_WOOD_BED + 1),
		"rotated bed state is not an inventory item")


func _verify_sleep_clock_and_threat_hook() -> void:
	var clock := DayNightCycle.new()
	clock.set_time(23.0)
	_check(clock.is_night(), "23:00 is sleepable night")
	clock.skip_to_morning()
	_check(is_equal_approx(clock.time_hours, DayNightCycle.SUNRISE_HOUR),
		"sleep skips to sunrise")
	_check(not clock.is_night(), "sunrise is daytime")
	var world := VoxelWorld.new()
	_check(not world.is_threatened(Vector3.ZERO), "no entity system means no default threat")
	world.threat_check = func(_position: Vector3, radius: float) -> bool: return radius >= 8.0
	_check(world.is_threatened(Vector3.ZERO), "installed hostile query blocks sleep")


func _verify_indoor_bed_spawn() -> void:
	var world := VoxelWorld.new()
	world._blocks = BlockRegistry.new()
	var chunk := VoxelWorld.Chunk.new()
	chunk.data.resize(VoxelDefs.CHUNK_AREA * VoxelDefs.WORLD_HEIGHT)
	world._chunks[Vector2i.ZERO] = chunk
	var bed := Vector3i(8, 5, 8)
	# Solid floor, occupied bed cell, and a roof that the general surface-spawn
	# search would prefer. The dedicated search must stay beside the bed.
	for z in range(5, 12):
		for x in range(5, 12):
			_set_fixture_block(chunk.data, Vector3i(x, 4, z), BlockRegistry.BLOCK_STONE)
			_set_fixture_block(chunk.data, Vector3i(x, 8, z), BlockRegistry.BLOCK_STONE)
	_set_fixture_block(chunk.data, bed, BlockRegistry.BLOCK_WOOD_BED)
	var result := world.find_bed_spawn(bed)
	_check(bool(result.get("found", false)), "indoor bed finds a same-floor respawn")
	if bool(result.get("found", false)):
		var position: Vector3 = result.position
		_check(position.y < 7.0, "indoor bed respawn stays below the roof")
		_check(absi(floori(position.x) - bed.x) <= 3 and absi(floori(position.z) - bed.z) <= 3,
			"bed respawn stays nearby")
		_check(world.is_standable_spawn(position), "stored indoor bed respawn remains directly usable")


func _set_fixture_block(data: PackedByteArray, position: Vector3i, block_id: int) -> void:
	data[position.x + position.z * VoxelDefs.DATA_STRIDE_Z \
		+ position.y * VoxelDefs.DATA_STRIDE_Y] = block_id


func _check(condition: bool, label: String) -> void:
	if condition:
		return
	failures += 1
	push_error("functional_blocks_verify: " + label)
