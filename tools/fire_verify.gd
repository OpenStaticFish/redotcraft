## Headless regression check for fire spread/decay, ignitable blocks, and the
## flint-and-steel ignition path. Scene-based so class_name globals resolve.
## Run:
##   redot --headless --path . res://tools/fire_verify.tscn
extends Node

var _failures := 0


func _ready() -> void:
	_check_registry()
	_check_ignition_and_spread()
	_check_decay()
	_check_explosive_chain()
	_check_flint_and_steel()
	_check_submerged_and_support()
	_check_persistence_reseed()
	_check_shader_wiring()
	if _failures == 0:
		print("FIRE VERIFY: PASS")
	else:
		print("FIRE VERIFY: FAIL (%d)" % _failures)
	get_tree().quit(1 if _failures > 0 else 0)


func _check_registry() -> void:
	var registry := BlockRegistry.new()
	_expect(registry.is_flammable(BlockRegistry.BLOCK_LOG), "logs should burn")
	_expect(registry.is_flammable(BlockRegistry.BLOCK_LEAVES), "leaves should burn")
	_expect(registry.is_flammable(BlockRegistry.BLOCK_TALL_GRASS), "tall grass should burn")
	_expect(registry.is_flammable(BlockRegistry.BLOCK_MELON), "melon should burn")
	_expect(not registry.is_flammable(BlockRegistry.BLOCK_STONE), "stone should not burn")
	_expect(not registry.is_flammable(BlockRegistry.BLOCK_FIRE), "fire is not fuel")
	_expect(registry.is_emissive(BlockRegistry.BLOCK_FIRE), "fire should be emissive")
	_expect(registry.has_flag(BlockRegistry.BLOCK_FIRE, BlockRegistry.FLAG_CROSS), "fire should be a cross block")
	_expect(registry.is_breakable(BlockRegistry.BLOCK_FIRE), "fire should be breakable")
	_expect(registry.emission_color(BlockRegistry.BLOCK_FIRE) != Color.BLACK, "fire needs an emission color")
	_expect(registry._fire_layer >= 0, "fire texture layer was not resolved")


func _check_ignition_and_spread() -> void:
	var world := _make_world(8)
	var fire_position := Vector3i(4, 9, 4)
	var fuel_position := Vector3i(5, 9, 4)
	_set_block(world._chunks[Vector2i.ZERO].data, fuel_position, BlockRegistry.BLOCK_LOG)
	_expect(world.ignite_fire(fire_position), "failed to ignite a supported air cell")
	_expect(world.get_block_world(fire_position) == BlockRegistry.BLOCK_FIRE, "ignite did not place fire")
	_expect(world._edited_blocks.get(fire_position, -1) == BlockRegistry.BLOCK_FIRE,
		"ignition was not recorded as a persistent edit")
	_expect(world._chunk_edit_version.get(Vector2i.ZERO, 0) == 1,
		"ignition invalidated its chunk more than once")
	for step in 12:
		world._fire_tick()
	# The log catches fire but is never replaced by a fire block.
	_expect(world._burning.has(fuel_position), "fire did not catch the adjacent log")
	_expect(world.get_block_world(fuel_position) == BlockRegistry.BLOCK_LOG,
		"burning log was replaced instead of burning in place")
	# Burn-out destroys the block and persists the settled air edit.
	for step in 30:
		world._fire_tick()
	_expect(world.get_block_world(fuel_position) == BlockRegistry.BLOCK_AIR,
		"burning log never crumbled away")
	_expect(world._edited_blocks.get(fuel_position, -1) == BlockRegistry.BLOCK_AIR,
		"burnt log did not persist its settled air edit")
	world.free()


func _check_decay() -> void:
	var world := _make_world(8)
	var fire_position := Vector3i(4, 9, 4)
	var fuel_position := Vector3i(5, 9, 4)
	_set_block(world._chunks[Vector2i.ZERO].data, fuel_position, BlockRegistry.BLOCK_LEAVES)
	world.ignite_fire(fire_position)
	for step in 45:
		world._fire_tick()
	_expect(world.get_block_world(fire_position) == BlockRegistry.BLOCK_AIR,
		"burned-out fire did not decay to air")
	_expect(world.get_block_world(fuel_position) == BlockRegistry.BLOCK_AIR,
		"burned fuel did not decay to air")
	_expect(world._edited_blocks.get(fire_position, -1) == BlockRegistry.BLOCK_AIR,
		"extinguished fire did not persist its settled air edit")
	_expect(world._edited_blocks.get(fuel_position, -1) == BlockRegistry.BLOCK_AIR,
		"burnt fuel did not persist its settled air edit")

	# A lone spark in open air has no support and should extinguish immediately.
	var floating := Vector3i(10, 20, 10)
	_expect(world.ignite_fire(floating), "failed to place a floating spark")
	world._fire_tick()
	_expect(world.get_block_world(floating) == BlockRegistry.BLOCK_AIR,
		"unsupported fire was not extinguished")
	world.free()


