class_name ChunkMesher
extends RefCounted

const LIGHT_PAD := 16
const MAX_LEVEL := BlockRegistry.MAX_LIGHT_LEVEL
const CROSS_PLANES := [
	[Vector3(0.1, 0.0, 0.1), Vector3(0.9, 0.0, 0.9), Vector3(0.9, 1.0, 0.9), Vector3(0.1, 1.0, 0.1)],
	[Vector3(0.9, 0.0, 0.1), Vector3(0.1, 0.0, 0.9), Vector3(0.1, 1.0, 0.9), Vector3(0.9, 1.0, 0.1)],
]
const CROSS_UVS := [Vector2(0.0, 1.0), Vector2(1.0, 1.0), Vector2(1.0, 0.0), Vector2(0.0, 0.0)]

var _blocks: BlockRegistry
var _face_ao_offsets: Array = []
var _opacity: PackedByteArray = PackedByteArray()
var _emission_r: PackedByteArray = PackedByteArray()
var _emission_g: PackedByteArray = PackedByteArray()
var _emission_b: PackedByteArray = PackedByteArray()


class MeshResult:
	var data := PackedByteArray()
	var max_y := 0
	var mask := 0
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var light := PackedFloat32Array()
	var indices := PackedInt32Array()
	var collision := PackedVector3Array()
	var water_verts := PackedVector3Array()
	var water_normals := PackedVector3Array()
	var water_uvs := PackedVector2Array()
	var water_colors := PackedColorArray()
	var water_indices := PackedInt32Array()
	var light_volume: LightVolume


class LightVolume:
	var w := 0
	var d := 0
	var h := 0
	var blocks := PackedByteArray()
	var sky := PackedByteArray()
	var block_r := PackedByteArray()
	var block_g := PackedByteArray()
	var block_b := PackedByteArray()


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
	_build_light_tables()


## Thread-safe: only reads immutable block tables once constructed.
func build(data: PackedByteArray, data_max_y: int, neighbors: NeighborSet) -> MeshResult:
	var result := MeshResult.new()
	result.data = data
	result.mask = neighbors.mask
	var max_y := clampi(data_max_y + 1, 1, VoxelDefs.WORLD_HEIGHT - 2)
	result.max_y = max_y
	var light_volume := _assemble_light_volume(data, data_max_y, neighbors)
	_compute_sky_light(light_volume)
	_compute_block_light(light_volume)
	result.light_volume = light_volume
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
				if _blocks.has_flag(id, BlockRegistry.FLAG_CROSS):
					var volume: LightVolume = result.light_volume
					var light_index := (y * volume.d + local_z + LIGHT_PAD) * volume.w + local_x + LIGHT_PAD
					var sky_light := float(volume.sky[light_index]) / float(MAX_LEVEL)
					var block_light := Color.BLACK
					if not volume.block_r.is_empty():
						block_light = Color(
							float(volume.block_r[light_index]) / float(MAX_LEVEL),
							float(volume.block_g[light_index]) / float(MAX_LEVEL),
							float(volume.block_b[light_index]) / float(MAX_LEVEL))
					_append_cross_block(Vector3(local_x, y, local_z), id, block_light, sky_light, result)
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
	result.light_volume = null
	return result


func make_block_mesh(block_id: int) -> ArrayMesh:
	if not _blocks.is_valid_id(block_id):
		block_id = BlockRegistry.BLOCK_GRASS
	if _blocks.has_flag(block_id, BlockRegistry.FLAG_CROSS):
		var cross := MeshResult.new()
		_append_cross_block(Vector3(-0.5, -0.5, -0.5), block_id, Color.BLACK, 1.0, cross)
		return arrays_to_mesh(cross.verts, cross.normals, cross.uvs, cross.colors, cross.indices, _blocks.material, cross.light)
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var light := PackedFloat32Array()
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
			light.append_array(PackedFloat32Array([0.0, 0.0, 0.0, 1.0]))
		indices.append_array(PackedInt32Array([base, base + 2, base + 1, base, base + 3, base + 2]))
	return arrays_to_mesh(verts, normals, uvs, colors, indices, _blocks.material, light)


