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
var _cross: PackedByteArray = PackedByteArray()
var _leaves: PackedByteArray = PackedByteArray()
var _tinted: PackedByteArray = PackedByteArray()
var _water_level: PackedByteArray = PackedByteArray()
var _layer_top: PackedInt32Array = PackedInt32Array()
var _layer_bottom: PackedInt32Array = PackedInt32Array()
var _layer_side: PackedInt32Array = PackedInt32Array()
var _emission_r: PackedByteArray = PackedByteArray()
var _emission_g: PackedByteArray = PackedByteArray()
var _emission_b: PackedByteArray = PackedByteArray()


class MeshResult:
	var data := PackedByteArray()
	var heights := PackedInt32Array()
	var max_y := 0
	var mask := 0
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var light := PackedFloat32Array()
	var layers := PackedFloat32Array()
	var indices := PackedInt32Array()
	var collision := PackedVector3Array()
	var water_verts := PackedVector3Array()
	var water_normals := PackedVector3Array()
	var water_uvs := PackedVector2Array()
	var water_colors := PackedColorArray()
	var water_light := PackedFloat32Array()
	var water_indices := PackedInt32Array()
	var light_volume: LightVolume


class LightVolume:
	var w := 0
	var d := 0
	var h := 0
	var blocks := PackedByteArray()
	var heights := PackedInt32Array()
	var sky := PackedByteArray()
	var block_r := PackedByteArray()
	var block_g := PackedByteArray()
	var block_b := PackedByteArray()


class NeighborSample:
	var data := PackedByteArray()
	var max_y := 0
	var heights := PackedInt32Array()

	func _init(p_data: PackedByteArray, p_max_y: int, p_heights: PackedInt32Array) -> void:
		data = p_data
		max_y = p_max_y
		heights = p_heights


class NeighborSet:
	var mask := 0
	var samples: Dictionary = {}

	func get_sample(direction: Vector2i) -> NeighborSample:
		return samples.get(direction)


const LOD_NONE := -1
const LOD_SIDE_FACES := [4, 5, 2, 3]


class LodEdge:
	var solid := PackedInt32Array()
	var water := PackedInt32Array()


class LodNeighbors:
	var mask := 0
	var edges: Dictionary = {}

	func get_edge(direction: Vector2i) -> LodEdge:
		return edges.get(direction)


func _init(blocks: BlockRegistry) -> void:
	_blocks = blocks
	_build_ao_offsets()
	_build_light_tables()


## Thread-safe: only reads immutable block tables once constructed.
func build(data: PackedByteArray, data_max_y: int, heights: PackedInt32Array, foliage_tints: PackedColorArray, water_tints: PackedColorArray, neighbors: NeighborSet) -> MeshResult:
	var result := MeshResult.new()
	result.data = data
	result.heights = heights
	result.mask = neighbors.mask
	var max_y := clampi(data_max_y + 1, 1, VoxelDefs.WORLD_HEIGHT - 1)
	result.max_y = max_y
	var light_volume := _assemble_light_volume(data, data_max_y, heights, neighbors)
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
				var column := local_x + local_z * VoxelDefs.DATA_STRIDE_Z
				var pad_index := (local_x + 1) + (local_z + 1) * VoxelDefs.PAD_STRIDE_Z + (y + 1) * VoxelDefs.PAD_STRIDE_Y
				var id := padded[pad_index]
				if id == BlockRegistry.BLOCK_AIR:
					continue
				if _water_level[id] > 0:
					_append_water_block(padded, pad_index, local_x, y, local_z, _column_tint(column, water_tints), result)
					continue
				if _cross[id] == 1:
					var volume: LightVolume = result.light_volume
					var light_index := (y * volume.d + local_z + LIGHT_PAD) * volume.w + local_x + LIGHT_PAD
					var sky_light := float(volume.sky[light_index]) / float(MAX_LEVEL)
					var block_light := Color.BLACK
					if not volume.block_r.is_empty():
						block_light = Color(
							float(volume.block_r[light_index]) / float(MAX_LEVEL),
							float(volume.block_g[light_index]) / float(MAX_LEVEL),
							float(volume.block_b[light_index]) / float(MAX_LEVEL))
					_append_cross_block(Vector3(local_x, y, local_z), id, block_light, sky_light, _tint_for(id, column, foliage_tints), result)
					continue
				var is_opaque := _opacity[id] >= MAX_LEVEL
				var tint := _tint_for(id, column, foliage_tints)
				for face in 6:
					var normal: Vector3i = VoxelDefs.FACE_NORMALS[face]
					var neighbor_index := pad_index + normal.x + normal.z * VoxelDefs.PAD_STRIDE_Z + normal.y * VoxelDefs.PAD_STRIDE_Y
					var neighbor_id := padded[neighbor_index]
					if _opacity[neighbor_id] >= MAX_LEVEL:
						continue
					if not is_opaque and neighbor_id == id and _leaves[id] == 0:
						continue
					_append_face(face, pad_index, local_x, y, local_z, id, padded, tint, result)
	result.light_volume = null
	return result


