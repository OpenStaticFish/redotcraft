class_name CloudField
extends Node3D

const CELL_SIZE := 12.0
const CLOUD_HEIGHT := 180.0
const CLOUD_THICKNESS := 4.0
const REGION_CELLS := 16
const VIEW_REGIONS := 3
const COVERAGE := 0.58
const DRIFT_SPEED := 1.4
const WIND_DIR := Vector2(1.0, 0.35)
const BUILD_BUDGET := 2

const FACE_COLORS := [
	Color(1.0, 1.0, 1.0),
	Color(0.7, 0.76, 0.85),
	Color(0.9, 0.93, 0.97),
	Color(0.84, 0.88, 0.94),
	Color(0.88, 0.91, 0.96),
	Color(0.86, 0.9, 0.95),
]

var _regions: Dictionary = {}
var _queued: Dictionary = {}
var _queue: Array[Vector2i] = []
var _origin := Vector2.ZERO
var _ref := Vector2i(2147483647, 2147483647)
var _material: StandardMaterial3D


func _ready() -> void:
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.vertex_color_use_as_albedo = true
	_material.cull_mode = BaseMaterial3D.CULL_BACK


## Tints every cloud region, used by the day/night cycle.
func set_sky_tint(tint: Color) -> void:
	if _material:
		_material.albedo_color = tint


func _process(delta: float) -> void:
	_origin += WIND_DIR.normalized() * DRIFT_SPEED * delta
	global_position = Vector3(_origin.x, 0.0, _origin.y)
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var cloud_pos: Vector3 = camera.global_position - Vector3(_origin.x, 0.0, _origin.y)
	var span := CELL_SIZE * REGION_CELLS
	_refresh_desired(Vector2i(floori(cloud_pos.x / span), floori(cloud_pos.z / span)))
	var built := 0
	while built < BUILD_BUDGET and not _queue.is_empty():
		var key: Vector2i = _queue.pop_front()
		_queued.erase(key)
		_build_region(key)
		built += 1


func _refresh_desired(ref: Vector2i) -> void:
	if ref == _ref:
		return
	_ref = ref
	var desired := {}
	for rz in range(ref.y - VIEW_REGIONS, ref.y + VIEW_REGIONS + 1):
		for rx in range(ref.x - VIEW_REGIONS, ref.x + VIEW_REGIONS + 1):
			var key := Vector2i(rx, rz)
			desired[key] = true
			if not _regions.has(key) and not _queued.has(key):
				_queue.append(key)
				_queued[key] = true
	for key in _regions.keys():
		if not desired.has(key):
			_regions[key].queue_free()
			_regions.erase(key)


func _is_desired(key: Vector2i) -> bool:
	return absi(key.x - _ref.x) <= VIEW_REGIONS and absi(key.y - _ref.y) <= VIEW_REGIONS


func _build_region(key: Vector2i) -> void:
	if not _is_desired(key):
		return
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var base_cx := key.x * REGION_CELLS
	var base_cz := key.y * REGION_CELLS
	for cz in range(base_cz, base_cz + REGION_CELLS):
		for cx in range(base_cx, base_cx + REGION_CELLS):
			if not _cell_filled(cx, cz):
				continue
			for face in 6:
				var normal: Vector3i = VoxelDefs.FACE_NORMALS[face]
				if normal.y == 0 and _cell_filled(cx + normal.x, cz + normal.z):
					continue
				var base := verts.size()
				for corner in 4:
					var offset: Vector3i = VoxelDefs.FACE_VERTS[face][corner]
					verts.append(Vector3(
						(cx - base_cx) * CELL_SIZE + offset.x * CELL_SIZE,
						CLOUD_HEIGHT + offset.y * CLOUD_THICKNESS,
						(cz - base_cz) * CELL_SIZE + offset.z * CELL_SIZE))
					normals.append(Vector3(normal))
					colors.append(FACE_COLORS[face])
				indices.append_array(PackedInt32Array([base, base + 2, base + 1, base, base + 3, base + 2]))
	if verts.is_empty():
		return
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = _material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.extra_cull_margin = CELL_SIZE * REGION_CELLS
	instance.position = Vector3(key.x * REGION_CELLS * CELL_SIZE, 0.0, key.y * REGION_CELLS * CELL_SIZE)
	add_child(instance)
	_regions[key] = instance


func _cell_filled(cx: int, cz: int) -> bool:
	var coarse := Vector2(floor(cx / 2.0), floor(cz / 2.0))
	return _density(coarse) >= COVERAGE


func _density(coarse: Vector2) -> float:
	var large := _value_noise(coarse * 0.075)
	var medium := _value_noise(coarse * 0.19 + Vector2(31.4, 17.8))
	return large * 0.6 + medium * 0.4


func _value_noise(point: Vector2) -> float:
	var cell := Vector2(floor(point.x), floor(point.y))
	var local := point - cell
	var smooth := local * (Vector2(3.0, 3.0) - local * 2.0)
	var a := _hash21(cell)
	var b := _hash21(cell + Vector2(1.0, 0.0))
	var c := _hash21(cell + Vector2(0.0, 1.0))
	var d := _hash21(cell + Vector2(1.0, 1.0))
	return lerpf(lerpf(a, b, smooth.x), lerpf(c, d, smooth.x), smooth.y)


func _hash21(point: Vector2) -> float:
	var value := Vector2(fposmod(point.x * 127.1, 1.0), fposmod(point.y * 311.7, 1.0))
	var dot := value.dot(value + Vector2(19.19, 19.19))
	value += Vector2(dot, dot)
	return fposmod(value.x * value.y, 1.0)