static func arrays_to_mesh(verts: PackedVector3Array, normals: PackedVector3Array, uvs: PackedVector2Array, colors: PackedColorArray, indices: PackedInt32Array, material: Material, light := PackedFloat32Array()) -> ArrayMesh:
	if verts.is_empty():
		return null
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var flags := 0
	if not light.is_empty():
		arrays[Mesh.ARRAY_CUSTOM0] = light
		flags = Mesh.ARRAY_FORMAT_CUSTOM0 | (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, flags)
	mesh.surface_set_material(0, material)
	return mesh


func _build_light_tables() -> void:
	_opacity.resize(256)
	_emission_r.resize(256)
	_emission_g.resize(256)
	_emission_b.resize(256)
	for id in 256:
		_opacity[id] = _blocks.light_attenuation(id)
		var color := _blocks.emission_color(id)
		if color == Color.BLACK:
			continue
		_emission_r[id] = roundi(color.r * MAX_LEVEL)
		_emission_g[id] = roundi(color.g * MAX_LEVEL)
		_emission_b[id] = roundi(color.b * MAX_LEVEL)


## Assembles a 3x3 chunk footprint of block IDs so light from emitters and sky
## openings up to 15 blocks outside the chunk is accounted for.
func _assemble_light_volume(data: PackedByteArray, data_max_y: int, neighbors: NeighborSet) -> LightVolume:
	var volume := LightVolume.new()
	volume.w = VoxelDefs.CHUNK_SIZE * 3
	volume.d = VoxelDefs.CHUNK_SIZE * 3
	var tiles: Array[PackedByteArray] = []
	tiles.resize(9)
	var tile_max := PackedInt32Array()
	tile_max.resize(9)
	var max_y := data_max_y
	for tile_z in 3:
		for tile_x in 3:
			var index := tile_z * 3 + tile_x
			var direction := Vector2i(tile_x - 1, tile_z - 1)
			if direction == Vector2i.ZERO:
				tiles[index] = data
				tile_max[index] = data_max_y
			else:
				var sample := neighbors.get_sample(direction)
				if sample != null:
					tiles[index] = sample.data
					tile_max[index] = sample.max_y
					max_y = maxi(max_y, sample.max_y)
	volume.h = mini(max_y + 3, VoxelDefs.WORLD_HEIGHT)
	for y in volume.h:
		for volume_z in volume.d:
			var local_z := volume_z % VoxelDefs.CHUNK_SIZE
			var tile_z := int(volume_z / VoxelDefs.CHUNK_SIZE)
			for tile_x in 3:
				var index := tile_z * 3 + tile_x
				var tile := tiles[index]
				if not tile.is_empty() and y <= tile_max[index]:
					var source := y * VoxelDefs.DATA_STRIDE_Y + local_z * VoxelDefs.DATA_STRIDE_Z
					volume.blocks.append_array(tile.slice(source, source + VoxelDefs.CHUNK_SIZE))
				else:
					volume.blocks.resize(volume.blocks.size() + VoxelDefs.CHUNK_SIZE)
	volume.sky.resize(volume.blocks.size())
	return volume


