class_name Player
extends CharacterBody3D

signal block_broken(block_id: int)
signal block_placed(block_id: int)
signal item_used(item_id: int, block_position: Vector3i)
signal status_requested(message: String)
signal slot_cycled(direction: int)
signal slot_selected(index: int)
signal pause_requested
signal died(cause: String)
signal vitals_changed()
signal block_picked(block_id: int)
signal block_interacted(position: Vector3i)
signal mined_block(position: Vector3i, block_id: int, harvest: bool)

const WALK_SPEED := 4.6
const SPRINT_SPEED := 6.8
const JUMP_VELOCITY := 8.4
const GRAVITY := 26.0
const GROUND_ACCEL := 55.0
const AIR_ACCEL := 16.0
const REACH := 6.0
const FLY_SPEED := 11.0
const FLY_ACCEL := 45.0
const FLY_BOOST_MULTIPLIER := 5.0
const DOUBLE_TAP_TIME := 0.32
const FALL_RESET_Y := -20.0
const SPRINT_FOV_BOOST := 6.0
const FOV_LERP_SPEED := 8.0
const FOOTSTEP_STRIDE := 1.7
const FOOTSTEP_MIN_SPEED := 0.6
const MAX_HEALTH := 20.0
const MAX_HUNGER := 20.0
const MAX_AIR := 10.0
const CROUCH_SPEED := 1.8

var world: VoxelWorld
var game_mode: int = GameMode.SURVIVAL
var can_place_check: Callable = Callable()
var interact_check: Callable = Callable()
var health := MAX_HEALTH
var hunger := MAX_HUNGER
var air := MAX_AIR
var dead := false
var crouching := false
var third_person := false
var mining_progress := 0.0
var _mining := false
var _mining_position := Vector3i.ZERO
var _mining_id := 0
var _mining_tool := 0
var _survival_clock := 0.0
var _regen_clock := 0.0
var _fall_start := NAN
var _head_height := 1.65
var _effects: PlayerEffects
var selected_block := 1
var target_block := Vector3i.ZERO
var target_normal := Vector3i.UP
var has_target := false
var spawn_position := Vector3.ZERO
var flying := false
var base_fov := 76.0
var pitch_limit := deg_to_rad(85.0)
var _last_jump_time := -10.0
var _footstep_distance := 0.0
var _highlight: MeshInstance3D
var _held_block: MeshInstance3D

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D


func _ready() -> void:
	camera.current = true
	_head_height = head.position.y
	_effects = PlayerEffects.new()
	add_child(_effects)
	_effects.setup(self)
	spawn_position = global_position
	apply_settings()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func apply_settings() -> void:
	set_fov(GameConfig.get_fov())


func set_fov(value: float) -> void:
	base_fov = value
	if camera:
		camera.fov = base_fov


func setup_world(world_node: VoxelWorld) -> void:
	world = world_node
	_create_highlight()
	_create_held_block()
	_update_held_block()


func set_selected_block(block_id: int) -> void:
	if selected_block != block_id:
		cancel_mining()
	selected_block = block_id
	_update_held_block()


func persistent_state() -> Dictionary:
	# During scene shutdown children can already be detached when Main performs
	# its final save. A detached Node3D has no global transform; Player is a
	# direct child of the identity gameplay root, so its local position is the
	# correct fallback and avoids get_global_transform() shutdown errors.
	var saved_position := global_position if is_inside_tree() else position
	return {
		"position": [saved_position.x, saved_position.y, saved_position.z],
		"yaw": rotation.y,
		"pitch": head.rotation.x if head != null else 0.0,
		"flying": flying,
		"health": health,
		"hunger": hunger,
		"air": air,
		"dead": dead,
		"spawn": [spawn_position.x, spawn_position.y, spawn_position.z],
	}


