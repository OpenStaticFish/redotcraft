class_name ChunkMesher
extends RefCounted

var _blocks: BlockRegistry
var _face_ao_offsets: Array = []


class MeshResult:
	var data := PackedByteArray()
	var max_y := 0
	var mask := 0
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var collision := PackedVector3Array()
	var water_verts := PackedVector3Array()
	var water_normals := PackedVector3Array()
	var water_uvs := PackedVector2Array()
	var water_colors := PackedColorArray()
	var water_indices := PackedInt32Array()


class NeighborSample:
	var data := PackedByteArray()
	var max_y := 0

	func _init(p_data: PackedByteArray, p_max_y: int) -> void:
		data = p_data
		max_y = p_max_y


class NeighborSet:
	var mask := 0
	var samples: Dictionary = {}

	func get_sample(direction: Vector2i) -> NeighborSample:
		return samples.get(direction)


func _init(blocks: BlockRegistry) -> void:
	_blocks = blocks
	_build_ao_offsets()


## Thread-safe: only reads immutable block tables once constructed.
func build(data: PackedByteArray, data_max_y: int, neighbors: NeighborSet) -> MeshResult:
	var result := MeshResult.new()
	result.data = data
	result.mask = neighbors.mask
	var max_y := clampi(data_max_y + 1, 1, VoxelDefs.WORLD_HEIGHT - 2)
	result.max_y = max_y
	var pad_height := max_y + 3
	var padded := PackedByteArray()
	padded.resize(VoxelDefs.PAD_W * VoxelDefs.PAD_W * pad_height)
	for pad_y in range(0, pad_height):
		var y := pad_y - 1
		for pad_z in range(0, VoxelDefs.PAD_W):
			var local_z := pad_z - 1
			for pad_x in range(0, VoxelDefs.PAD_W):
				var local_x := pad_x - 1
				var id := 0
				if local_x >= 0 and local_x < VoxelDefs.CHUNK_SIZE and local_z >= 0 and local_z < VoxelDefs.CHUNK_SIZE:
					if y >= 0 and y < VoxelDefs.WORLD_HEIGHT:
						id = data[local_x + local_z * VoxelDefs.DATA_STRIDE_Z + y * VoxelDefs.DATA_STRIDE_Y]
				else:
					var dx := 0
					var dz := 0
					if pad_x == 0:
						dx = -1
					elif pad_x == VoxelDefs.PAD_W - 1:
						dx = 1
					if pad_z == 0:
						dz = -1
					elif pad_z == VoxelDefs.PAD_W - 1:
						dz = 1
					var sample := neighbors.get_sample(Vector2i(dx, dz))
					if sample != null and y >= 0 and y <= sample.max_y:
						var neighbor_x := local_x - dx * VoxelDefs.CHUNK_SIZE
						var neighbor_z := local_z - dz * VoxelDefs.CHUNK_SIZE
						id = sample.data[neighbor_x + neighbor_z * VoxelDefs.DATA_STRIDE_Z + y * VoxelDefs.DATA_STRIDE_Y]
				padded[pad_x + pad_z * VoxelDefs.PAD_STRIDE_Z + pad_y * VoxelDefs.PAD_STRIDE_Y] = id
	for y in range(0, max_y + 1):
		for local_z in VoxelDefs.CHUNK_SIZE:
			for local_x in VoxelDefs.CHUNK_SIZE:
				var pad_index := (local_x + 1) + (local_z + 1) * VoxelDefs.PAD_STRIDE_Z + (y + 1) * VoxelDefs.PAD_STRIDE_Y
				var id := padded[pad_index]
				if id == BlockRegistry.BLOCK_AIR:
					continue
				if id == BlockRegistry.BLOCK_WATER:
					_append_water_block(padded, pad_index, local_x, y, local_z, result)
					continue
				var is_opaque := _blocks.is_opaque(id)
				for face in 6:
					var normal: Vector3i = VoxelDefs.FACE_NORMALS[face]
					var neighbor_index := pad_index + normal.x + normal.z * VoxelDefs.PAD_STRIDE_Z + normal.y * VoxelDefs.PAD_STRIDE_Y
					var neighbor_id := padded[neighbor_index]
					if _blocks.is_opaque(neighbor_id):
						continue
					if not is_opaque and neighbor_id == id and not _blocks.has_flag(id, BlockRegistry.FLAG_LEAVES):
						continue
					_append_face(face, pad_index, local_x, y, local_z, id, padded, result)
	return result


func make_block_mesh(block_id: int) -> ArrayMesh:
	if not _blocks.is_valid_id(block_id):
		block_id = BlockRegistry.BLOCK_GRASS
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	for face in 6:
		var normal: Vector3i = VoxelDefs.FACE_NORMALS[face]
		var tile := _blocks.tile_for(block_id, face)
		var uv_origin := _blocks.tile_uv_origin(tile)
		var base := verts.size()
		var face_verts: Array = VoxelDefs.FACE_VERTS[face]
		var face_uvs: Array = VoxelDefs.FACE_UVS[face]
		var shade: float = VoxelDefs.FACE_SHADE[face]
		for corner in 4:
			var offset: Vector3i = face_verts[corner]
			verts.append(Vector3(offset.x, offset.y, offset.z) - Vector3(0.5, 0.5, 0.5))
			normals.append(Vector3(normal))
			var uv: Vector2 = face_uvs[corner]
			uvs.append(uv_origin + Vector2(uv.x * _blocks.tile_uv_size.x, uv.y * _blocks.tile_uv_size.y))
			colors.append(Color(shade, shade, shade, 1.0))
		indices.append_array(PackedInt32Array([base, base + 2, base + 1, base, base + 3, base + 2]))
	return arrays_to_mesh(verts, normals, uvs, colors, indices, _blocks.material)