func _compute_sky_light(volume: LightVolume) -> void:
	var w := volume.w
	var area := volume.w * volume.d
	var blocks := volume.blocks
	var sky := volume.sky
	var queue := PackedInt32Array()
	queue.resize(blocks.size() * 2)
	var head := 0
	var tail := 0
	for volume_z in volume.d:
		for vx in w:
			var level := MAX_LEVEL
			var y := volume.h - 1
			while y >= 0:
				var index := y * area + volume_z * w + vx
				var attenuation := _opacity[blocks[index]]
				if attenuation >= MAX_LEVEL:
					break
				if attenuation > 0:
					level = maxi(level - attenuation, 0)
					if level == 0:
						break
				if sky[index] < level:
					sky[index] = level
				if level > 1 and tail < queue.size():
					if vx > 0:
						var ni := index - 1
						if sky[ni] < level - 1 and _opacity[blocks[ni]] < MAX_LEVEL:
							sky[ni] = level - 1
							queue[tail] = ni
							tail += 1
					if vx < w - 1:
						var ni := index + 1
						if sky[ni] < level - 1 and _opacity[blocks[ni]] < MAX_LEVEL:
							sky[ni] = level - 1
							queue[tail] = ni
							tail += 1
					if volume_z > 0:
						var ni := index - w
						if sky[ni] < level - 1 and _opacity[blocks[ni]] < MAX_LEVEL:
							sky[ni] = level - 1
							queue[tail] = ni
							tail += 1
					if volume_z < volume.d - 1:
						var ni := index + w
						if sky[ni] < level - 1 and _opacity[blocks[ni]] < MAX_LEVEL:
							sky[ni] = level - 1
							queue[tail] = ni
							tail += 1
				y -= 1
	while head < tail:
		var index := queue[head]
		head += 1
		var level := sky[index]
		if level <= 1:
			continue
		var vx := index % w
		var remainder := int(index / w)
		var volume_z := remainder % volume.d
		var y := int(remainder / volume.d)
		if vx > 0:
			var ni := index - 1
			var nl := level - maxi(_opacity[blocks[ni]], 1)
			if nl > sky[ni] and tail < queue.size():
				sky[ni] = nl
				queue[tail] = ni
				tail += 1
		if vx < w - 1:
			var ni := index + 1
			var nl := level - maxi(_opacity[blocks[ni]], 1)
			if nl > sky[ni] and tail < queue.size():
				sky[ni] = nl
				queue[tail] = ni
				tail += 1
		if volume_z > 0:
			var ni := index - w
			var nl := level - maxi(_opacity[blocks[ni]], 1)
			if nl > sky[ni] and tail < queue.size():
				sky[ni] = nl
				queue[tail] = ni
				tail += 1
		if volume_z < volume.d - 1:
			var ni := index + w
			var nl := level - maxi(_opacity[blocks[ni]], 1)
			if nl > sky[ni] and tail < queue.size():
				sky[ni] = nl
				queue[tail] = ni
				tail += 1
		if y > 0:
			var ni := index - area
			var nl := level - maxi(_opacity[blocks[ni]], 1)
			if nl > sky[ni] and tail < queue.size():
				sky[ni] = nl
				queue[tail] = ni
				tail += 1
		if y < volume.h - 1:
			var ni := index + area
			var nl := level - maxi(_opacity[blocks[ni]], 1)
			if nl > sky[ni] and tail < queue.size():
				sky[ni] = nl
				queue[tail] = ni
				tail += 1


