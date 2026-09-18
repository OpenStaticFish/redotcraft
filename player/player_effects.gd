class_name PlayerEffects
extends Node3D

var player: Player
var cracks: MeshInstance3D
var body: MeshInstance3D
var _crack_material: StandardMaterial3D
var _swing := 0.0
var _hit_time := 0.0


func setup(owner_player: Player) -> void:
	player = owner_player
	cracks = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3.ONE * 1.006
	cracks.mesh = box
	cracks.top_level = true
	cracks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_crack_material = StandardMaterial3D.new()
	_crack_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_crack_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_crack_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	# A small branching fracture texture, repeated on all six box faces.
	var image := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	for y in range(32):
		var x := 15 + roundi(sin(float(y) * 0.8) * 2.0)
		image.set_pixel(x, y, Color(0.04, 0.025, 0.02, 1.0))
		if y >= 9 and y < 25:
			image.set_pixel(clampi(x + y - 9, 0, 31), y, Color(0.04, 0.025, 0.02, 1.0))
		if y >= 15:
			image.set_pixel(clampi(x - (y - 15), 0, 31), y, Color(0.04, 0.025, 0.02, 1.0))
	_crack_material.albedo_texture = ImageTexture.create_from_image(image)
	cracks.material_override = _crack_material
	add_child(cracks)
	cracks.hide()
	body = MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.3
	capsule.height = 1.8
	body.mesh = capsule
	body.position.y = 0.9
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.18, 0.36, 0.43)
	body.material_override = material
	add_child(body)
	body.hide()


func hide_cracks() -> void:
	if cracks != null:
		cracks.hide()


func show_cracks(cell: Vector3i, progress: float) -> void:
	cracks.global_position = Vector3(cell) + Vector3.ONE * 0.5
	_crack_material.albedo_color.a = clampf(progress * 1.5, 0.15, 1.0)
	var stage := 1.0 + floorf(progress * 3.0)
	_crack_material.uv1_scale = Vector3(stage, stage, 1.0)
	cracks.show()


func burst(cell: Vector3i, hit: bool = false) -> void:
	var particles := CPUParticles3D.new()
	particles.top_level = true
	particles.amount = 5 if hit else 18
	particles.lifetime = 0.55
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.direction = Vector3.UP
	particles.spread = 100.0
	particles.initial_velocity_min = 1.3
	particles.initial_velocity_max = 3.0
	particles.gravity = Vector3(0.0, -9.0, 0.0)
	particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	particles.emission_box_extents = Vector3.ONE * 0.35
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE * 0.085
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.48, 0.39, 0.28)
	mesh.material = material
	particles.mesh = mesh
	add_child(particles)
	particles.global_position = Vector3(cell) + Vector3.ONE * 0.5
	if hit:
		particles.global_position += Vector3(player.target_normal) * 0.55
	particles.finished.connect(particles.queue_free)
	particles.restart()


func update_view(delta: float) -> void:
	if player._mining:
		_hit_time += delta
		if _hit_time >= 0.25:
			_hit_time = 0.0
			burst(player.target_block, true)
	else:
		_hit_time = 0.0
	body.visible = player.third_person
	body.scale.y = 0.8 if player.crouching else 1.0
	var camera := player.camera
	camera.position = Vector3.ZERO
	if player.third_person:
		var origin := player.head.global_position
		var desired := origin + camera.global_basis.z * 3.5
		var query := PhysicsRayQueryParameters3D.create(origin, desired, 1, [player.get_rid()])
		var hit := player.get_world_3d().direct_space_state.intersect_ray(query)
		var distance := 3.5
		if not hit.is_empty():
			distance = maxf(0.0, origin.distance_to(hit["position"]) - 0.25)
		camera.position.z = distance
	if player._held_block != null:
		player._held_block.visible = not player.third_person and not player.dead and player.selected_block != BlockRegistry.BLOCK_AIR
		_swing = _swing + delta * 14.0 if player._mining else 0.0
		var swing := sin(_swing) * 0.18
		player._held_block.position = Vector3(0.62 - absf(swing), -0.55 + swing, -1.05)
		player._held_block.rotation_degrees = Vector3(-12.0 - absf(swing) * 160.0, -22.0, 12.0)