func restore_persistent_state(state: Dictionary) -> bool:
	var position_value: Variant = state.get("position", [])
	if typeof(position_value) != TYPE_ARRAY or position_value.size() != 3:
		return false
	var restored := Vector3(float(position_value[0]), float(position_value[1]), float(position_value[2]))
	if not is_finite(restored.x) or not is_finite(restored.y) or not is_finite(restored.z):
		return false
	if restored.y < 0.0 and (game_mode == GameMode.CREATIVE or (
			not bool(state.get("dead", false))
			and _restore_vital(state.get("health", MAX_HEALTH), MAX_HEALTH) > 0.0)):
		return false
	global_position = restored
	rotation.y = float(state.get("yaw", 0.0))
	if head != null:
		head.rotation.x = clampf(float(state.get("pitch", 0.0)), -pitch_limit, pitch_limit)
	flying = game_mode == GameMode.CREATIVE and bool(state.get("flying", false))
	health = _restore_vital(state.get("health", MAX_HEALTH), MAX_HEALTH)
	hunger = _restore_vital(state.get("hunger", MAX_HUNGER), MAX_HUNGER)
	air = _restore_vital(state.get("air", MAX_AIR), MAX_AIR)
	dead = bool(state.get("dead", false)) or health <= 0.0
	if game_mode == GameMode.CREATIVE:
		health = MAX_HEALTH
		hunger = MAX_HUNGER
		air = MAX_AIR
		dead = false
	if dead:
		health = 0.0
	_reset_survival_motion()
	velocity = Vector3.ZERO
	var spawn_value: Variant = state.get("spawn", [])
	if typeof(spawn_value) == TYPE_ARRAY and spawn_value.size() == 3:
		var restored_spawn := Vector3(float(spawn_value[0]), float(spawn_value[1]), float(spawn_value[2]))
		if is_finite(restored_spawn.x) and is_finite(restored_spawn.y) and is_finite(restored_spawn.z) \
				and restored_spawn.y >= 0.0:
			spawn_position = restored_spawn
		else:
			spawn_position = restored
	else:
		spawn_position = restored
	vitals_changed.emit()
	return true


func _restore_vital(value: Variant, maximum: float) -> float:
	if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
		return maximum
	var number := float(value)
	return clampf(number, 0.0, maximum) if is_finite(number) else maximum


func take_damage(amount: float, cause: String = "injury") -> void:
	if game_mode == GameMode.CREATIVE or dead or not is_finite(amount) or amount <= 0.0:
		return
	health = maxf(0.0, health - amount)
	if health <= 0.0:
		dead = true
		_reset_survival_motion()
		if _highlight != null:
			_highlight.hide()
		if _held_block != null:
			_held_block.hide()
	vitals_changed.emit()
	if dead:
		died.emit(cause)


## Returns false when food should not be consumed by the inventory owner.
func eat(amount: float) -> bool:
	if game_mode == GameMode.CREATIVE or dead or not is_finite(amount) or amount <= 0.0 or hunger >= MAX_HUNGER:
		return false
	hunger = minf(MAX_HUNGER, hunger + amount)
	vitals_changed.emit()
	return true


func respawn() -> void:
	_reset_survival_motion()
	flying = false
	crouching = false
	global_position = spawn_position
	if world != null:
		world.setup_player(self, true)
		global_position = world.find_safe_spawn(spawn_position)
		world.setup_player(self, true)
	health = MAX_HEALTH
	hunger = MAX_HUNGER
	air = MAX_AIR
	dead = false
	vitals_changed.emit()


func _reset_survival_motion() -> void:
	velocity = Vector3.ZERO
	_fall_start = NAN
	_survival_clock = 0.0
	_regen_clock = 0.0
	_last_jump_time = -10.0
	cancel_mining()


## Detached photo-mode camera: freeze player simulation and hide the targeting
## highlight and the first-person held block so the composition cannot be
## disturbed or the hand model caught in the shot.
func set_photo_mode(enabled: bool) -> void:
	cancel_mining()
	process_mode = Node.PROCESS_MODE_DISABLED if enabled else Node.PROCESS_MODE_INHERIT
	if enabled and _highlight != null:
		_highlight.visible = false
	if _held_block != null:
		_held_block.visible = not enabled and not third_person and selected_block != BlockRegistry.BLOCK_AIR


