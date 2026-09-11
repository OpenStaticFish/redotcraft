extends CharacterBody3D

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

var world: Node3D
var hud: Node
var camera: Camera3D
var head: Node3D
var highlight: MeshInstance3D
var held_block: MeshInstance3D
var selected_block := 1
var target_block := Vector3i.ZERO
var target_normal := Vector3i.UP
var has_target := false
var spawn_position := Vector3.ZERO
var flying := false
var base_fov := 76.0
var _last_jump_time := -10.0


func _ready() -> void:
	head = $Head
	camera = $Head/Camera3D
	camera.current = true
	spawn_position = global_position
	apply_settings()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func apply_settings() -> void:
	set_fov(float(GameConfig.settings["fov"]))


func set_fov(value: float) -> void:
	base_fov = value
	if camera:
		camera.fov = base_fov


func setup_world(world_node: Node3D, hud_node: Node) -> void:
	world = world_node
	hud = hud_node
	_create_highlight()
	_create_held_block()
	_update_held_block()


func _create_highlight() -> void:
	highlight = MeshInstance3D.new()
	highlight.name = "TargetHighlight"
	var mesh := BoxMesh.new()
	mesh.size = Vector3(1.01, 1.01, 1.01)
	highlight.mesh = mesh
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.08, 0.08, 0.08, 0.28)
	highlight.material_override = material
	highlight.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	highlight.visible = false
	world.add_child(highlight)


func _create_held_block() -> void:
	held_block = MeshInstance3D.new()
	held_block.name = "HeldBlock"
	held_block.position = Vector3(0.62, -0.55, -1.05)
	held_block.rotation_degrees = Vector3(-12.0, -22.0, 12.0)
	held_block.scale = Vector3(0.43, 0.43, 0.43)
	held_block.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	camera.add_child(held_block)


func set_selected_block(block_id: int) -> void:
	selected_block = block_id
	_update_held_block()


func _update_held_block() -> void:
	if held_block and world:
		held_block.mesh = world.make_block_mesh(selected_block)
		held_block.material_override = world.get_blocks_material()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sensitivity := float(GameConfig.settings["mouse_sensitivity"])
		rotation.y -= event.relative.x * sensitivity
		head.rotation.x = clampf(head.rotation.x - event.relative.y * sensitivity, -1.48, 1.48)
		return

	if event is InputEventMouseButton and event.pressed:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			if hud:
				hud.select_slot(wrapi(hud.selected_slot - 1, 0, hud.HOTBAR.size()))
			get_viewport().set_input_as_handled()
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if hud:
				hud.select_slot(wrapi(hud.selected_slot + 1, 0, hud.HOTBAR.size()))
			get_viewport().set_input_as_handled()
			return
		if event.button_index == MOUSE_BUTTON_LEFT:
			_break_target()
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_place_target()
			get_viewport().set_input_as_handled()
		return

	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			if hud:
				hud.activate_pause()
			get_viewport().set_input_as_handled()
		elif event.keycode >= KEY_1 and event.keycode <= KEY_9:
			if hud:
				hud.select_slot(event.keycode - KEY_1)
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_0:
			if hud:
				hud.select_slot(9)
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_SPACE:
			var now := Time.get_ticks_msec() / 1000.0
			if now - _last_jump_time <= DOUBLE_TAP_TIME:
				flying = not flying
				velocity.y = 0.0
				_last_jump_time = -10.0
				if hud:
					hud.set_status("Flying enabled" if flying else "Flying disabled")
			else:
				_last_jump_time = now


func _physics_process(delta: float) -> void:
	var input_vector := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var direction := Vector3(input_vector.x, 0.0, input_vector.y).rotated(Vector3.UP, rotation.y)
	if direction.length_squared() > 1.0:
		direction = direction.normalized()
	var sprinting := not flying and Input.is_key_pressed(KEY_SHIFT) and input_vector.length_squared() > 0.01
	if flying:
		var vertical := 0.0
		if Input.is_key_pressed(KEY_SPACE):
			vertical += 1.0
		if Input.is_key_pressed(KEY_SHIFT):
			vertical -= 1.0
		velocity.x = move_toward(velocity.x, direction.x * FLY_SPEED, FLY_ACCEL * delta)
		velocity.y = move_toward(velocity.y, vertical * FLY_SPEED, FLY_ACCEL * delta)
		velocity.z = move_toward(velocity.z, direction.z * FLY_SPEED, FLY_ACCEL * delta)
	else:
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
	if global_position.y < -20.0:
		global_position = spawn_position
		velocity = Vector3.ZERO
	if camera:
		var target_fov := base_fov + 6.0 if sprinting and direction.length_squared() > 0.0 else base_fov
		camera.fov = lerpf(camera.fov, target_fov, clampf(delta * 8.0, 0.0, 1.0))
	_update_target()


func _update_target() -> void:
	if not world:
		return
	var query := PhysicsRayQueryParameters3D.create(camera.global_position, camera.global_position - camera.global_transform.basis.z * REACH)
	query.collision_mask = 1
	query.exclude = [self]
	var result := get_world_3d().direct_space_state.intersect_ray(query)
	has_target = false
	if result.is_empty():
		highlight.visible = false
		return
	var hit: Vector3 = result.get("position", Vector3.ZERO)
	var normal: Vector3 = result.get("normal", Vector3.UP)
	target_normal = Vector3i(roundi(normal.x), roundi(normal.y), roundi(normal.z))
	target_block = Vector3i(
		floori(hit.x - normal.x * 0.5),
		floori(hit.y - normal.y * 0.5),
		floori(hit.z - normal.z * 0.5)
	)
	has_target = true
	highlight.global_position = Vector3(target_block) + Vector3(0.5, 0.5, 0.5)
	highlight.visible = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED


func _break_target() -> void:
	if not has_target or not world:
		return
	var removed_type: int = world.break_block(target_block)
	if removed_type != 0 and hud:
		hud.collect_block(removed_type)
		hud.set_status("Mined %s" % world.get_block_name(removed_type))


func _place_target() -> void:
	if not has_target or not world:
		return
	if hud and not hud.can_place_selected():
		hud.set_status("No %s left" % world.get_block_name(selected_block))
		return
	var place_position := target_block + target_normal
	if _player_occupies(place_position):
		return
	if world.place_block(place_position, selected_block) and hud:
		hud.consume_selected_block()
		hud.set_status("Placed %s" % world.get_block_name(selected_block))


func _player_occupies(block_position: Vector3i) -> bool:
	var block_box := AABB(Vector3(block_position), Vector3.ONE)
	var player_box := AABB(global_position + Vector3(-0.34, 0.05, -0.34), Vector3(0.68, 1.85, 0.68))
	return block_box.intersects(player_box)
