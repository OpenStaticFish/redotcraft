class_name FireOverlay
extends Node3D

## Draws the "block on fire" state. The burning block keeps its own mesh; this
## node clusters flame and smoke billboards on it so the block reads as alight
## without ever replacing it. One MultiMesh per effect keeps the whole fire to
## two draw calls, and the shaders animate from per-instance phase/progress, so
## `refresh()` only runs on the 4 Hz fire tick.

const MAX_CELLS := 384
const FLAMES_PER_CELL := 4
const SMOKES_PER_CELL := 2
## Flames are drawn larger than a block so they read around its silhouette
## instead of being buried inside the solid faces.
const FLAME_SCALE_MIN := 1.45
const FLAME_SCALE_RANGE := 0.75
const FLAME_SHADER := preload("res://world/fire_overlay.gdshader")
const SMOKE_SHADER := preload("res://world/smoke_overlay.gdshader")
const FLAME_TEXTURE := preload("res://assets/placeholders/fire/fire.png")
const SMOKE_TEXTURE := preload("res://assets/placeholders/fire/smoke.png")

var _flame_multimesh: MultiMesh
var _smoke_multimesh: MultiMesh


func _ready() -> void:
	_flame_multimesh = _make_layer(_flame_material(), MAX_CELLS * FLAMES_PER_CELL)
	_smoke_multimesh = _make_layer(_smoke_material(), MAX_CELLS * SMOKES_PER_CELL)
	add_child(_make_instance("Flames", _flame_multimesh))
	add_child(_make_instance("Smoke", _smoke_multimesh))


func _flame_material() -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = FLAME_SHADER
	material.set_shader_parameter("flame_texture", FLAME_TEXTURE)
	return material


func _smoke_material() -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = SMOKE_SHADER
	material.set_shader_parameter("smoke_texture", SMOKE_TEXTURE)
	return material


func _make_layer(material: Material, capacity: int) -> MultiMesh:
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	quad.material = material
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = true
	multimesh.mesh = quad
	multimesh.instance_count = capacity
	multimesh.visible_instance_count = 0
	return multimesh


func _make_instance(layer_name: String, multimesh: MultiMesh) -> MultiMeshInstance3D:
	var instance := MultiMeshInstance3D.new()
	instance.name = layer_name
	instance.multimesh = multimesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return instance


## Rebuilds the overlay from `cells` (block position -> remaining burn ticks).
## Instance placement is derived from a stable per-position hash, so flames do
## not jitter between the 4 Hz refreshes; the animation happens in the shader.
func refresh(cells: Dictionary, burn_ticks: int) -> void:
	if _flame_multimesh == null:
		return
	var keys := cells.keys()
	# Over the cap, keep the cells nearest the camera: those are the active fire
	# front the player is watching, not the stale cells that ignited first.
	if keys.size() > MAX_CELLS:
		var origin := Vector3.ZERO
		var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
		if camera != null:
			origin = camera.global_position
		keys.sort_custom(func(a: Vector3i, b: Vector3i) -> bool:
			return (Vector3(a) - origin).length_squared() < (Vector3(b) - origin).length_squared())
		keys.resize(MAX_CELLS)
	var flame_count := 0
	var smoke_count := 0
	for key in keys:
		var position: Vector3i = key
		var center := Vector3(position) + Vector3(0.5, 0.5, 0.5)
		var progress := 1.0 - float(cells[key]) / float(maxi(burn_ticks, 1))
		for index in FLAMES_PER_CELL:
			if flame_count >= _flame_multimesh.instance_count:
				break
			var angle := _cell_random(position, index * 3) * TAU
			var scale := FLAME_SCALE_MIN + _cell_random(position, index * 3 + 1) * FLAME_SCALE_RANGE
			var offset := Vector3(
				(_cell_random(position, index * 5 + 2) - 0.5) * 0.5,
				(_cell_random(position, index * 7 + 3) - 0.4) * 0.5,
				(_cell_random(position, index * 11 + 4) - 0.5) * 0.5)
			_flame_multimesh.set_instance_transform(flame_count,
				_billboard_transform(center + offset, angle, scale))
			_flame_multimesh.set_instance_custom_data(flame_count,
				Color(_cell_random(position, 13), progress, 0.0, 0.0))
			flame_count += 1
		for index in SMOKES_PER_CELL:
			if smoke_count >= _smoke_multimesh.instance_count:
				break
			var angle := _cell_random(position, 40 + index) * TAU
			var scale := 1.2 + _cell_random(position, 50 + index) * 0.7
			var offset := Vector3(
				(_cell_random(position, 60 + index) - 0.5) * 0.5,
				0.7,
				(_cell_random(position, 70 + index) - 0.5) * 0.5)
			_smoke_multimesh.set_instance_transform(smoke_count,
				_billboard_transform(center + offset, angle, scale))
			_smoke_multimesh.set_instance_custom_data(smoke_count,
				Color(_cell_random(position, 80 + index), progress, 0.0, 0.0))
			smoke_count += 1
	_flame_multimesh.visible_instance_count = flame_count
	_smoke_multimesh.visible_instance_count = smoke_count


## `QuadMesh` already faces +Z (vertical), so a Y spin is all that is needed to
## stack several quads into a flame cluster.
func _billboard_transform(origin: Vector3, angle: float, scale: float) -> Transform3D:
	var basis := Basis(Vector3.UP, angle).scaled(Vector3(scale, scale, scale))
	return Transform3D(basis, origin)


func _cell_random(position: Vector3i, salt: int) -> float:
	var n := position.x * 73856093 ^ position.y * 19349663 ^ position.z * 83492791 ^ (salt * 2654435761)
	n = (n ^ (n >> 13)) * 1274126177
	n = n ^ (n >> 16)
	return float(absi(n) % 10000) / 10000.0