func _unhandled_input(event: InputEvent) -> void:
	if dead:
		return
	if event.is_action_pressed("pick_block") and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_pick_target()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		cancel_mining()
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sensitivity := GameConfig.get_mouse_sensitivity()
		rotation.y -= event.relative.x * sensitivity
		head.rotation.x = clampf(head.rotation.x - event.relative.y * sensitivity, -pitch_limit, pitch_limit)
		return

	if event is InputEventMouseButton and event.pressed:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
			return
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				slot_cycled.emit(-1)
				get_viewport().set_input_as_handled()
			MOUSE_BUTTON_WHEEL_DOWN:
				slot_cycled.emit(1)
				get_viewport().set_input_as_handled()
			MOUSE_BUTTON_LEFT:
				_break_target()
				get_viewport().set_input_as_handled()
			MOUSE_BUTTON_RIGHT:
				_place_target()
				get_viewport().set_input_as_handled()
		return

	if event is InputEventKey and event.pressed and not event.echo:
		if event.is_action_pressed("ui_cancel"):
			pause_requested.emit()
			get_viewport().set_input_as_handled()
		elif event.keycode >= KEY_1 and event.keycode <= KEY_9:
			slot_selected.emit(event.keycode - KEY_1)
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_0:
			slot_selected.emit(9)
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("jump"):
			_handle_double_tap_jump()
		elif event.is_action_pressed("third_person"):
			third_person = not third_person
			cancel_mining()


func _physics_process(delta: float) -> void:
	if dead:
		return
	if global_position.y < FALL_RESET_Y:
		if game_mode == GameMode.CREATIVE:
			respawn()
		else:
			take_damage(MAX_HEALTH, "void")
		return
	crouching = not flying and Input.is_action_pressed("crouch")
	head.position.y = _head_height - (0.35 if crouching else 0.0)
	_effects.update_view(delta)
	# Never simulate movement in a chunk whose collision has not committed yet.
	# Extreme streaming and boosted flight can otherwise outrun the nearest-first
	# worker queue; a flying player could then descend straight through visible
	# terrain while the authoritative collision shape was still being built.
	if world != null and not world.is_collision_ready_at(global_position):
		velocity = Vector3.ZERO
		_fall_start = NAN
		cancel_mining()
		has_target = false
		if _highlight != null:
			_highlight.hide()
		return
	_update_target()
	_update_survival(delta)
	if dead:
		return
	if _mining and (not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED):
		cancel_mining()
	if not _mining and has_target and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_break_target()
	_tick_mining(delta)
	var input_vector := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var direction := Vector3(input_vector.x, 0.0, input_vector.y).rotated(Vector3.UP, rotation.y)
	if direction.length_squared() > 1.0:
		direction = direction.normalized()
	var sprinting := false
	if flying:
		var vertical := Input.get_action_strength("fly_up") - Input.get_action_strength("fly_down")
		var boost := FLY_BOOST_MULTIPLIER if Input.is_action_pressed("fly_boost") else 1.0
		var fly_speed := FLY_SPEED * boost
		var fly_accel := FLY_ACCEL * boost
		velocity.x = move_toward(velocity.x, direction.x * fly_speed, fly_accel * delta)
		velocity.y = move_toward(velocity.y, vertical * fly_speed, fly_accel * delta)
		velocity.z = move_toward(velocity.z, direction.z * fly_speed, fly_accel * delta)
	else:
		sprinting = not crouching and hunger > 6.0 and Input.is_action_pressed("sprint") and input_vector.length_squared() > 0.01
		var speed := CROUCH_SPEED if crouching else (SPRINT_SPEED if sprinting else WALK_SPEED)
		var acceleration := GROUND_ACCEL if is_on_floor() else AIR_ACCEL
		velocity.x = move_toward(velocity.x, direction.x * speed, acceleration * delta)
		velocity.z = move_toward(velocity.z, direction.z * speed, acceleration * delta)
		if _on_ladder():
			var climb := Input.get_action_strength("move_forward") - Input.get_action_strength("move_backward")
			if Input.is_action_pressed("jump"):
				climb = 1.0
			elif crouching:
				climb = -1.0
			velocity.y = move_toward(velocity.y, climb * WALK_SPEED, GROUND_ACCEL * delta)
			_fall_start = NAN
		elif not is_on_floor():
			velocity.y -= GRAVITY * delta
		elif Input.is_action_just_pressed("jump"):
			velocity.y = JUMP_VELOCITY
		else:
			velocity.y = -0.5
	if crouching and is_on_floor():
		_protect_edge(delta)
	if world != null:
		var intended_position := global_position + velocity * delta
		var loaded_fraction := world.loaded_motion_fraction(global_position, intended_position)
		if loaded_fraction < 1.0:
			var x_fraction := world.loaded_motion_fraction(global_position,
				global_position + Vector3(velocity.x * delta, 0.0, 0.0))
			var z_fraction := world.loaded_motion_fraction(global_position,
				global_position + Vector3(0.0, 0.0, velocity.z * delta))
			if x_fraction < 1.0 or z_fraction < 1.0:
				velocity.x *= x_fraction
				velocity.z *= z_fraction
			# At an exact corner both cardinal chunks can be ready while the
			# diagonal is not. Keep the dominant axis so movement slides along
			# the loaded edge instead of entering the missing diagonal chunk.
			elif absf(velocity.x) >= absf(velocity.z):
				velocity.z = 0.0
			else:
				velocity.x = 0.0
		# Entering a rendered chunk is allowed even if its approach collision
		# rebuild is one frame behind, but neither gravity nor flight descent may
		# spend that frame crossing its uncommitted floor. The next tick pauses all
		# movement until collision is ready.
		var constrained_position := global_position + velocity * delta
		if velocity.y < 0.0 and not world.is_collision_ready_at(constrained_position):
			velocity.y = 0.0
	var was_grounded := is_on_floor()
	if flying or _water_at(global_position + Vector3.UP * 0.1):
		_fall_start = NAN
	elif not was_grounded:
		_fall_start = global_position.y if is_nan(_fall_start) else maxf(_fall_start, global_position.y)
	move_and_slide()
	if not flying and is_on_floor() and not is_nan(_fall_start):
		var distance := _fall_start - global_position.y
		_fall_start = NAN
		if distance > 3.0 and not _water_at(global_position + Vector3.UP * 0.1):
			take_damage(floorf(distance - 3.0), "fall")
	if camera:
		var target_fov := base_fov + SPRINT_FOV_BOOST if sprinting and direction.length_squared() > 0.0 else base_fov
		camera.fov = lerpf(camera.fov, target_fov, clampf(delta * FOV_LERP_SPEED, 0.0, 1.0))
	_update_footsteps(delta)


