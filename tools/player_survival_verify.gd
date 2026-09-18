## redot --headless --path . --script res://tools/player_survival_verify.gd
## Runtime Player loading allows its autoload dependencies to resolve.
extends SceneTree

class TestWorld extends VoxelWorld:
	var sync_calls := 0
	func _ready() -> void:
		_blocks = BlockRegistry.new()
	func _process(_delta: float) -> void:
		pass
	func setup_player(_node: Node3D, sync_spawn_area := false) -> void:
		if sync_spawn_area:
			sync_calls += 1
	func find_safe_spawn(desired: Vector3) -> Vector3:
		return desired + Vector3.UP

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var pick := InputEventMouseButton.new()
	pick.button_index = MOUSE_BUTTON_MIDDLE
	pick.pressed = true
	_expect(pick.is_action_pressed("pick_block"), "middle click maps to pick action")
	var world := TestWorld.new()
	root.add_child(world)
	var chunk := VoxelWorld.Chunk.new()
	chunk.data.resize(VoxelDefs.CHUNK_AREA * VoxelDefs.WORLD_HEIGHT)
	chunk.shape = CollisionShape3D.new()
	chunk.shape.shape = BoxShape3D.new()
	world.add_child(chunk.shape)
	world._chunks[Vector2i.ZERO] = chunk
	var player = load("res://player/player.gd").new()
	player.game_mode = GameMode.SURVIVAL
	var head := Node3D.new()
	head.name = "Head"
	head.position.y = 1.65
	var camera := Camera3D.new()
	camera.name = "Camera3D"
	head.add_child(camera)
	player.add_child(head)
	var capsule := CollisionShape3D.new()
	capsule.shape = CapsuleShape3D.new()
	capsule.shape.height = 1.8
	capsule.shape.radius = 0.3
	capsule.position.y = 0.9
	player.add_child(capsule)
	root.add_child(player)
	player.set_physics_process(false)
	player.world = world
	player._create_highlight()
	player._create_held_block()
	player.position = Vector3(4.5, 3.0, 4.5)
	player.spawn_position = player.position
	var deaths: Array[String] = []
	player.died.connect(func(cause: String) -> void: deaths.append(cause))
	player.take_damage(3.0, "test")
	_expect(player.health == 17.0 and not player.dead, "damage")
	player.take_damage(NAN)
	_expect(player.health == 17.0, "nonfinite damage rejected")
	player.hunger = 10.0
	_expect(player.eat(4.0) and player.hunger == 14.0, "food")
	_expect(not player.eat(-1.0), "negative food rejected")
	var state: Dictionary = player.persistent_state()
	player.health = 1.0
	_expect(player.restore_persistent_state(state) and player.health == 17.0 and player.hunger == 14.0, "vitals roundtrip")
	state["flying"] = true
	state["game_mode"] = GameMode.CREATIVE
	_expect(player.restore_persistent_state(state) and not player.flying and player.game_mode == GameMode.SURVIVAL, "survival ignores saved flight and mode")
	player._handle_double_tap_jump()
	player._handle_double_tap_jump()
	_expect(not player.flying, "survival cannot enable flight")
	player.take_damage(100.0, "test death")
	player.take_damage(1.0)
	_expect(player.dead and deaths == ["test death"] and not player.eat(4.0), "death fires once and blocks food")
	state = player.persistent_state()
	_expect(player.restore_persistent_state(state) and player.dead, "dead restore")
	state["position"] = [4.5, -21.0, 4.5]
	_expect(player.restore_persistent_state(state) and player.dead, "void death restore")
	player.respawn()
	_expect(not player.dead and player.health == 20.0 and player.hunger == 20.0 and player.air == 10.0, "respawn vitals")
	_expect(world.sync_calls == 2 and player.position == player.spawn_position + Vector3.UP, "respawn streams and resolves safe spawn")
	player.position = Vector3(4.5, 3.0, 4.5)
	var eye := Vector3i(4, 4, 4)
	_set_block(chunk.data, eye, BlockRegistry.BLOCK_WATER)
	player.air = 0.1
	player._update_survival(1.0)
	_expect(player.air == 0.0 and player.health == 18.0, "drowning")
	_set_block(chunk.data, eye, BlockRegistry.BLOCK_AIR)
	player._update_survival(1.0)
	_expect(player.air == 4.0, "air refill")
	player.hunger = 0.0
	player._update_survival(1.0)
	_expect(player.health == 17.0, "starvation")
	player.hunger = 20.0
	player._regen_clock = 3.0
	player._update_survival(1.0)
	_expect(player.health == 18.0 and player.hunger < 20.0, "fed regeneration")
	_set_block(chunk.data, Vector3i(4, 3, 4), BlockRegistry.BLOCK_LAVA)
	player._update_survival(1.0)
	_expect(player.health == 14.0, "lava")
	_set_block(chunk.data, Vector3i(4, 3, 4), BlockRegistry.BLOCK_AIR)
	_set_block(chunk.data, eye, BlockRegistry.BLOCK_STONE)
	player._update_survival(1.0)
	_expect(player.health == 13.0, "suffocation")
	_set_block(chunk.data, eye, BlockRegistry.BLOCK_FIRE)
	player._update_survival(1.0)
	_expect(player.health == 11.0, "fire")
	_set_block(chunk.data, eye, BlockRegistry.BLOCK_AIR)
	var cell := Vector3i(4, 4, 2)
	_set_block(chunk.data, cell, BlockRegistry.BLOCK_STONE)
	player.has_target = true
	player.target_block = cell
	player.selected_block = 0
	var mined: Array = []
	var broken: Array = []
	player.mined_block.connect(func(pos: Vector3i, id: int, harvest: bool) -> void: mined.append([pos, id, harvest]))
	player.block_broken.connect(func(id: int) -> void: broken.append(id))
	player._break_target()
	player._tick_mining(0.01)
	_expect(world.get_block_world(cell) == BlockRegistry.BLOCK_STONE and player.mining_progress > 0.0, "mining is timed")
	_expect(player._effects.cracks.visible, "mining cracks")
	player.selected_block = ItemRegistry.ITEM_WOOD_PICKAXE
	player._tick_mining(0.1)
	_expect(not player._mining and player.mining_progress == 0.0, "tool change cancels mining")
	player._break_target()
	player._tick_mining(BlockRegistry.break_seconds(BlockRegistry.BLOCK_STONE, player.selected_block) + 0.1)
	_expect(world.get_block_world(cell) == 0 and mined.size() == 1 and broken.size() == 1 and mined[0][2], "completion signals and harvest")
	_set_block(chunk.data, cell, BlockRegistry.BLOCK_STONE)
	player.selected_block = 0
	player._break_target()
	player._tick_mining(BlockRegistry.break_seconds(BlockRegistry.BLOCK_STONE, 0) + 0.1)
	_expect(mined.size() == 2 and not mined[1][2], "wrong tool removes without harvesting")
	_set_block(chunk.data, cell, BlockRegistry.BLOCK_BEDROCK)
	player._break_target()
	player._tick_mining(100.0)
	_expect(world.get_block_world(cell) == BlockRegistry.BLOCK_BEDROCK and mined.size() == 2, "unbreakable mining")
	_set_block(chunk.data, cell, BlockRegistry.BLOCK_STONE)
	player._break_target()
	player.target_block += Vector3i.RIGHT
	player._tick_mining(100.0)
	_expect(not player._mining and mined.size() == 2, "target change cancels mining")
	player.target_block = cell
	var interactions: Array = []
	player.interact_check = func(_pos: Vector3i) -> bool: return true
	player.block_interacted.connect(func(pos: Vector3i) -> void: interactions.append(pos))
	player.can_place_check = func() -> bool: return false
	player._place_target()
	_expect(interactions == [cell], "interaction precedes placement validation")
	player.third_person = true
	player._effects.update_view(0.1)
	_expect(camera.position.z > 0.0 and player._effects.body.visible and not player._held_block.visible, "third person")
	player.third_person = false
	player._effects.update_view(0.1)
	_expect(camera.position == Vector3.ZERO and not player._effects.body.visible, "first person restored")
	var picks: Array = []
	player.block_picked.connect(func(id: int) -> void: picks.append(id))
	# The headless display cannot capture a mouse; exercise the same action.
	player._pick_target()
	_expect(picks == [BlockRegistry.BLOCK_STONE], "middle pick")
	player._break_target()
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	player._unhandled_input(release)
	_expect(not player._mining and not player._effects.cracks.visible, "release cancels mining")
	var foods: Array = []
	player.item_used.connect(func(id: int, _pos: Vector3i) -> void: foods.append(id))
	player.selected_block = ItemRegistry.ITEM_COOKED_MEAT
	player.has_target = false
	player._place_target()
	_expect(foods == [ItemRegistry.ITEM_COOKED_MEAT], "food works without target")
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(2.0, 1.0, 2.0)
	floor_shape.shape = floor_box
	floor_body.add_child(floor_shape)
	floor_body.position = Vector3(4.0, 2.5, 4.0)
	root.add_child(floor_body)
	await physics_frame
	await process_frame
	player.position = Vector3(4.5, 3.01, 4.5)
	player.velocity = Vector3(10.0, 0.0, 0.0)
	player._protect_edge(0.1)
	_expect(player.velocity.x == 0.0, "crouch blocks unsupported step")
	player.velocity = Vector3(-1.0, 0.0, 0.0)
	player._protect_edge(0.1)
	_expect(player.velocity.x == -1.0, "crouch permits supported step")
	player.position = Vector3(4.0, 9.0, 4.0)
	player.velocity = Vector3.ZERO
	player.health = 20.0
	player.hunger = 10.0
	for tick in range(160):
		player._physics_process(1.0 / 60.0)
	_expect(player.is_on_floor() and player.health < 20.0 and player.health > 0.0, "landing fall damage")
	# Simulate a separate Creative startup with hostile legacy session values.
	player.game_mode = GameMode.CREATIVE
	state = {"position": [4.5, 3.0, 4.5], "health": 0.0, "hunger": 1.0,
		"air": 0.0, "dead": true, "flying": true, "game_mode": GameMode.SURVIVAL}
	_expect(player.restore_persistent_state(state) and not player.dead and player.flying
		and player.health == 20.0 and player.hunger == 20.0 and player.air == 10.0
		and player.game_mode == GameMode.CREATIVE, "creative ignores saved death, vitals and mode")
	_set_block(chunk.data, eye, BlockRegistry.BLOCK_LAVA)
	player._update_survival(100.0)
	player.take_damage(100.0, "test")
	_expect(player.health == 20.0 and player.hunger == 20.0 and player.air == 10.0 and not player.dead, "creative has no survival drain or damage")
	player._handle_double_tap_jump()
	player._handle_double_tap_jump()
	_expect(not player.flying, "creative double tap toggles flight")
	_set_block(chunk.data, cell, BlockRegistry.BLOCK_STONE)
	player.has_target = true
	player.target_block = cell
	player.selected_block = 0
	player._break_target()
	_expect(world.get_block_world(cell) == 0 and not player._mining, "creative mines instantly without a tool")
	_set_block(chunk.data, cell, BlockRegistry.BLOCK_BEDROCK)
	player._break_target()
	_expect(world.get_block_world(cell) == BlockRegistry.BLOCK_BEDROCK, "creative respects unbreakable blocks")
	player.position.y = -21.0
	player._physics_process(0.1)
	_expect(player.position.y >= 0.0 and not player.dead and player.velocity == Vector3.ZERO, "creative void recovery does not stall below world")
	state["position"] = [4.5, -21.0, 4.5]
	_expect(not player.restore_persistent_state(state), "creative rejects saved void death position for startup spawn recovery")
	floor_body.free()
	player.free()
	world.free()
	# Let the headless audio mixer finish the two real mining cues before exit.
	await create_timer(1.0).timeout
	if failures == 0:
		print("PLAYER SURVIVAL VERIFY: PASS")
	quit(0 if failures == 0 else 1)


func _set_block(data: PackedByteArray, pos: Vector3i, id: int) -> void:
	data[pos.x + pos.z * VoxelDefs.DATA_STRIDE_Z + pos.y * VoxelDefs.DATA_STRIDE_Y] = id


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("player_survival_verify: " + message)