## Distance mesh: one textured top quad per column plus vertical runs of side
## quads on exposed edges. No light volume, AO, collision, or cross blocks;
## the surface height matches the full mesh so chunk seams stay closed.
## Thread-safe: only reads immutable block tables and the passed-in data.
func build_lod(data: PackedByteArray, data_max_y: int, heights: PackedInt32Array, foliage_tints: PackedColorArray, water_tints: PackedColorArray, neighbors: LodNeighbors) -> MeshResult:
	var result := MeshResult.new()
	result.data = data
	result.heights = heights
	result.mask = neighbors.mask
	result.max_y = data_max_y
	var solid_y := PackedInt32Array()
	var solid_id := PackedByteArray()
	var water_y := PackedInt32Array()
	var water_id := PackedByteArray()
	solid_y.resize(VoxelDefs.CHUNK_AREA)
	solid_id.resize(VoxelDefs.CHUNK_AREA)
	water_y.resize(VoxelDefs.CHUNK_AREA)
	water_id.resize(VoxelDefs.CHUNK_AREA)
	solid_y.fill(LOD_NONE)
	water_y.fill(LOD_NONE)
	for z in VoxelDefs.CHUNK_SIZE:
		for x in VoxelDefs.CHUNK_SIZE:
			var column := x + z * VoxelDefs.DATA_STRIDE_Z
			for y in range(data_max_y, -1, -1):
				var id := data[column + y * VoxelDefs.DATA_STRIDE_Y]
				if id == BlockRegistry.BLOCK_AIR:
					continue
				if _water_level[id] > 0:
					if water_y[column] == LOD_NONE:
						water_y[column] = y
						water_id[column] = id
					continue
				if _cross[id] == 1:
					continue
				solid_y[column] = y
				solid_id[column] = id
				break
	for z in VoxelDefs.CHUNK_SIZE:
		for x in VoxelDefs.CHUNK_SIZE:
			var column := x + z * VoxelDefs.DATA_STRIDE_Z
			var top_solid := solid_y[column]
			var top_water := water_y[column]
			if top_solid >= 0:
				_append_lod_block_face(0, x, top_solid, z, solid_id[column], _tint_for(solid_id[column], column, foliage_tints), result)
			if top_water >= 0:
				var above := BlockRegistry.BLOCK_AIR
				if top_water + 1 <= data_max_y:
					above = data[column + (top_water + 1) * VoxelDefs.DATA_STRIDE_Y]
				if _water_level[above] == 0 and _opacity[above] < MAX_LEVEL:
					var water_level := _water_level[water_id[column]]
					_append_lod_water_face(0, x, top_water, z, _water_top(water_level), water_level < 8, _column_tint(column, water_tints), result)
			for index in VoxelDefs.DIRS_4.size():
				var direction: Vector2i = VoxelDefs.DIRS_4[index]
				var neighbor_solid := -1
				var neighbor_water := -1
				var neighbor_x := x + direction.x
				var neighbor_z := z + direction.y
				if neighbor_x >= 0 and neighbor_x < VoxelDefs.CHUNK_SIZE and neighbor_z >= 0 and neighbor_z < VoxelDefs.CHUNK_SIZE:
					var neighbor_column := neighbor_x + neighbor_z * VoxelDefs.DATA_STRIDE_Z
					neighbor_solid = solid_y[neighbor_column]
					neighbor_water = water_y[neighbor_column]
				else:
					var edge := neighbors.get_edge(direction)
					if edge != null:
						var edge_index := z if direction.x != 0 else x
						neighbor_solid = edge.solid[edge_index]
						neighbor_water = edge.water[edge_index]
				var face: int = LOD_SIDE_FACES[index]
				var exposed_from := maxi(neighbor_solid, neighbor_water) + 1
				for y in range(exposed_from, maxi(top_solid, top_water) + 1):
					var id := data[column + y * VoxelDefs.DATA_STRIDE_Y]
					if id == BlockRegistry.BLOCK_AIR or _cross[id] == 1:
						continue
					if _water_level[id] > 0:
						if y > neighbor_water:
							var level := _water_level[id]
							var above_water := false
							if y + 1 <= data_max_y:
								above_water = _water_level[data[column + (y + 1) * VoxelDefs.DATA_STRIDE_Y]] > 0
							var top := 1.0 if above_water else _water_top(level)
							_append_lod_water_face(face, x, y, z, top, level < 8, _column_tint(column, water_tints), result)
					elif y <= top_solid:
						_append_lod_block_face(face, x, y, z, id, _tint_for(id, column, foliage_tints), result)
	return result