## Distance-based footsteps pick a material from the block under the player.
## The half-stride reset after landing or takeoff stops steps from bunching.
func _update_footsteps(delta: float) -> void:
	if world == null or not is_on_floor():
		_footstep_distance = FOOTSTEP_STRIDE * 0.5
		return
	var speed := Vector2(velocity.x, velocity.z).length()
	if speed < FOOTSTEP_MIN_SPEED:
		return
	_footstep_distance += speed * delta
	if _footstep_distance < FOOTSTEP_STRIDE:
		return
	_footstep_distance = 0.0
	var block := _ground_block_below()
	if block == BlockRegistry.BLOCK_AIR:
		return
	AudioManager.play_footstep(AudioManager.material_for_block(block),
		Vector3(global_position.x, global_position.y - 0.2, global_position.z))


func _ground_block_below() -> int:
	var x := floori(global_position.x)
	var z := floori(global_position.z)
	var y := floori(global_position.y - 0.1)
	for probe in range(2):
		var block := world.get_block_world(Vector3i(x, y - probe, z))
		if block != BlockRegistry.BLOCK_AIR:
			return block
	return BlockRegistry.BLOCK_AIR


func _update_target() -> void:
	if world == null:
		return
	has_target = false
	var result := _voxel_raycast(head.global_position, -camera.global_transform.basis.z, REACH)
	if result.is_empty():
		_highlight.visible = false
		return
	target_block = result["block"]
	target_normal = result["normal"]
	has_target = true
	_highlight.global_position = Vector3(target_block) + Vector3(0.5, 0.5, 0.5)
	_highlight.visible = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED


## Grid traversal targets rendered voxels directly instead of depending on
## collision geometry. Cross plants stay non-solid to movement but can still be
## selected, broken, and used as the face reference for block placement.
func _voxel_raycast(origin: Vector3, direction_value: Vector3, max_distance: float) -> Dictionary:
	var direction := direction_value.normalized()
	var cell := Vector3i(floori(origin.x), floori(origin.y), floori(origin.z))
	var step := Vector3i(
		1 if direction.x > 0.0 else (-1 if direction.x < 0.0 else 0),
		1 if direction.y > 0.0 else (-1 if direction.y < 0.0 else 0),
		1 if direction.z > 0.0 else (-1 if direction.z < 0.0 else 0))
	var delta := Vector3(
		absf(1.0 / direction.x) if step.x != 0 else INF,
		absf(1.0 / direction.y) if step.y != 0 else INF,
		absf(1.0 / direction.z) if step.z != 0 else INF)
	var next := Vector3(
		(float(cell.x + 1) - origin.x) / direction.x if step.x > 0 else ((origin.x - float(cell.x)) / -direction.x if step.x < 0 else INF),
		(float(cell.y + 1) - origin.y) / direction.y if step.y > 0 else ((origin.y - float(cell.y)) / -direction.y if step.y < 0 else INF),
		(float(cell.z + 1) - origin.z) / direction.z if step.z > 0 else ((origin.z - float(cell.z)) / -direction.z if step.z < 0 else INF))
	var entered_from := Vector3i.ZERO
	var distance := 0.0
	while distance <= max_distance:
		var block_id := world.get_block_world(cell)
		var water: bool = block_id == BlockRegistry.BLOCK_WATER \
			or (block_id >= BlockRegistry.BLOCK_WATER_FLOW_7 and block_id <= BlockRegistry.BLOCK_WATER_FLOW_1)
		if block_id != BlockRegistry.BLOCK_AIR and not water:
			return {"block": cell, "normal": entered_from}
		if next.x <= next.y and next.x <= next.z:
			cell.x += step.x
			distance = next.x
			next.x += delta.x
			entered_from = Vector3i(-step.x, 0, 0)
		elif next.y <= next.z:
			cell.y += step.y
			distance = next.y
			next.y += delta.y
			entered_from = Vector3i(0, -step.y, 0)
		else:
			cell.z += step.z
			distance = next.z
			next.z += delta.z
			entered_from = Vector3i(0, 0, -step.z)
	return {}


func _pick_target() -> void:
	if not dead and has_target and world != null:
		block_picked.emit(BlockRegistry.canonical_id(world.get_block_world(target_block)))


func _break_target() -> void:
	if dead or not has_target or world == null:
		return
	_mining = true
	_mining_position = target_block
	_mining_id = world.get_block_world(target_block)
	_mining_tool = selected_block
	mining_progress = 0.0
	if game_mode == GameMode.CREATIVE:
		_tick_mining(0.0)


func cancel_mining() -> void:
	_mining = false
	mining_progress = 0.0
	if _effects != null:
		_effects.hide_cracks()


func _tick_mining(delta: float) -> void:
	if not _mining or dead or world == null:
		return
	if not has_target or target_block != _mining_position or selected_block != _mining_tool \
			or world.get_block_world(target_block) != _mining_id:
		cancel_mining()
		return
	var seconds := BlockRegistry.break_seconds(_mining_id, _mining_tool)
	if seconds < 0.0 or not is_finite(seconds):
		cancel_mining()
		return
	mining_progress = 1.0 if game_mode == GameMode.CREATIVE else minf(1.0, mining_progress + delta / maxf(0.05, seconds))
	if _effects != null:
		_effects.show_cracks(_mining_position, mining_progress)
	if mining_progress < 1.0:
		return
	var position_mined := _mining_position
	var harvest := BlockRegistry.can_harvest(_mining_id, _mining_tool)
	cancel_mining()
	var removed := world.break_block(position_mined)
	if removed == BlockRegistry.BLOCK_AIR:
		return
	if _effects != null:
		_effects.burst(position_mined)
	block_broken.emit(removed)
	mined_block.emit(position_mined, removed, harvest)
	AudioManager.play_block_break(removed, Vector3(position_mined) + Vector3(0.5, 0.5, 0.5))