static func arrays_to_mesh(verts: PackedVector3Array, normals: PackedVector3Array, uvs: PackedVector2Array, colors: PackedColorArray, indices: PackedInt32Array, material: Material) -> ArrayMesh:
	if verts.is_empty():
		return null
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, material)
	return mesh


func _build_ao_offsets() -> void:
	_face_ao_offsets = []
	for face in VoxelDefs.FACE_NORMALS.size():
		var normal: Vector3i = VoxelDefs.FACE_NORMALS[face]
		var tangent_a: Vector3i = VoxelDefs.FACE_TANGENT_A[face]
		var tangent_b: Vector3i = VoxelDefs.FACE_TANGENT_B[face]
		var axis_a := 0 if tangent_a.x != 0 else 1
		var axis_b := 0 if tangent_b.x != 0 else (1 if tangent_b.y != 0 else 2)
		var corners: Array = []
		for corner in 4:
			var offset: Vector3i = VoxelDefs.FACE_VERTS[face][corner]
			var a: Vector3i = tangent_a * (offset[axis_a] * 2 - 1)
			var b: Vector3i = tangent_b * (offset[axis_b] * 2 - 1)
			corners.append([normal + a, normal + b, normal + a + b])
		_face_ao_offsets.append(corners)


func _append_face(face: int, pad_index: int, local_x: int, y: int, local_z: int, block_id: int, padded: PackedByteArray, result: MeshResult) -> void:
	var normal: Vector3i = VoxelDefs.FACE_NORMALS[face]
	var shade: float = VoxelDefs.FACE_SHADE[face]
	var tile := _blocks.tile_for(block_id, face)
	var uv_origin := _blocks.tile_uv_origin(tile)
	var base := result.verts.size()
	var face_verts: Array = VoxelDefs.FACE_VERTS[face]
	var face_uvs: Array = VoxelDefs.FACE_UVS[face]
	for corner in 4:
		var offset: Vector3i = face_verts[corner]
		var position := Vector3(local_x + offset.x, y + offset.y, local_z + offset.z)
		result.verts.append(position)
		result.normals.append(Vector3(normal))
		var uv: Vector2 = face_uvs[corner]
		result.uvs.append(uv_origin + Vector2(uv.x * _blocks.tile_uv_size.x, uv.y * _blocks.tile_uv_size.y))
		var occlusion := 0
		var samples: Array = _face_ao_offsets[face][corner]
		for sample in samples:
			var sample_offset: Vector3i = sample
			var sample_index := pad_index + sample_offset.x + sample_offset.z * VoxelDefs.PAD_STRIDE_Z + sample_offset.y * VoxelDefs.PAD_STRIDE_Y
			if _blocks.is_opaque(padded[sample_index]):
				occlusion += 1
		var light := shade * float(VoxelDefs.AO_LEVELS[3 - occlusion])
		result.colors.append(Color(light, light, light, 1.0))
	var p0: Vector3 = result.verts[base]
	var p1: Vector3 = result.verts[base + 1]
	var p2: Vector3 = result.verts[base + 2]
	var p3: Vector3 = result.verts[base + 3]
	result.indices.append_array(PackedInt32Array([base, base + 2, base + 1, base, base + 3, base + 2]))
	result.collision.append_array(PackedVector3Array([p0, p2, p1, p0, p3, p2]))


func _append_water_block(padded: PackedByteArray, pad_index: int, local_x: int, y: int, local_z: int, result: MeshResult) -> void:
	var above := padded[pad_index + VoxelDefs.PAD_STRIDE_Y]
	var top := 0.9 if above != BlockRegistry.BLOCK_WATER else 1.0
	if above != BlockRegistry.BLOCK_WATER and not _blocks.is_opaque(above):
		_append_water_face(0, local_x, y, local_z, top, result)
	for face in range(2, 6):
		var normal: Vector3i = VoxelDefs.FACE_NORMALS[face]
		var neighbor_index := pad_index + normal.x + normal.z * VoxelDefs.PAD_STRIDE_Z + normal.y * VoxelDefs.PAD_STRIDE_Y
		var neighbor := padded[neighbor_index]
		if neighbor == BlockRegistry.BLOCK_WATER or _blocks.is_opaque(neighbor):
			continue
		_append_water_face(face, local_x, y, local_z, top, result)


func _append_water_face(face: int, local_x: int, y: int, local_z: int, top: float, result: MeshResult) -> void:
	var normal: Vector3i = VoxelDefs.FACE_NORMALS[face]
	var base := result.water_verts.size()
	var face_verts: Array = VoxelDefs.FACE_VERTS[face]
	var shade := 1.0 if face == 0 else 0.92
	for corner in 4:
		var offset: Vector3i = face_verts[corner]
		result.water_verts.append(Vector3(local_x + offset.x, y + (top if offset.y == 1 else 0.0), local_z + offset.z))
		result.water_normals.append(Vector3(normal))
		result.water_uvs.append(Vector2(local_x + offset.x, local_z + offset.z))
		result.water_colors.append(Color(shade, shade, shade, 1.0))
	result.water_indices.append_array(PackedInt32Array([base, base + 2, base + 1, base, base + 3, base + 2]))