func _append_lod_block_face(face: int, x: int, y: int, z: int, block_id: int, tint: Color, result: MeshResult) -> void:
	var normal: Vector3i = VoxelDefs.FACE_NORMALS[face]
	var layer := _layer_for(block_id, face)
	var base := result.verts.size()
	var face_verts: Array = VoxelDefs.FACE_VERTS[face]
	var face_uvs: Array = VoxelDefs.FACE_UVS[face]
	var shade: float = VoxelDefs.FACE_SHADE[face]
	for corner in 4:
		var offset: Vector3i = face_verts[corner]
		result.verts.append(Vector3(x + offset.x, y + offset.y, z + offset.z))
		result.normals.append(Vector3(normal))
		result.uvs.append(face_uvs[corner])
		result.colors.append(Color(shade * tint.r, shade * tint.g, shade * tint.b, 1.0))
		result.layers.push_back(float(layer))
		result.light.append_array(PackedFloat32Array([0.0, 0.0, 0.0, 1.0]))
	result.indices.append_array(PackedInt32Array([base, base + 2, base + 1, base, base + 3, base + 2]))


func _append_lod_water_face(face: int, x: int, y: int, z: int, top: float, flowing: bool, tint: Color, result: MeshResult) -> void:
	var normal: Vector3i = VoxelDefs.FACE_NORMALS[face]
	var base := result.water_verts.size()
	var face_verts: Array = VoxelDefs.FACE_VERTS[face]
	var shade := 1.0 if face == 0 else 0.92
	var flow_alpha := 0.72 if flowing else 1.0
	for corner in 4:
		var offset: Vector3i = face_verts[corner]
		result.water_verts.append(Vector3(x + offset.x, y + (top if offset.y == 1 else 0.0), z + offset.z))
		result.water_normals.append(Vector3(normal))
		result.water_uvs.append(Vector2(x + offset.x, z + offset.z))
		result.water_colors.append(Color(shade * tint.r, shade * tint.g, shade * tint.b, flow_alpha))
		result.water_light.append_array(PackedFloat32Array([0.0, 0.0, 0.0, 1.0]))
	result.water_indices.append_array(PackedInt32Array([base, base + 2, base + 1, base, base + 3, base + 2]))


func make_block_mesh(block_id: int) -> ArrayMesh:
	if not _blocks.is_valid_id(block_id):
		block_id = BlockRegistry.BLOCK_GRASS
	if _cross[block_id] == 1:
		var cross := MeshResult.new()
		_append_cross_block(Vector3(-0.5, -0.5, -0.5), block_id, Color.BLACK, 1.0, Color.WHITE, cross)
		return arrays_to_mesh(cross.verts, cross.normals, cross.uvs, cross.colors, cross.indices, _blocks.material, cross.light, cross.layers)
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var light := PackedFloat32Array()
	var layers := PackedFloat32Array()
	var indices := PackedInt32Array()
	for face in 6:
		var normal: Vector3i = VoxelDefs.FACE_NORMALS[face]
		var layer := _layer_for(block_id, face)
		var base := verts.size()
		var face_verts: Array = VoxelDefs.FACE_VERTS[face]
		var face_uvs: Array = VoxelDefs.FACE_UVS[face]
		var shade: float = VoxelDefs.FACE_SHADE[face]
		for corner in 4:
			var offset: Vector3i = face_verts[corner]
			verts.append(Vector3(offset.x, offset.y, offset.z) - Vector3(0.5, 0.5, 0.5))
			normals.append(Vector3(normal))
			uvs.append(face_uvs[corner])
			colors.append(Color(shade, shade, shade, 1.0))
			light.append_array(PackedFloat32Array([0.0, 0.0, 0.0, 1.0]))
			layers.push_back(float(layer))
		indices.append_array(PackedInt32Array([base, base + 2, base + 1, base, base + 3, base + 2]))
	return arrays_to_mesh(verts, normals, uvs, colors, indices, _blocks.material, light, layers)