func _place_target() -> void:
	if dead or world == null:
		return
	cancel_mining()
	if has_target and interact_check.is_valid() and interact_check.call(target_block):
		block_interacted.emit(target_block)
		return
	if selected_block == BlockRegistry.BLOCK_AIR:
		return
	if ItemRegistry.food_value(selected_block) > 0.0:
		item_used.emit(selected_block, target_block if has_target else Vector3i.ZERO)
		return
	if not has_target:
		return
	if can_place_check.is_valid() and not can_place_check.call():
		status_requested.emit("No %s left" % _selected_name())
		return
	if ItemRegistry.is_item(selected_block):
		item_used.emit(selected_block, target_block)
		return
	var place_position := target_block + target_normal
	if _player_occupies(place_position):
		return
	if BlockRegistry.canonical_id(selected_block) == BlockRegistry.BLOCK_WOOD_DOOR \
			and _player_occupies(place_position + Vector3i.UP):
		return
	if world.place_block(place_position, selected_block, _placement_facing(), target_normal):
		block_placed.emit(selected_block)
		AudioManager.play_block_place(selected_block, Vector3(place_position) + Vector3(0.5, 0.5, 0.5))


func _placement_facing() -> int:
	var forward := -global_transform.basis.z
	if absf(forward.x) > absf(forward.z):
		return BlockRegistry.FACING_EAST if forward.x > 0.0 else BlockRegistry.FACING_WEST
	return BlockRegistry.FACING_SOUTH if forward.z > 0.0 else BlockRegistry.FACING_NORTH


func _on_ladder() -> bool:
	if world == null:
		return false
	var feet := world.get_block_world(Vector3i((global_position + Vector3.UP * 0.2).floor()))
	var chest := world.get_block_world(Vector3i((global_position + Vector3.UP * 1.1).floor()))
	for block_id in [feet, chest]:
		if not BlockRegistry.is_ladder(block_id):
			continue
		var local := Vector2(fposmod(global_position.x, 1.0), fposmod(global_position.z, 1.0))
		match BlockRegistry.facing(block_id):
			BlockRegistry.FACING_NORTH:
				return local.y < 0.4
			BlockRegistry.FACING_EAST:
				return local.x > 0.6
			BlockRegistry.FACING_SOUTH:
				return local.y > 0.6
			BlockRegistry.FACING_WEST:
				return local.x < 0.4
	return false


func _handle_double_tap_jump() -> void:
	if game_mode != GameMode.CREATIVE or dead:
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_jump_time <= DOUBLE_TAP_TIME:
		flying = not flying
		velocity.y = 0.0
		_fall_start = NAN
		_last_jump_time = -10.0
		status_requested.emit("Flying enabled" if flying else "Flying disabled")
	else:
		_last_jump_time = now


func _create_highlight() -> void:
	_highlight = MeshInstance3D.new()
	_highlight.name = "TargetHighlight"
	var mesh := BoxMesh.new()
	mesh.size = Vector3(1.01, 1.01, 1.01)
	_highlight.mesh = mesh
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.08, 0.08, 0.08, 0.28)
	_highlight.material_override = material
	_highlight.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_highlight.visible = false
	world.add_child(_highlight)


func _create_held_block() -> void:
	_held_block = MeshInstance3D.new()
	_held_block.name = "HeldBlock"
	_held_block.position = Vector3(0.62, -0.55, -1.05)
	_held_block.rotation_degrees = Vector3(-12.0, -22.0, 12.0)
	_held_block.scale = Vector3(0.43, 0.43, 0.43)
	_held_block.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	camera.add_child(_held_block)


func _update_held_block() -> void:
	if _held_block and world:
		_held_block.visible = not third_person and selected_block != BlockRegistry.BLOCK_AIR
		if ItemRegistry.is_item(selected_block):
			var tool_mesh := BoxMesh.new()
			tool_mesh.size = Vector3(0.18, 1.2, 0.18)
			_held_block.mesh = tool_mesh
			var tool_material := StandardMaterial3D.new()
			tool_material.albedo_color = Color(0.55, 0.36, 0.19)
			_held_block.material_override = tool_material
			return
		_held_block.mesh = world.make_block_mesh(selected_block)
		_held_block.material_override = world.get_blocks_material()