func _check_explosive_chain() -> void:
	var world := _make_world(8)
	var fire_position := Vector3i(5, 9, 4)
	var tnt_position := Vector3i(6, 9, 4)
	_set_block(world._chunks[Vector2i.ZERO].data, tnt_position, BlockRegistry.BLOCK_TNT)
	world.ignite_fire(fire_position)
	world._fire_tick()
	_expect(world.get_block_world(tnt_position) == BlockRegistry.BLOCK_AIR,
		"fire did not chain-detonate the adjacent TNT")
	_expect(world._edited_blocks.get(tnt_position, -1) == BlockRegistry.BLOCK_AIR,
		"detonation was not recorded as a persistent edit")
	world.free()


func _check_flint_and_steel() -> void:
	var world := _make_world(8)
	var stone_position := Vector3i(4, 9, 4)
	_set_block(world._chunks[Vector2i.ZERO].data, stone_position, BlockRegistry.BLOCK_STONE)
	var lit := world.use_flint_and_steel(stone_position, Vector3i.UP)
	_expect(int(lit.get("ignited", 0)) == 1, "flint and steel did not light a fire on a block face")
	_expect(world.get_block_world(stone_position + Vector3i.UP) == BlockRegistry.BLOCK_FIRE,
		"flint and steel lit the wrong cell")

	var tnt_position := Vector3i(9, 9, 4)
	_set_block(world._chunks[Vector2i.ZERO].data, tnt_position, BlockRegistry.BLOCK_TNT)
	var blast := world.use_flint_and_steel(tnt_position, Vector3i.UP)
	_expect(int(blast.get("removed", 0)) > 0, "flint and steel did not detonate TNT")
	_expect(world.get_block_world(tnt_position) == BlockRegistry.BLOCK_AIR,
		"detonated TNT survived")

	# Clicking a flammable block lights that block, not the air beside it.
	var log_position := Vector3i(1, 9, 1)
	_set_block(world._chunks[Vector2i.ZERO].data, log_position, BlockRegistry.BLOCK_LOG)
	var lit_log := world.use_flint_and_steel(log_position, Vector3i.UP)
	_expect(int(lit_log.get("ignited", 0)) == 1, "flint and steel did not ignite a log")
	_expect(world._burning.has(log_position), "clicked log did not start burning")
	_expect(world.get_block_world(log_position) == BlockRegistry.BLOCK_LOG,
		"clicked log was replaced by a fire block instead of burning in place")

	var far_away := Vector3i(4096, 40, 4096)
	_expect(world.use_flint_and_steel(far_away, Vector3i.UP).is_empty(),
		"flint and steel ignited unloaded terrain")
	world.free()