func _compute_block_light(volume: LightVolume) -> void:
	var blocks := volume.blocks
	var found_emitter := false
	for block_id in BlockRegistry.EMISSIVE_COLORS:
		if blocks.find(block_id) != -1:
			found_emitter = true
			break
	if not found_emitter:
		return
	var size := blocks.size()
	var area := volume.w * volume.d
	volume.block_r.resize(size)
	volume.block_g.resize(size)
	volume.block_b.resize(size)
	var red := volume.block_r
	var green := volume.block_g
	var blue := volume.block_b
	var queue := PackedInt32Array()
	queue.resize(size * 2)
	var head := 0
	var tail := 0
	var volume_z := 0
	var y := 0
	var vx := 0
	for block_id in BlockRegistry.EMISSIVE_COLORS:
		var emitter := blocks.find(block_id)
		var seed_r := _emission_r[block_id]
		var seed_g := _emission_g[block_id]
		var seed_b := _emission_b[block_id]
		if seed_r <= 0 and seed_g <= 0 and seed_b <= 0:
			continue
		var emitter_opaque := _opacity[block_id] >= MAX_LEVEL
		while emitter != -1:
			var remainder := int(emitter / volume.w)
			vx = emitter % volume.w
			volume_z = remainder % volume.d
			y = int(remainder / volume.d)
			if not emitter_opaque:
				if red[emitter] < seed_r or green[emitter] < seed_g or blue[emitter] < seed_b:
					red[emitter] = maxi(red[emitter], seed_r)
					green[emitter] = maxi(green[emitter], seed_g)
					blue[emitter] = maxi(blue[emitter], seed_b)
					if tail < queue.size():
						queue[tail] = emitter
						tail += 1
			elif seed_r > 1 or seed_g > 1 or seed_b > 1:
				var neighbor_r := maxi(seed_r - 1, 0)
				var neighbor_g := maxi(seed_g - 1, 0)
				var neighbor_b := maxi(seed_b - 1, 0)
				for direction in 6:
					var ni := emitter
					match direction:
						0:
							if vx == 0:
								continue
							ni -= 1
						1:
							if vx == volume.w - 1:
								continue
							ni += 1
						2:
							if volume_z == 0:
								continue
							ni -= volume.w
						3:
							if volume_z == volume.d - 1:
								continue
							ni += volume.w
						4:
							if y == 0:
								continue
							ni -= area
						_:
							if y == volume.h - 1:
								continue
							ni += area
					if _opacity[blocks[ni]] >= MAX_LEVEL:
						continue
					if red[ni] >= neighbor_r and green[ni] >= neighbor_g and blue[ni] >= neighbor_b:
						continue
					red[ni] = maxi(red[ni], neighbor_r)
					green[ni] = maxi(green[ni], neighbor_g)
					blue[ni] = maxi(blue[ni], neighbor_b)
					if tail < queue.size():
						queue[tail] = ni
						tail += 1
			emitter = blocks.find(block_id, emitter + 1)
	while head < tail:
		var index := queue[head]
		head += 1
		var r := red[index]
		var g := green[index]
		var b := blue[index]
		if r <= 1 and g <= 1 and b <= 1:
			continue
		var remainder := int(index / volume.w)
		vx = index % volume.w
		volume_z = remainder % volume.d
		y = int(remainder / volume.d)
		for direction in 6:
			var ni := index
			match direction:
				0:
					if vx == 0:
						continue
					ni -= 1
				1:
					if vx == volume.w - 1:
						continue
					ni += 1
				2:
					if volume_z == 0:
						continue
					ni -= volume.w
				3:
					if volume_z == volume.d - 1:
						continue
					ni += volume.w
				4:
					if y == 0:
						continue
					ni -= area
				_:
					if y == volume.h - 1:
						continue
					ni += area
			var attenuation := maxi(_opacity[blocks[ni]], 1)
			if attenuation >= MAX_LEVEL:
				continue
			var nr := maxi(r - attenuation, 0)
			var ng := maxi(g - attenuation, 0)
			var nb := maxi(b - attenuation, 0)
			if red[ni] >= nr and green[ni] >= ng and blue[ni] >= nb:
				continue
			red[ni] = maxi(red[ni], nr)
			green[ni] = maxi(green[ni], ng)
			blue[ni] = maxi(blue[ni], nb)
			if tail < queue.size():
				queue[tail] = ni
				tail += 1


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
	var volume: LightVolume = result.light_volume
	var block_light_active := not volume.block_r.is_empty()
	var front_x := local_x + LIGHT_PAD + normal.x
	var front_y := y + normal.y
	var front_z := local_z + LIGHT_PAD + normal.z
	var front_index := -1
	if front_y >= 0 and front_y < volume.h:
		front_index = (front_y * volume.d + front_z) * volume.w + front_x
	for corner in 4:
		var offset: Vector3i = face_verts[corner]
		var position := Vector3(local_x + offset.x, y + offset.y, local_z + offset.z)
		result.verts.append(position)
		result.normals.append(Vector3(normal))
		var uv: Vector2 = face_uvs[corner]
		result.uvs.append(uv_origin + Vector2(uv.x * _blocks.tile_uv_size.x, uv.y * _blocks.tile_uv_size.y))
		var occlusion := 0
		var light_count := 0
		var sky_sum := 0
		var r_sum := 0
		var g_sum := 0
		var b_sum := 0
		if front_index >= 0:
			sky_sum += int(volume.sky[front_index])
			light_count += 1
			if block_light_active:
				r_sum += int(volume.block_r[front_index])
				g_sum += int(volume.block_g[front_index])
				b_sum += int(volume.block_b[front_index])
		var samples: Array = _face_ao_offsets[face][corner]
		for sample in samples:
			var sample_offset: Vector3i = sample
			var sample_index := pad_index + sample_offset.x + sample_offset.z * VoxelDefs.PAD_STRIDE_Z + sample_offset.y * VoxelDefs.PAD_STRIDE_Y
			if _blocks.is_opaque(padded[sample_index]):
				occlusion += 1
				continue
			var sample_x := local_x + LIGHT_PAD + sample_offset.x
			var sample_y := y + sample_offset.y
			var sample_z := local_z + LIGHT_PAD + sample_offset.z
			if sample_x < 0 or sample_x >= volume.w or sample_z < 0 or sample_z >= volume.d or sample_y < 0 or sample_y >= volume.h:
				continue
			var light_index := (sample_y * volume.d + sample_z) * volume.w + sample_x
			sky_sum += int(volume.sky[light_index])
			light_count += 1
			if block_light_active:
				r_sum += int(volume.block_r[light_index])
				g_sum += int(volume.block_g[light_index])
				b_sum += int(volume.block_b[light_index])
		var light := shade * float(VoxelDefs.AO_LEVELS[3 - occlusion])
		result.colors.append(Color(light, light, light, 1.0))
		var inverse := 1.0 / (float(maxi(light_count, 1)) * float(MAX_LEVEL))
		result.light.push_back(float(r_sum) * inverse)
		result.light.push_back(float(g_sum) * inverse)
		result.light.push_back(float(b_sum) * inverse)
		result.light.push_back(float(sky_sum) * inverse)
	var p0: Vector3 = result.verts[base]
	var p1: Vector3 = result.verts[base + 1]
	var p2: Vector3 = result.verts[base + 2]
	var p3: Vector3 = result.verts[base + 3]
	result.indices.append_array(PackedInt32Array([base, base + 2, base + 1, base, base + 3, base + 2]))
	result.collision.append_array(PackedVector3Array([p0, p2, p1, p0, p3, p2]))