static func arrays_to_mesh(verts: PackedVector3Array, normals: PackedVector3Array, uvs: PackedVector2Array, colors: PackedColorArray, indices: PackedInt32Array, material: Material, light := PackedFloat32Array(), layers := PackedFloat32Array()) -> ArrayMesh:
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
	if not layers.is_empty():
		arrays[Mesh.ARRAY_CUSTOM1] = layers
		flags |= Mesh.ARRAY_FORMAT_CUSTOM1 | (Mesh.ARRAY_CUSTOM_R_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT)
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, flags)
	mesh.surface_set_material(0, material)
	return mesh


func _build_light_tables() -> void:
	_opacity.resize(256)
	_cross.resize(256)
	_leaves.resize(256)
	_tinted.resize(256)
	_water_level.resize(256)
	_layer_top.resize(256)
	_layer_bottom.resize(256)
	_layer_side.resize(256)
	_emission_r.resize(256)
	_emission_g.resize(256)
	_emission_b.resize(256)
	for id in 256:
		_opacity[id] = _blocks.light_attenuation(id)
		_cross[id] = 1 if _blocks.has_flag(id, BlockRegistry.FLAG_CROSS) else 0
		_leaves[id] = 1 if _blocks.has_flag(id, BlockRegistry.FLAG_LEAVES) else 0
		_tinted[id] = 1 if _blocks.has_flag(id, BlockRegistry.FLAG_TINTED) else 0
		_water_level[id] = _blocks.water_level(id)
		if id == BlockRegistry.BLOCK_AIR or _blocks.is_valid_id(id):
			_layer_top[id] = _blocks.layer_for(id, 0)
			_layer_bottom[id] = _blocks.layer_for(id, 1)
			_layer_side[id] = _blocks.layer_for(id, 2)
		var color := _blocks.emission_color(id)
		if color == Color.BLACK:
			continue
		_emission_r[id] = roundi(color.r * MAX_LEVEL)
		_emission_g[id] = roundi(color.g * MAX_LEVEL)
		_emission_b[id] = roundi(color.b * MAX_LEVEL)


