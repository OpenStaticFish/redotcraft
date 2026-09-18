## redot --headless --path . --script res://tools/item_drops_verify.gd
extends SceneTree

class TestWorld extends VoxelWorld:
	var resident := true
	var wall := false
	func _ready() -> void:
		_blocks = BlockRegistry.new()
	func _process(_delta: float) -> void:
		pass
	func is_collision_ready_at(at: Vector3) -> bool:
		return resident and at.x < 16.0 and at.x >= 0.0 and at.z >= 0.0 and at.z < 16.0
	func get_block_world(at: Vector3i) -> int:
		return BlockRegistry.BLOCK_STONE if at.y == 0 or (wall and at.x == 8) else BlockRegistry.BLOCK_AIR
	func make_block_mesh(_id: int) -> ArrayMesh:
		return ArrayMesh.new()

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var world := TestWorld.new()
	root.add_child(world)
	# Runtime loading resolves Player's autoload dependencies in --script mode.
	var player = load("res://player/player.gd").new()
	var head := Node3D.new()
	head.name = "Head"
	head.position.y = 1.65
	var camera := Camera3D.new()
	camera.name = "Camera3D"
	head.add_child(camera)
	player.add_child(head)
	root.add_child(player)
	player.set_physics_process(false)
	player.position = Vector3(4, 1.2, 4)
	var inventory := ItemInventory.new(1)
	var drops = load("res://game/item_drops.gd").new()
	root.add_child(drops)
	drops.setup(world, player, inventory)
	drops.set_physics_process(false)
	var stone := BlockRegistry.BLOCK_STONE
	inventory.add_item(stone, 63)
	drops.spawn_drop(Vector3(4, 2, 4), {"id": stone, "count": 5})
	drops._drops[0].velocity = Vector3.ZERO
	var on_credit := func() -> void:
		_expect(inventory.count_item(stone) + _count(drops) == 68, "save during inventory notification has consistent ownership")
	inventory.changed.connect(on_credit)
	_tick(drops, 3)
	_expect(inventory.count_item(stone) == 63 and _count(drops) == 5, "throw delay prevents instant pickup credit")
	_tick(drops, 40)
	inventory.changed.disconnect(on_credit)
	_expect(inventory.count_item(stone) == 64 and _count(drops) == 4, "partial pickup retains exact overflow")
	_tick(drops, 100)
	_expect(inventory.count_item(stone) == 64 and _count(drops) == 4, "full inventory never loses or duplicates drops")
	inventory.remove_at(0, 64)
	_tick(drops, 40)
	_expect(inventory.count_item(stone) == 4 and drops.persistent_state().is_empty(), "overflow picked up after capacity opens")

	inventory.restore([])
	var tool := ItemRegistry.ITEM_IRON_PICKAXE
	drops.spawn_drop(Vector3(4, 2, 4), {"id": tool, "count": 2, "durability": 17})
	drops._drops[0].velocity = Vector3.ZERO
	_tick(drops, 40)
	_expect(inventory.slots[0].get("durability") == 17 and inventory.count_item(tool) == 1 \
		and _count(drops) == 1, "tools remain unstacked and preserve wear")
	var state: Array = drops.persistent_state()
	var serialized: Array = JSON.parse_string(JSON.stringify(state))
	drops.restore(serialized)
	var restored: Array = drops.persistent_state()
	var saved_position: Array = serialized[0].position
	_expect(restored[0].stack.id == int(serialized[0].stack.id) \
		and restored[0].stack.count == int(serialized[0].stack.count) \
		and restored[0].stack.durability == int(serialized[0].stack.durability) \
		and Vector3(drops._drops[0].position).is_equal_approx( \
		Vector3(saved_position[0], saved_position[1], saved_position[2])), "JSON persistence retains position, count and durability")
	state[0].stack.count = 99
	_expect(_count(drops) == 1, "persistent snapshots do not alias live stacks")
	drops.restore(serialized)
	_expect(_count(drops) == 1, "restore replaces rather than duplicates")
	inventory.restore([])
	player.dead = true
	_tick(drops, 40)
	_expect(inventory.count_item(tool) == 0 and _count(drops) == 1, "dead player cannot pick up")
	player.dead = false
	paused = true
	var before: Array = drops.persistent_state()
	_tick(drops, 20)
	_expect(drops.persistent_state() == before and inventory.count_item(tool) == 0, "paused simulation cannot move or credit")
	paused = false
	world.resident = false
	_tick(drops, 30)
	_expect(drops.persistent_state() == before and inventory.count_item(tool) == 0, "unloaded drop freezes without pickup")
	world.resident = true
	_tick(drops, 40)
	_expect(inventory.count_item(tool) == 1 and inventory.slots[0].durability == 17, "restored worn tool eventually collected")

	player.dead = true
	drops.spawn_drop(Vector3(6, 8, 6), {"id": stone, "count": 3})
	_expect(drops._drops[0].velocity.y > 0.0, "spawn applies throwing impulse")
	drops._drops[0].velocity = Vector3(1, -200, 0)
	drops._physics_process(1.0)
	_tick(drops, 100)
	var at: Vector3 = drops._drops[0].position
	_expect(at.y >= 1.0 + drops.RADIUS and at.y < 1.3 and at.x > 6.0, "substeps move laterally and cannot tunnel through floor")
	_expect(Vector3(drops._drops[0].velocity).length() < 0.001, "ground friction settles throw")
	before = drops.persistent_state()
	player.position = Vector3(1000, 2, 1000)
	_tick(drops, 100)
	_expect(drops.persistent_state() == before, "far-away physics freezes without expiry")
	player.position = Vector3(4, 1.2, 4)
	drops._drops[0].position = Vector3(15.5, 4, 6)
	drops._drops[0].velocity = Vector3(100, 0, 0)
	drops._physics_process(0.1)
	_expect(drops._drops[0].position.x + drops.RADIUS < 16.0, "sweep cannot enter an unloaded neighboring chunk")
	world.wall = true
	drops._drops[0].position = Vector3(7, 2, 4)
	drops._drops[0].velocity = Vector3(100, 0, 0)
	drops._physics_process(0.1)
	_expect(drops._drops[0].position.x + drops.RADIUS < 8.0, "sweep cannot tunnel through voxel wall")
	player.dead = false
	player.position = Vector3(9, 1.2, 4)
	drops._drops[0].position = Vector3(7.6, 2, 4)
	drops._drops[0].age = 2.0
	inventory.restore([])
	_tick(drops, 40)
	_expect(inventory.count_item(stone) == 0 and _count(drops) == 3, "magnet cannot collect through wall")
	world.wall = false
	_tick(drops, 40)
	_expect(inventory.count_item(stone) == 3 and _count(drops) == 0, "magnet resumes when obstruction is removed")

	drops.restore([{}, {"position": [0, 0], "stack": {}}, {"position": [NAN, 2, 3], "stack": {"id": stone, "count": 1}}])
	_expect(drops.persistent_state().is_empty(), "malformed positions are rejected")
	drops.free()
	player.free()
	world.free()
	print("item_drops_verify: %d failures" % failures)
	quit(1 if failures else 0)


func _tick(drops: Node, count: int) -> void:
	for tick in count:
		drops._physics_process(0.05)


func _count(drops: Node) -> int:
	var count := 0
	for entry in drops.persistent_state():
		count += int(entry.stack.count)
	return count


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