func _check_submerged_and_support() -> void:
	var world := _make_world(8)
	# A log with water directly above is flooded and cannot be lit.
	var wet_log := Vector3i(2, 9, 2)
	_set_block(world._chunks[Vector2i.ZERO].data, wet_log, BlockRegistry.BLOCK_LOG)
	_set_block(world._chunks[Vector2i.ZERO].data, wet_log + Vector3i.UP, BlockRegistry.BLOCK_WATER)
	var wet_lit := world.use_flint_and_steel(wet_log, Vector3i.UP)
	_expect(wet_lit.get("blocked", "") == "wet", "flint and steel lit a submerged log")
	_expect(not world._burning.has(wet_log), "submerged log started burning")

	# Re-clicking a burning block reports already-burning rather than a face hint.
	var log_position := Vector3i(4, 9, 4)
	_set_block(world._chunks[Vector2i.ZERO].data, log_position, BlockRegistry.BLOCK_LOG)
	world.use_flint_and_steel(log_position, Vector3i.UP)
	var again := world.use_flint_and_steel(log_position, Vector3i.UP)
	_expect(again.get("blocked", "") == "burning", "re-lighting a burning block was not reported")

	# Fire keeps burning next to transparent-but-solid glass (broadened support).
	var fire_position := Vector3i(6, 9, 6)
	_set_block(world._chunks[Vector2i.ZERO].data, fire_position, BlockRegistry.BLOCK_GLASS)
	_set_block(world._chunks[Vector2i.ZERO].data, fire_position + Vector3i.UP, BlockRegistry.BLOCK_AIR)
	_expect(world.ignite_fire(fire_position + Vector3i.UP), "failed to place fire on glass")
	world._fire_tick()
	_expect(world.get_block_world(fire_position + Vector3i.UP) == BlockRegistry.BLOCK_FIRE,
		"fire on a glass face was extinguished")

	# Burn-out queues adjacent water so a flooded cell refills, like break_block().
	var burn_position := Vector3i(10, 9, 10)
	_set_block(world._chunks[Vector2i.ZERO].data, burn_position, BlockRegistry.BLOCK_LOG)
	world._start_burning(burn_position, {})
	world._burning[burn_position] = 1
	world._water_queued.clear()
	world._fire_tick()
	_expect(world.get_block_world(burn_position) == BlockRegistry.BLOCK_AIR,
		"burning block did not crumble away")
	_expect(not world._water_queued.is_empty(), "burnt block did not seed adjacent water")
	world.free()


func _check_persistence_reseed() -> void:
	var world := _make_world(8)
	var fire_position := Vector3i(2, 9, 2)
	world._edited_blocks[fire_position] = BlockRegistry.BLOCK_FIRE
	world._edits_by_chunk[Vector2i.ZERO] = {
		fire_position: BlockRegistry.BLOCK_FIRE,
		Vector3i(3, 9, 2): BlockRegistry.BLOCK_AIR,
	}
	world._seed_fire_edits(Vector2i.ZERO)
	_expect(world._fire_queued.has(fire_position), "regenerated fire was not requeued")
	_expect(world._fire_life.has(fire_position), "regenerated fire had no burn life")
	_expect(not world._fire_queued.has(Vector3i(3, 9, 2)), "non-fire edits should not be queued")
	world.free()


func _check_shader_wiring() -> void:
	var code := FileAccess.get_file_as_string("res://world/block.gdshader")
	_expect(code.contains("fire_layer"), "block shader is missing the fire_layer uniform")
	_expect(code.contains("fire > 0.5"), "block shader is missing the fire UV animation")
	# The burning-block overlay is what keeps the block's own texture visible.
	var flame_shader := FileAccess.get_file_as_string("res://world/fire_overlay.gdshader")
	_expect(flame_shader.contains("INSTANCE_CUSTOM"), "flame overlay shader is missing per-instance data")
	var smoke_shader := FileAccess.get_file_as_string("res://world/smoke_overlay.gdshader")
	_expect(smoke_shader.contains("INSTANCE_CUSTOM"), "smoke overlay shader is missing per-instance data")
	_expect(FileAccess.file_exists("res://assets/placeholders/fire/smoke.png"),
		"smoke overlay texture is missing")


func _make_world(floor_y: int) -> VoxelWorld:
	var world := VoxelWorld.new()
	world._blocks = BlockRegistry.new()
	var chunk := VoxelWorld.Chunk.new()
	chunk.data.resize(VoxelDefs.CHUNK_AREA * VoxelDefs.WORLD_HEIGHT)
	world._chunks[Vector2i.ZERO] = chunk
	for direction in VoxelDefs.DIRS_8:
		var neighbor := VoxelWorld.Chunk.new()
		neighbor.data.resize(VoxelDefs.CHUNK_AREA * VoxelDefs.WORLD_HEIGHT)
		world._chunks[direction] = neighbor
	for z in VoxelDefs.CHUNK_SIZE:
		for x in VoxelDefs.CHUNK_SIZE:
			_set_block(chunk.data, Vector3i(x, floor_y, z), BlockRegistry.BLOCK_STONE)
	return world


func _set_block(data: PackedByteArray, position: Vector3i, block_id: int) -> void:
	var index := position.x + position.z * VoxelDefs.DATA_STRIDE_Z + position.y * VoxelDefs.DATA_STRIDE_Y
	data[index] = block_id


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("fire_verify: %s" % message)