func _selected_name() -> String:
	if ItemRegistry.is_item(selected_block):
		return ItemRegistry.get_item_name(selected_block)
	return world.get_block_name(selected_block)


func _player_occupies(block_position: Vector3i) -> bool:
	var block_box := AABB(Vector3(block_position), Vector3.ONE)
	var player_box := AABB(global_position + Vector3(-0.34, 0.05, -0.34), Vector3(0.68, 1.85, 0.68))
	return block_box.intersects(player_box)


func _head_in_water() -> bool:
	return head != null and _water_at(head.global_position)


func _water_at(at: Vector3) -> bool:
	if world == null:
		return false
	var cell := Vector3i(at.floor())
	var id := world.get_block_world(cell)
	var registry := world.get_registry()
	if registry != null and registry.has_flag(id, BlockRegistry.FLAG_CROSS):
		id = world.get_block_world(cell + Vector3i.UP)
	return id == BlockRegistry.BLOCK_WATER or (id >= BlockRegistry.BLOCK_WATER_FLOW_7 and id <= BlockRegistry.BLOCK_WATER_FLOW_1)


func _update_survival(delta: float) -> void:
	if game_mode == GameMode.CREATIVE or dead or world == null or world.get_registry() == null:
		return
	var previous := Vector3(health, hunger, air)
	var moving := Vector2(velocity.x, velocity.z).length() > 0.6
	var draining := 0.004
	if moving and not flying:
		draining = 0.06 if Input.is_action_pressed("sprint") and not crouching else 0.02
	hunger = maxf(0.0, hunger - delta * draining)
	var submerged := _head_in_water()
	air = maxf(0.0, air - delta) if submerged else minf(MAX_AIR, air + delta * 4.0)
	_survival_clock += delta
	while _survival_clock >= 1.0 and not dead:
		_survival_clock -= 1.0
		var feet_id := world.get_block_world(Vector3i((global_position + Vector3.UP * 0.1).floor()))
		var ground_cell := Vector3i((global_position - Vector3.UP * 0.1).floor())
		var ground_id := world.get_block_world(ground_cell)
		var head_id := world.get_block_world(Vector3i(head.global_position.floor()))
		if feet_id == BlockRegistry.BLOCK_LAVA or head_id == BlockRegistry.BLOCK_LAVA or ground_id == BlockRegistry.BLOCK_LAVA:
			take_damage(4.0, "lava")
		elif feet_id == BlockRegistry.BLOCK_FIRE or head_id == BlockRegistry.BLOCK_FIRE \
				or world.is_burning_at(ground_cell):
			take_damage(2.0, "fire")
		if submerged and air <= 0.0:
			take_damage(2.0, "drowning")
		elif world.get_registry().is_opaque(head_id):
			take_damage(1.0, "suffocation")
		if hunger <= 0.0:
			take_damage(1.0, "starvation")
	if not dead and hunger >= 18.0 and health < MAX_HEALTH:
		_regen_clock += delta
		if _regen_clock >= 4.0:
			_regen_clock = 0.0
			health = minf(MAX_HEALTH, health + 1.0)
			hunger = maxf(0.0, hunger - 0.5)
	else:
		_regen_clock = 0.0
	if previous != Vector3(health, hunger, air):
		vitals_changed.emit()


func _has_support(at: Vector3) -> bool:
	if world == null or not world.is_collision_ready_at(at):
		return false
	var query := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.1, at - Vector3.UP * 0.65, 1, [get_rid()])
	return not get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _protect_edge(delta: float) -> void:
	# Check axes separately, then the diagonal, so sneaking slides along ledges.
	if not _has_support(global_position + Vector3(velocity.x * delta, 0.0, 0.0)):
		velocity.x = 0.0
	if not _has_support(global_position + Vector3(0.0, 0.0, velocity.z * delta)):
		velocity.z = 0.0
	if not _has_support(global_position + Vector3(velocity.x * delta, 0.0, velocity.z * delta)):
		velocity.x = 0.0
		velocity.z = 0.0
