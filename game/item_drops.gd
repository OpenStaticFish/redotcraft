class_name ItemDrops
extends Node3D

const ACTIVE_DISTANCE := 48.0
const MAGNET_DISTANCE := 2.4
const RADIUS := 0.16
const STEP := 0.08
const PICKUP_DELAY := 0.6

var _world: VoxelWorld
var _player: Player
var _inventory: ItemInventory
var _drops: Array[Dictionary] = []


func setup(world: VoxelWorld, player: Player, inventory: ItemInventory) -> void:
	_world = world
	_player = player
	_inventory = inventory
	process_mode = Node.PROCESS_MODE_PAUSABLE


## Positions are world-space cube centers; the caller transfers ownership of stack.
func spawn_drop(position: Vector3, stack: Dictionary) -> void:
	var id := int(stack.get("id", 0))
	var count := int(stack.get("count", 0))
	if not position.is_finite() or not ItemRegistry.is_valid(id) or count <= 0:
		return
	var maximum := ItemRegistry.max_durability(id)
	var durability := int(stack.get("durability", maximum))
	durability = maximum if durability < 0 else clampi(durability, 0, maximum)
	if maximum > 0 and durability == 0:
		return
	_drops.append({"position": position,
		"stack": {"id": id, "count": count, "durability": durability},
		"velocity": Vector3(randf_range(-1.8, 1.8), 3.0, randf_range(-1.8, 1.8)),
		"age": 0.0, "phase": randf() * TAU, "visual": null})


func persistent_state() -> Array:
	var state: Array = []
	for drop in _drops:
		if int(drop.stack.count) <= 0:
			continue
		var at: Vector3 = drop.position
		state.append({"position": [at.x, at.y, at.z], "stack": drop.stack.duplicate(true)})
	return state


## Replaces existing drops. Motion is deliberately restarted at rest on load.
func restore(state: Array) -> void:
	for drop in _drops:
		if is_instance_valid(drop.visual):
			drop.visual.queue_free()
	_drops.clear()
	for entry in state:
		if not entry is Dictionary or not entry.get("stack") is Dictionary:
			continue
		var coordinates: Variant = entry.get("position")
		if not coordinates is Array or coordinates.size() != 3:
			continue
		if not coordinates.all(func(value: Variant) -> bool: return value is float or value is int):
			continue
		var previous := _drops.size()
		spawn_drop(Vector3(coordinates[0], coordinates[1], coordinates[2]), entry.stack)
		if _drops.size() > previous:
			_drops.back().velocity = Vector3.ZERO


func _physics_process(delta: float) -> void:
	if _world == null or not is_instance_valid(_player) or _inventory == null \
			or get_tree().paused or delta <= 0.0 or not is_finite(delta):
		return
	# Cap catch-up work after a stall, not the number or lifetime of stored drops.
	var dt := minf(delta, 0.1)
	var target := _player.global_position + Vector3.UP * 0.8
	for index in range(_drops.size() - 1, -1, -1):
		var drop := _drops[index]
		var nearby: bool = drop.position.distance_squared_to(target) <= ACTIVE_DISTANCE * ACTIVE_DISTANCE
		if is_instance_valid(drop.visual):
			drop.visual.visible = nearby
		if not nearby or not _resident(drop.position):
			continue
		drop.age += dt
		var capacity := _capacity(drop.stack) if not _player.dead else 0
		var magnet: bool = capacity > 0 and drop.age >= PICKUP_DELAY \
			and drop.position.distance_to(target) < MAGNET_DISTANCE
		if magnet:
			var offset: Vector3 = target - Vector3(drop.position)
			drop.velocity = offset.normalized() * minf(7.0, offset.length() / dt)
		else:
			drop.velocity.y = maxf(-24.0, float(drop.velocity.y) - 18.0 * dt)
		_move(drop, dt)
		if magnet and drop.position.distance_to(target) < 0.22:
			var amount := mini(capacity, int(drop.stack.count))
			# Update ownership before add_item emits changed (listeners may save).
			drop.stack.count -= amount
			drop.stack.count += _inventory.add_item(int(drop.stack.id), amount, int(drop.stack.durability))
			if int(drop.stack.count) == 0:
				if is_instance_valid(drop.visual):
					drop.visual.queue_free()
				_drops.remove_at(index)
				continue
		if not is_instance_valid(drop.visual):
			drop.visual = _make_visual(int(drop.stack.id))
		var visual: Node3D = drop.visual
		visual.global_position = drop.position + Vector3.UP * (0.06 + sin(float(drop.age) * 3.0 + float(drop.phase)) * 0.04)
		visual.rotation.y = float(drop.age) * 1.6 + float(drop.phase)


func _capacity(stack: Dictionary) -> int:
	var capacity := 0
	var limit := ItemRegistry.stack_limit(int(stack.id))
	for slot in _inventory.slots:
		if slot.is_empty():
			capacity += limit
		elif int(slot.id) == int(stack.id) and int(slot.durability) == int(stack.durability):
			capacity += maxi(0, limit - int(slot.count))
	return capacity


func _resident(at: Vector3) -> bool:
	# get_block_world returns air for missing/LOD chunks; never simulate that air.
	for x in [-RADIUS, RADIUS]:
		for z in [-RADIUS, RADIUS]:
			if not _world.is_collision_ready_at(at + Vector3(x, 0, z)):
				return false
	return true


func _blocked(at: Vector3) -> bool:
	var low := Vector3i((at - Vector3.ONE * RADIUS).floor())
	var high := Vector3i((at + Vector3.ONE * RADIUS).floor())
	var registry := _world.get_registry()
	for x in range(low.x, high.x + 1):
		for y in range(low.y, high.y + 1):
			for z in range(low.z, high.z + 1):
				var id := _world.get_block_world(Vector3i(x, y, z))
				if y < 0 or (id != BlockRegistry.BLOCK_AIR and not registry.is_water_id(id) \
						and not registry.has_flag(id, BlockRegistry.FLAG_CROSS)):
					return true
	return false


func _move(drop: Dictionary, dt: float) -> void:
	var motion: Vector3 = drop.velocity * dt
	var steps := maxi(1, ceili(motion.length() / STEP))
	var step := motion / float(steps)
	for substep in steps:
		for axis in [1, 0, 2]:
			if step[axis] == 0.0:
				continue
			var next: Vector3 = drop.position
			next[axis] += step[axis]
			if not _resident(next):
				return
			if _blocked(next):
				if axis == 1 and step.y < 0.0:
					drop.velocity.x = move_toward(float(drop.velocity.x), 0.0, 12.0 * dt)
					drop.velocity.z = move_toward(float(drop.velocity.z), 0.0, 12.0 * dt)
				drop.velocity[axis] = 0.0
				step[axis] = 0.0
			else:
				drop.position = next


func _make_visual(id: int) -> Node3D:
	var visual := Node3D.new()
	add_child(visual)
	if not ItemRegistry.is_item(id):
		var cube := MeshInstance3D.new()
		cube.mesh = _world.make_block_mesh(id)
		cube.scale = Vector3.ONE * 0.24
		visual.add_child(cube)
	else:
		var texture := ItemRegistry.make_icon(id)
		var icon := Sprite3D.new()
		icon.texture = texture
		icon.pixel_size = 0.34 / float(texture.get_width())
		icon.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		icon.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		visual.add_child(icon)
	return visual