func _append_cross_block(origin: Vector3, block_id: int, block_light: Color, sky_light: float, result: MeshResult) -> void:
	var tile := _blocks.tile_for(block_id, 2)
	var uv_origin := _blocks.tile_uv_origin(tile)
	var tile_size := _blocks.tile_uv_size
	var shade := 0.96
	for plane in CROSS_PLANES:
		var base := result.verts.size()
		for corner in 4:
			var offset: Vector3 = plane[corner]
			result.verts.append(origin + offset)
			result.normals.append(Vector3.UP)
			var uv: Vector2 = CROSS_UVS[corner]
			result.uvs.append(uv_origin + Vector2(uv.x * tile_size.x, uv.y * tile_size.y))
			result.colors.append(Color(shade, shade, shade, 1.0))
			result.light.push_back(block_light.r)
			result.light.push_back(block_light.g)
			result.light.push_back(block_light.b)
			result.light.push_back(sky_light)
		result.indices.append_array(PackedInt32Array([base, base + 2, base + 1, base, base + 3, base + 2]))
		result.indices.append_array(PackedInt32Array([base, base + 1, base + 2, base, base + 2, base + 3]))
	_append_cross_collision(origin, result)


func _append_cross_collision(origin: Vector3, result: MeshResult) -> void:
	var min := origin + Vector3(0.3, 0.0, 0.3)
	var max := origin + Vector3(0.7, 0.7, 0.7)
	var corners := PackedVector3Array([
		Vector3(min.x, min.y, min.z), Vector3(max.x, min.y, min.z), Vector3(max.x, min.y, max.z), Vector3(min.x, min.y, max.z),
		Vector3(min.x, max.y, min.z), Vector3(max.x, max.y, min.z), Vector3(max.x, max.y, max.z), Vector3(min.x, max.y, max.z),
	])
	result.collision.append_array(PackedVector3Array([
		corners[0], corners[1], corners[2], corners[0], corners[2], corners[3],
		corners[4], corners[6], corners[5], corners[4], corners[7], corners[6],
		corners[0], corners[4], corners[5], corners[0], corners[5], corners[1],
		corners[3], corners[2], corners[6], corners[3], corners[6], corners[7],
		corners[0], corners[3], corners[7], corners[0], corners[7], corners[4],
		corners[1], corners[5], corners[6], corners[1], corners[6], corners[2],
	]))


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