## Assembles a 3x3 chunk footprint of block IDs so light from emitters and sky
## openings up to 15 blocks outside the chunk is accounted for.
func _assemble_light_volume(data: PackedByteArray, data_max_y: int, data_heights: PackedInt32Array, neighbors: NeighborSet) -> LightVolume:
	var volume := LightVolume.new()
	volume.w = VoxelDefs.CHUNK_SIZE * 3
	volume.d = VoxelDefs.CHUNK_SIZE * 3
	var tiles: Array[PackedByteArray] = []
	tiles.resize(9)
	var tile_heights: Array[PackedInt32Array] = []
	tile_heights.resize(9)
	var tile_max := PackedInt32Array()
	tile_max.resize(9)
	var max_y := data_max_y
	for tile_z in 3:
		for tile_x in 3:
			var index := tile_z * 3 + tile_x
			var direction := Vector2i(tile_x - 1, tile_z - 1)
			if direction == Vector2i.ZERO:
				tiles[index] = data
				tile_heights[index] = data_heights
				tile_max[index] = data_max_y
			else:
				var sample := neighbors.get_sample(direction)
				if sample != null:
					tiles[index] = sample.data
					tile_heights[index] = sample.heights
					tile_max[index] = sample.max_y
					max_y = maxi(max_y, sample.max_y)
	volume.h = mini(max_y + 3, VoxelDefs.WORLD_HEIGHT)
	volume.heights.resize(volume.w * volume.d)
	volume.heights.fill(volume.h - 1)
	for tile_z in 3:
		for tile_x in 3:
			var index := tile_z * 3 + tile_x
			var heights := tile_heights[index]
			if heights.is_empty():
				continue
			for local_z in VoxelDefs.CHUNK_SIZE:
				var destination := (tile_z * VoxelDefs.CHUNK_SIZE + local_z) * volume.w + tile_x * VoxelDefs.CHUNK_SIZE
				var source := local_z * VoxelDefs.CHUNK_SIZE
				for local_x in VoxelDefs.CHUNK_SIZE:
					volume.heights[destination + local_x] = heights[source + local_x]
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
	var heights := volume.heights
	var queue := PackedInt32Array()
	queue.resize(blocks.size() * 2)
	var head := 0
	var tail := 0
	for volume_z in volume.d:
		for vx in w:
			var column := volume_z * w + vx
			var top := mini(int(heights[column]), volume.h - 1)
			for fill_y in range(top + 1, volume.h):
				sky[fill_y * area + column] = MAX_LEVEL
			var level := MAX_LEVEL
			var y := top
			while y >= 0:
				var index := y * area + column
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
			if top + 1 < volume.h:
				for direction in 4:
					var nx := vx
					var nz := volume_z
					match direction:
						0:
							nx -= 1
						1:
							nx += 1
						2:
							nz -= 1
						_:
							nz += 1
					if nx < 0 or nx >= w or nz < 0 or nz >= volume.d:
						continue
					var neighbor_top := mini(int(heights[nz * w + nx]), volume.h)
					if neighbor_top <= top + 1:
						continue
					var seed_level := MAX_LEVEL - 1
					var neighbor_y := top + 1
					while neighbor_y < neighbor_top:
						var ni := neighbor_y * area + nz * w + nx
						if _opacity[blocks[ni]] >= MAX_LEVEL:
							break
						if sky[ni] < seed_level:
							sky[ni] = seed_level
							if tail < queue.size():
								queue[tail] = ni
								tail += 1
						neighbor_y += 1
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


func _append_face(face: int, pad_index: int, local_x: int, y: int, local_z: int, block_id: int, padded: PackedByteArray, tint: Color, result: MeshResult) -> void:
	var normal: Vector3i = VoxelDefs.FACE_NORMALS[face]
	var shade: float = VoxelDefs.FACE_SHADE[face]
	var layer := _layer_for(block_id, face)
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
		result.uvs.append(face_uvs[corner])
		result.layers.push_back(float(layer))
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
			if _opacity[padded[sample_index]] >= MAX_LEVEL:
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
		result.colors.append(Color(light * tint.r, light * tint.g, light * tint.b, 1.0))
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


func _append_cross_block(origin: Vector3, block_id: int, block_light: Color, sky_light: float, tint: Color, result: MeshResult) -> void:
	var layer := _layer_side[block_id]
	var shade := 0.96
	for plane in CROSS_PLANES:
		var base := result.verts.size()
		for corner in 4:
			var offset: Vector3 = plane[corner]
			result.verts.append(origin + offset)
			result.normals.append(Vector3.UP)
			result.uvs.append(CROSS_UVS[corner])
			result.colors.append(Color(shade * tint.r, shade * tint.g, shade * tint.b, 1.0))
			result.layers.push_back(float(layer))
			result.light.push_back(block_light.r)
			result.light.push_back(block_light.g)
			result.light.push_back(block_light.b)
			result.light.push_back(sky_light)
		result.indices.append_array(PackedInt32Array([base, base + 2, base + 1, base, base + 3, base + 2]))
		result.indices.append_array(PackedInt32Array([base, base + 1, base + 2, base, base + 2, base + 3]))


func _tint_for(block_id: int, column: int, foliage_tints: PackedColorArray) -> Color:
	if _tinted[block_id] == 0 or column < 0 or column >= foliage_tints.size():
		return Color.WHITE
	return foliage_tints[column]


func _layer_for(block_id: int, face: int) -> int:
	if face == 0:
		return _layer_top[block_id]
	if face == 1:
		return _layer_bottom[block_id]
	return _layer_side[block_id]


func _column_tint(column: int, tints: PackedColorArray) -> Color:
	return tints[column] if column >= 0 and column < tints.size() else Color.WHITE


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


## Compresses the 1..8 flow levels into a narrower height range so larger
## flows read as a gentle slope instead of a staircase.
func _water_top(level: int) -> float:
	return 0.9 * (0.35 + 0.65 * float(level) / 8.0)


