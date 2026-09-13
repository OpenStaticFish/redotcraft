class_name Player
extends CharacterBody3D

signal block_broken(block_id: int)
signal block_placed(block_id: int)
signal status_requested(message: String)
signal slot_cycled(direction: int)
signal slot_selected(index: int)
signal pause_requested

const WALK_SPEED := 4.6
const SPRINT_SPEED := 6.8
const JUMP_VELOCITY := 8.4
const GRAVITY := 26.0
const GROUND_ACCEL := 55.0
const AIR_ACCEL := 16.0
const REACH := 6.0
const FLY_SPEED := 11.0
const FLY_ACCEL := 45.0
const DOUBLE_TAP_TIME := 0.32
const FALL_RESET_Y := -20.0
const SPRINT_FOV_BOOST := 6.0
const FOV_LERP_SPEED := 8.0

var world: VoxelWorld
var can_place_check: Callable = Callable()
var selected_block := 1
var target_block := Vector3i.ZERO
var target_normal := Vector3i.UP
var has_target := false
var spawn_position := Vector3.ZERO
var flying := false
var base_fov := 76.0
var pitch_limit := deg_to_rad(85.0)
var _last_jump_time := -10.0
var _highlight: MeshInstance3D
var _held_block: MeshInstance3D

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D


func _ready() -> void:
	camera.current = true
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
	selected_block = block_id
	_update_held_block()


func _unhandled_input(event: InputEvent) -> void:
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


func _physics_process(delta: float) -> void:
	var input_vector := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var direction := Vector3(input_vector.x, 0.0, input_vector.y).rotated(Vector3.UP, rotation.y)
	if direction.length_squared() > 1.0:
		direction = direction.normalized()
	var sprinting := false
	if flying:
		var vertical := Input.get_action_strength("fly_up") - Input.get_action_strength("fly_down")
		velocity.x = move_toward(velocity.x, direction.x * FLY_SPEED, FLY_ACCEL * delta)
		velocity.y = move_toward(velocity.y, vertical * FLY_SPEED, FLY_ACCEL * delta)
		velocity.z = move_toward(velocity.z, direction.z * FLY_SPEED, FLY_ACCEL * delta)
	else:
		sprinting = Input.is_action_pressed("sprint") and input_vector.length_squared() > 0.01
		var speed := SPRINT_SPEED if sprinting else WALK_SPEED
		var acceleration := GROUND_ACCEL if is_on_floor() else AIR_ACCEL
		velocity.x = move_toward(velocity.x, direction.x * speed, acceleration * delta)
		velocity.z = move_toward(velocity.z, direction.z * speed, acceleration * delta)
		if not is_on_floor():
			velocity.y -= GRAVITY * delta
		elif Input.is_action_just_pressed("jump"):
			velocity.y = JUMP_VELOCITY
		else:
			velocity.y = -0.5
	move_and_slide()
	if global_position.y < FALL_RESET_Y:
		global_position = spawn_position
		velocity = Vector3.ZERO
	if camera:
		var target_fov := base_fov + SPRINT_FOV_BOOST if sprinting and direction.length_squared() > 0.0 else base_fov
		camera.fov = lerpf(camera.fov, target_fov, clampf(delta * FOV_LERP_SPEED, 0.0, 1.0))
	_update_target()


func _update_target() -> void:
	if world == null:
		return
	has_target = false
	var result := _voxel_raycast(camera.global_position, -camera.global_transform.basis.z, REACH)
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


func _break_target() -> void:
	if not has_target or world == null:
		return
	var removed := world.break_block(target_block)
	if removed != BlockRegistry.BLOCK_AIR:
		block_broken.emit(removed)


func _place_target() -> void:
	if not has_target or world == null:
		return
	if can_place_check.is_valid() and not can_place_check.call():
		status_requested.emit("No %s left" % world.get_block_name(selected_block))
		return
	var place_position := target_block + target_normal
	if _player_occupies(place_position):
		return
	if world.place_block(place_position, selected_block):
		block_placed.emit(selected_block)


func _handle_double_tap_jump() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_jump_time <= DOUBLE_TAP_TIME:
		flying = not flying
		velocity.y = 0.0
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
		_held_block.mesh = world.make_block_mesh(selected_block)
		_held_block.material_override = world.get_blocks_material()


func _player_occupies(block_position: Vector3i) -> bool:
	var block_box := AABB(Vector3(block_position), Vector3.ONE)
	var player_box := AABB(global_position + Vector3(-0.34, 0.05, -0.34), Vector3(0.68, 1.85, 0.68))
	return block_box.intersects(player_box)