func _append_water_block(padded: PackedByteArray, pad_index: int, local_x: int, y: int, local_z: int, tint: Color, result: MeshResult) -> void:
	var level := _water_level[padded[pad_index]]
	var above := padded[pad_index + VoxelDefs.PAD_STRIDE_Y]
	var above_water := _water_level[above] > 0
	var top := 1.0 if above_water else _water_top(level)
	var flowing := level < 8
	if not above_water and _opacity[above] < MAX_LEVEL:
		_append_water_face(0, local_x, y, local_z, top, flowing, tint, result)
	for face in range(2, 6):
		var normal: Vector3i = VoxelDefs.FACE_NORMALS[face]
		var neighbor_index := pad_index + normal.x + normal.z * VoxelDefs.PAD_STRIDE_Z + normal.y * VoxelDefs.PAD_STRIDE_Y
		var neighbor := padded[neighbor_index]
		if _opacity[neighbor] >= MAX_LEVEL:
			continue
		if _water_level[neighbor] >= level and _water_level[neighbor] > 0:
			continue
		_append_water_face(face, local_x, y, local_z, top, flowing, tint, result)


func _append_water_face(face: int, local_x: int, y: int, local_z: int, top: float, flowing: bool, tint: Color, result: MeshResult) -> void:
	var normal: Vector3i = VoxelDefs.FACE_NORMALS[face]
	var base := result.water_verts.size()
	var face_verts: Array = VoxelDefs.FACE_VERTS[face]
	var shade := 1.0 if face == 0 else 0.92
	var flow_alpha := 0.72 if flowing else 1.0
	for corner in 4:
		var offset: Vector3i = face_verts[corner]
		result.water_verts.append(Vector3(local_x + offset.x, y + (top if offset.y == 1 else 0.0), local_z + offset.z))
		result.water_normals.append(Vector3(normal))
		result.water_uvs.append(Vector2(local_x + offset.x, local_z + offset.z))
		result.water_colors.append(Color(shade * tint.r, shade * tint.g, shade * tint.b, flow_alpha))
		var light := _sample_water_light(result.light_volume, local_x, y, local_z, face, corner)
		result.water_light.push_back(light.r)
		result.water_light.push_back(light.g)
		result.water_light.push_back(light.b)
		result.water_light.push_back(light.a)
	result.water_indices.append_array(PackedInt32Array([base, base + 2, base + 1, base, base + 3, base + 2]))


func _sample_water_light(volume: LightVolume, local_x: int, y: int, local_z: int, face: int, corner: int) -> Color:
	var block_light_active := not volume.block_r.is_empty()
	var normal: Vector3i = VoxelDefs.FACE_NORMALS[face]
	var sky_sum := 0
	var r_sum := 0
	var g_sum := 0
	var b_sum := 0
	var count := 0
	var front_y := y + normal.y
	if front_y >= 0 and front_y < volume.h:
		var index := (front_y * volume.d + local_z + LIGHT_PAD + normal.z) * volume.w + local_x + LIGHT_PAD + normal.x
		sky_sum += int(volume.sky[index])
		count += 1
		if block_light_active:
			r_sum += int(volume.block_r[index])
			g_sum += int(volume.block_g[index])
			b_sum += int(volume.block_b[index])
	var samples: Array = _face_ao_offsets[face][corner]
	for sample in samples:
		var offset: Vector3i = sample
		var sample_x := local_x + LIGHT_PAD + offset.x
		var sample_y := y + offset.y
		var sample_z := local_z + LIGHT_PAD + offset.z
		if sample_x < 0 or sample_x >= volume.w or sample_z < 0 or sample_z >= volume.d or sample_y < 0 or sample_y >= volume.h:
			continue
		var index := (sample_y * volume.d + sample_z) * volume.w + sample_x
		if _opacity[volume.blocks[index]] >= MAX_LEVEL:
			continue
		sky_sum += int(volume.sky[index])
		count += 1
		if block_light_active:
			r_sum += int(volume.block_r[index])
			g_sum += int(volume.block_g[index])
			b_sum += int(volume.block_b[index])
	var inverse := 1.0 / (float(maxi(count, 1)) * float(MAX_LEVEL))
	return Color(float(r_sum) * inverse, float(g_sum) * inverse, float(b_sum) * inverse, float(sky_sum) * inverse)
