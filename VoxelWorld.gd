extends Node3D

const CHUNK_SIZE := 16
const CHUNK_AREA := CHUNK_SIZE * CHUNK_SIZE
const WORLD_HEIGHT := 128
const SEA_LEVEL := 32
var render_distance := 10
var unload_radius := 12
const SPAWN_RADIUS := 1
const MAX_ACTIVE_JOBS := 12
const COMMIT_BUDGET_MS := 5
const PAD_W := CHUNK_SIZE + 2
const PAD_STRIDE_Z := PAD_W
const PAD_STRIDE_Y := PAD_W * PAD_W
const DATA_STRIDE_Z := CHUNK_SIZE
const DATA_STRIDE_Y := CHUNK_AREA

const BLOCK_AIR := 0
const BLOCK_GRASS := 1
const BLOCK_DIRT := 2
const BLOCK_STONE := 3
const BLOCK_COBBLESTONE := 4
const BLOCK_LOG := 5
const BLOCK_LEAVES := 6
const BLOCK_SAND := 7
const BLOCK_GLASS := 8
const BLOCK_GLOWSTONE := 9
const BLOCK_SNOW := 10
const BLOCK_BEDROCK := 11
const BLOCK_GRAVEL := 12
const BLOCK_COAL_ORE := 13
const BLOCK_IRON_ORE := 14
const BLOCK_GOLD_ORE := 15
const BLOCK_WATER := 16
const BLOCK_CLAY := 17
const BLOCK_MUD := 18
const BLOCK_RED_SAND := 19
const BLOCK_CACTUS := 20
const BLOCK_SPRUCE_LOG := 21
const BLOCK_SPRUCE_LEAVES := 22
const BLOCK_BIRCH_LOG := 23
const BLOCK_BIRCH_LEAVES := 24
const BLOCK_TERRACOTTA := 25
const BLOCK_MYCELIUM := 26

const FLAG_OPAQUE := 1
const FLAG_CUTOUT := 2
const FLAG_UNBREAKABLE := 4
const FLAG_LEAVES := 8

const BLOCK_DEFS := [
	[0, "AIR", "", "", "", 0],
	[1, "GRASS", "grass_top.png", "grass_side.png", "dirt.png", FLAG_OPAQUE],
	[2, "DIRT", "dirt.png", "dirt.png", "dirt.png", FLAG_OPAQUE],
	[3, "STONE", "stone.png", "stone.png", "stone.png", FLAG_OPAQUE],
	[4, "COBBLESTONE", "cobblestone.png", "cobblestone.png", "cobblestone.png", FLAG_OPAQUE],
	[5, "OAK LOG", "wood_top.png", "wood_side.png", "wood_top.png", FLAG_OPAQUE],
	[6, "OAK LEAVES", "leaves.png", "leaves.png", "leaves.png", FLAG_CUTOUT | FLAG_LEAVES],
	[7, "SAND", "sand.png", "sand.png", "sand.png", FLAG_OPAQUE],
	[8, "GLASS", "glass.png", "glass.png", "glass.png", FLAG_CUTOUT],
	[9, "GLOWSTONE", "glowstone.png", "glowstone.png", "glowstone.png", FLAG_OPAQUE],
	[10, "SNOW", "snow_block.png", "snow_block.png", "snow_block.png", FLAG_OPAQUE],
	[11, "BEDROCK", "bedrock.png", "bedrock.png", "bedrock.png", FLAG_OPAQUE | FLAG_UNBREAKABLE],
	[12, "GRAVEL", "gravel.png", "gravel.png", "gravel.png", FLAG_OPAQUE],
	[13, "COAL ORE", "coal_ore.png", "coal_ore.png", "coal_ore.png", FLAG_OPAQUE],
	[14, "IRON ORE", "iron_ore.png", "iron_ore.png", "iron_ore.png", FLAG_OPAQUE],
	[15, "GOLD ORE", "gold_ore.png", "gold_ore.png", "gold_ore.png", FLAG_OPAQUE],
	[16, "WATER", "water.png", "water.png", "water.png", 0],
	[17, "CLAY", "clay.png", "clay.png", "clay.png", FLAG_OPAQUE],
	[18, "MUD", "mud.png", "mud.png", "mud.png", FLAG_OPAQUE],
	[19, "RED SAND", "red_sand.png", "red_sand.png", "red_sand.png", FLAG_OPAQUE],
	[20, "CACTUS", "cactus_top.png", "cactus_side.png", "cactus_top.png", FLAG_OPAQUE],
	[21, "SPRUCE LOG", "spruce_log_top.png", "spruce_log_side.png", "spruce_log_top.png", FLAG_OPAQUE],
	[22, "SPRUCE LEAVES", "spruce_leaves.png", "spruce_leaves.png", "spruce_leaves.png", FLAG_CUTOUT | FLAG_LEAVES],
	[23, "BIRCH LOG", "birch_log_top.png", "birch_log_side.png", "birch_log_top.png", FLAG_OPAQUE],
	[24, "BIRCH LEAVES", "birch_leaves.png", "birch_leaves.png", "birch_leaves.png", FLAG_CUTOUT | FLAG_LEAVES],
	[25, "TERRACOTTA", "terracotta.png", "terracotta.png", "terracotta.png", FLAG_OPAQUE],
	[26, "MYCELIUM", "mycelium_top.png", "mycelium_side.png", "dirt.png", FLAG_OPAQUE],
]

const BIOME_PLAINS := 0
const BIOME_FOREST := 1
const BIOME_DESERT := 2
const BIOME_SNOW := 3
const BIOME_SWAMP := 4

const FACE_NORMALS := [
	Vector3i(0, 1, 0), Vector3i(0, -1, 0),
	Vector3i(0, 0, 1), Vector3i(0, 0, -1),
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
]
const FACE_VERTS := [
	[Vector3i(0, 1, 1), Vector3i(1, 1, 1), Vector3i(1, 1, 0), Vector3i(0, 1, 0)],
	[Vector3i(0, 0, 0), Vector3i(1, 0, 0), Vector3i(1, 0, 1), Vector3i(0, 0, 1)],
	[Vector3i(0, 0, 1), Vector3i(1, 0, 1), Vector3i(1, 1, 1), Vector3i(0, 1, 1)],
	[Vector3i(1, 0, 0), Vector3i(0, 0, 0), Vector3i(0, 1, 0), Vector3i(1, 1, 0)],
	[Vector3i(1, 0, 1), Vector3i(1, 0, 0), Vector3i(1, 1, 0), Vector3i(1, 1, 1)],
	[Vector3i(0, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 1, 1), Vector3i(0, 1, 0)],
]
const FACE_UVS := [
	[Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)],
	[Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)],
	[Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)],
	[Vector2(1, 1), Vector2(0, 1), Vector2(0, 0), Vector2(1, 0)],
	[Vector2(1, 1), Vector2(0, 1), Vector2(0, 0), Vector2(1, 0)],
	[Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)],
]
const FACE_TANGENT_A := [
	Vector3i(1, 0, 0), Vector3i(1, 0, 0),
	Vector3i(1, 0, 0), Vector3i(1, 0, 0),
	Vector3i(0, 0, 1), Vector3i(0, 0, 1),
]
const FACE_TANGENT_B := [
	Vector3i(0, 0, 1), Vector3i(0, 0, 1),
	Vector3i(0, 1, 0), Vector3i(0, 1, 0),
	Vector3i(0, 1, 0), Vector3i(0, 1, 0),
]
const FACE_SHADE := [1.0, 0.5, 0.82, 0.82, 0.66, 0.66]
const AO_LEVELS := [0.4, 0.62, 0.82, 1.0]

const DIRS_4 := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
const DIRS_8 := [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
]

const TEXTURE_ROOT := "res://assets/placeholders/zigcraft/default/"
const WATER_SHADER_PATH := "res://assets/placeholders/zigcraft/water.gdshader"
const TILE_PX := 64
const ATLAS_COLUMNS := 8
const UV_INSET := 2.0
const TEXTURE_TINTS := {
	"grass_top.png": Color(0.44, 0.84, 0.34),
	"leaves.png": Color(0.62, 1.15, 0.5),
	"spruce_leaves.png": Color(0.5, 1.05, 0.6),
	"birch_leaves.png": Color(0.78, 1.3, 0.55),
	"mycelium_top.png": Color(0.82, 0.68, 0.9),
	"sand.png": Color(0.98, 0.9, 0.64),
	"red_sand.png": Color(1.0, 0.84, 0.72),
}

var _chunks: Dictionary = {}
var _pending: Dictionary = {}
var _commit_queue: Array = []
var _gen_queue: Array = []
var _dirty: Dictionary = {}
var _desired: Dictionary = {}
var _edited_blocks: Dictionary = {}
var _chunk_edit_version: Dictionary = {}
var _stream_center := Vector2i(999999, 999999)
var _player: Node3D
var _water_mat: Material
var _blocks_mat: StandardMaterial3D
var _block_flags: PackedByteArray = PackedByteArray()
var _block_opaque: PackedByteArray = PackedByteArray()
var _block_tile_top: PackedInt32Array = PackedInt32Array()
var _block_tile_side: PackedInt32Array = PackedInt32Array()
var _block_tile_bottom: PackedInt32Array = PackedInt32Array()
var _block_names: PackedStringArray = PackedStringArray()
var _tile_uv_origin: PackedVector2Array = PackedVector2Array()
var _tile_uv_size := Vector2.ZERO
var _face_ao_offsets: Array = []
var _noise: Array = []
var world_seed := 0
var world_type := 0
var terrain_scale := 1.0
var tree_density := 1.0


func _ready() -> void:
	_setup_blocks()
	_setup_face_tables()
	_noise = _make_noise_set()


func apply_world_config() -> void:
	terrain_scale = clampf(terrain_scale, 0.4, 3.0)
	tree_density = clampf(tree_density, 0.0, 3.0)
	if world_type == 2:
		terrain_scale = maxf(terrain_scale, 1.0) * 1.8
	_noise = _make_noise_set()


func _process(_delta: float) -> void:
	if _player == null:
		return
	_stream_tick()


func _exit_tree() -> void:
	for pos in _pending.keys():
		WorkerThreadPool.wait_for_task_completion(_pending[pos]["task"])
	_pending.clear()


func setup_player(player_node: Node3D) -> void:
	_player = player_node
	_stream_center = _chunk_for_position(player_node.global_position)
	_generate_spawn_area()
	_rebuild_desired()
	_schedule_jobs()


func _stream_tick() -> void:
	var center := _chunk_for_position(_player.global_position)
	if center != _stream_center:
		_stream_center = center
		_rebuild_desired()
	_collect_jobs()
	_process_commit_queue()
	_schedule_jobs()
	_unload_far()


func _generate_spawn_area() -> void:
	for ring in range(SPAWN_RADIUS + 1):
		for dx in range(-ring, ring + 1):
			for dz in range(-ring, ring + 1):
				if maxi(absi(dx), absi(dz)) != ring:
					continue
				var pos := _stream_center + Vector2i(dx, dz)
				if _chunks.has(pos):
					continue
				var res := _job_generate(pos, _edited_blocks.duplicate(), _gather_neighbors(pos))
				_commit_chunk(pos, res)


func _rebuild_desired() -> void:
	_desired.clear()
	var wanted: Array = []
	for dx in range(-render_distance, render_distance + 1):
		for dz in range(-render_distance, render_distance + 1):
			var pos := _stream_center + Vector2i(dx, dz)
			_desired[pos] = true
			if not _chunks.has(pos) and not _pending.has(pos):
				wanted.append(pos)
	var center := _stream_center
	wanted.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var da := (a - center).length_squared()
		var db := (b - center).length_squared()
		return da < db
	)
	_gen_queue = wanted
	for pos in _dirty.keys():
		if _desired.has(pos) and not _pending.has(pos) and not _gen_queue.has(pos):
			_gen_queue.push_front(pos)


func _schedule_jobs() -> void:
	var edits_snapshot := _edited_blocks.duplicate()
	while _pending.size() < MAX_ACTIVE_JOBS and not _gen_queue.is_empty():
		var pos: Vector2i = _gen_queue.pop_front()
		if _pending.has(pos):
			continue
		if _chunks.has(pos) and not _dirty.has(pos):
			continue
		_dirty.erase(pos)
		var version: int = _chunk_edit_version.get(pos, 0)
		var neighbors := _gather_neighbors(pos)
		var slot := {}
		var task := WorkerThreadPool.add_task(_job_generate.bind(pos, edits_snapshot, neighbors, slot), true, "voxel_chunk")
		_pending[pos] = {"task": task, "version": version, "neighbors": neighbors, "slot": slot}


func _process_commit_queue() -> void:
	var start := Time.get_ticks_msec()
	while not _commit_queue.is_empty():
		var item: Dictionary = _commit_queue.pop_front()
		var pos: Vector2i = item["pos"]
		if not _desired.has(pos):
			continue
		if item["version"] != _chunk_edit_version.get(pos, 0):
			_queue_rebuild(pos)
			continue
		_commit_chunk(pos, item["result"])
		if Time.get_ticks_msec() - start > COMMIT_BUDGET_MS:
			break


func _collect_jobs() -> void:
	for pos in _pending.keys():
		var info: Dictionary = _pending[pos]
		if not WorkerThreadPool.is_task_completed(info["task"]):
			continue
		WorkerThreadPool.wait_for_task_completion(info["task"])
		_pending.erase(pos)
		var slot: Dictionary = info["slot"]
		if not slot.has("result"):
			continue
		_commit_queue.append({"pos": pos, "result": slot["result"], "version": info["version"]})


func _gather_neighbors(pos: Vector2i) -> Dictionary:
	var out := {"mask": 0}
	for index in DIRS_8.size():
		var dir: Vector2i = DIRS_8[index]
		var entry: Dictionary = _chunks.get(pos + dir, {})
		if entry.is_empty():
			continue
		out[dir] = {
			"data": (entry["data"] as PackedByteArray).duplicate(),
			"max_y": entry["max_y"],
		}
		if index < 4:
			out["mask"] = int(out["mask"]) | (1 << index)
	return out


func _commit_chunk(pos: Vector2i, res: Dictionary) -> void:
	var entry: Dictionary = _chunks.get(pos, {})
	var mesh := _arrays_to_mesh(res["verts"], res["normals"], res["uvs"], res["colors"], res["indices"], _blocks_mat)
	var water_mesh := _arrays_to_mesh(res["wverts"], res["wnormals"], res["wuvs"], res["wcolors"], res["windices"], _water_mat)
	if entry.is_empty():
		entry = {
			"data": res["data"],
			"max_y": res["max_y"],
			"mesh": null,
			"water": null,
			"body": null,
			"shape": null,
			"mask": res["mask"],
		}
		_chunks[pos] = entry
		var block_instance := MeshInstance3D.new()
		block_instance.name = "Chunk_%d_%d" % [pos.x, pos.y]
		block_instance.position = Vector3(pos.x * CHUNK_SIZE, 0.0, pos.y * CHUNK_SIZE)
		add_child(block_instance)
		entry["mesh"] = block_instance
		var water_instance := MeshInstance3D.new()
		water_instance.name = "Water_%d_%d" % [pos.x, pos.y]
		water_instance.position = block_instance.position
		water_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(water_instance)
		entry["water"] = water_instance
		var body := StaticBody3D.new()
		body.name = "Body_%d_%d" % [pos.x, pos.y]
		body.position = block_instance.position
		body.collision_layer = 1
		body.collision_mask = 0
		add_child(body)
		entry["body"] = body
		var shape_node := CollisionShape3D.new()
		body.add_child(shape_node)
		entry["shape"] = shape_node
	else:
		entry["data"] = res["data"]
		entry["max_y"] = res["max_y"]
		entry["mask"] = res["mask"]
	var block_instance: MeshInstance3D = entry["mesh"]
	block_instance.mesh = mesh
	var water_instance: MeshInstance3D = entry["water"]
	water_instance.mesh = water_mesh
	var shape_node: CollisionShape3D = entry["shape"]
	if res["collision"].is_empty():
		shape_node.shape = null
	else:
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(res["collision"])
		shape.backface_collision = true
		shape_node.shape = shape
	_remesh_on_commit_neighbors(pos)


func _remesh_on_commit_neighbors(pos: Vector2i) -> void:
	var opposite_bits := [2, 1, 8, 4]
	for index in DIRS_4.size():
		var entry: Dictionary = _chunks.get(pos + DIRS_4[index], {})
		if entry.is_empty():
			continue
		if (entry["mask"] as int) & opposite_bits[index] == 0:
			_queue_rebuild(pos + DIRS_4[index])


func _queue_rebuild(pos: Vector2i) -> void:
	if _pending.has(pos) or _gen_queue.has(pos):
		return
	_dirty[pos] = true
	_gen_queue.push_front(pos)


func _unload_far() -> void:
	for pos in _chunks.keys():
		if maxi(absi(pos.x - _stream_center.x), absi(pos.y - _stream_center.y)) > unload_radius:
			_free_chunk(pos)


func _free_chunk(pos: Vector2i) -> void:
	var entry: Dictionary = _chunks.get(pos, {})
	if entry.is_empty():
		return
	for key in ["mesh", "water", "body"]:
		var node: Node = entry[key]
		if node:
			node.queue_free()
	_chunks.erase(pos)


func _arrays_to_mesh(verts: PackedVector3Array, normals: PackedVector3Array, uvs: PackedVector2Array, colors: PackedColorArray, indices: PackedInt32Array, material: Material) -> ArrayMesh:
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


func _setup_blocks() -> void:
	var texture_names: PackedStringArray = PackedStringArray()
	for def in BLOCK_DEFS:
		for index in range(2, 5):
			var name: String = def[index]
			if name != "" and not texture_names.has(name):
				texture_names.append(name)
	var rows := int(ceil(float(texture_names.size()) / float(ATLAS_COLUMNS)))
	var atlas := Image.create(ATLAS_COLUMNS * TILE_PX, rows * TILE_PX, false, Image.FORMAT_RGBA8)
	var tile_lookup := {}
	for index in texture_names.size():
		var texture := load(TEXTURE_ROOT + texture_names[index]) as Texture2D
		var image := texture.get_image()
		if image.is_compressed():
			image.decompress()
		if image.get_format() != Image.FORMAT_RGBA8:
			image.convert(Image.FORMAT_RGBA8)
		var column := index % ATLAS_COLUMNS
		var row := floori(float(index) / float(ATLAS_COLUMNS))
		var destination := Vector2i(column * TILE_PX, row * TILE_PX)
		atlas.blit_rect(image, Rect2i(0, 0, TILE_PX, TILE_PX), destination)
		if TEXTURE_TINTS.has(texture_names[index]):
			_tint_atlas_region(atlas, destination, TEXTURE_TINTS[texture_names[index]])
		tile_lookup[texture_names[index]] = index
	atlas.fix_alpha_edges()
	atlas.generate_mipmaps()
	var atlas_texture := ImageTexture.create_from_image(atlas)
	var total_tiles := texture_names.size()
	_tile_uv_origin.resize(total_tiles)
	_tile_uv_size = Vector2(
		float(TILE_PX - UV_INSET * 2.0) / float(atlas.get_width()),
		float(TILE_PX - UV_INSET * 2.0) / float(atlas.get_height())
	)
	for index in total_tiles:
		var column := index % ATLAS_COLUMNS
		var row := floori(float(index) / float(ATLAS_COLUMNS))
		_tile_uv_origin[index] = Vector2(
			(float(column * TILE_PX) + UV_INSET) / float(atlas.get_width()),
			(float(row * TILE_PX) + UV_INSET) / float(atlas.get_height())
		)
	_blocks_mat = StandardMaterial3D.new()
	_blocks_mat.albedo_texture = atlas_texture
	_blocks_mat.albedo_color = Color.WHITE
	_blocks_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_blocks_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	_blocks_mat.alpha_scissor_threshold = 0.5
	_blocks_mat.vertex_color_use_as_albedo = true
	_blocks_mat.roughness = 1.0
	_blocks_mat.metallic = 0.0
	_blocks_mat.metallic_specular = 0.05
	var max_id := BLOCK_DEFS.size()
	_block_flags.resize(max_id)
	_block_opaque.resize(max_id)
	_block_tile_top.resize(max_id)
	_block_tile_side.resize(max_id)
	_block_tile_bottom.resize(max_id)
	_block_names.resize(max_id)
	for def in BLOCK_DEFS:
		var id: int = def[0]
		_block_names[id] = def[1]
		_block_flags[id] = def[5]
		_block_opaque[id] = 1 if (int(def[5]) & FLAG_OPAQUE) != 0 else 0
		_block_tile_top[id] = tile_lookup.get(def[2], 0)
		_block_tile_side[id] = tile_lookup.get(def[3], 0)
		_block_tile_bottom[id] = tile_lookup.get(def[4], 0)
	var shader := load(WATER_SHADER_PATH) as Shader
	if shader:
		var water_shader := ShaderMaterial.new()
		water_shader.shader = shader
		water_shader.set_shader_parameter("water_texture", load(TEXTURE_ROOT + "water.png"))
		_water_mat = water_shader
	else:
		var water_fallback := StandardMaterial3D.new()
		water_fallback.albedo_color = Color("#3f8fdd")
		water_fallback.albedo_texture = load(TEXTURE_ROOT + "water.png")
		water_fallback.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		water_fallback.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
		_water_mat = water_fallback


func _tint_atlas_region(atlas: Image, origin: Vector2i, tint: Color) -> void:
	for y in TILE_PX:
		for x in TILE_PX:
			var pixel := atlas.get_pixel(origin.x + x, origin.y + y)
			atlas.set_pixel(origin.x + x, origin.y + y, Color(pixel.r * tint.r, pixel.g * tint.g, pixel.b * tint.b, pixel.a))


func _setup_face_tables() -> void:
	_face_ao_offsets = []
	for face in FACE_NORMALS.size():
		var normal: Vector3i = FACE_NORMALS[face]
		var tangent_a: Vector3i = FACE_TANGENT_A[face]
		var tangent_b: Vector3i = FACE_TANGENT_B[face]
		var axis_a := 0 if tangent_a.x != 0 else 1
		var axis_b := 0 if tangent_b.x != 0 else (1 if tangent_b.y != 0 else 2)
		var corners: Array = []
		for corner in 4:
			var offset: Vector3i = FACE_VERTS[face][corner]
			var a: Vector3i = tangent_a * (offset[axis_a] * 2 - 1)
			var b: Vector3i = tangent_b * (offset[axis_b] * 2 - 1)
			corners.append([normal + a, normal + b, normal + a + b])
		_face_ao_offsets.append(corners)


func _make_noise_set() -> Array:
	var seeds := [
		[FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.0035, 4, 11],
		[FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.0045, 3, 22],
		[FastNoiseLite.TYPE_SIMPLEX, 0.02, 2, 33],
		[FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.0022, 2, 44],
		[FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.0026, 2, 55],
		[FastNoiseLite.TYPE_CELLULAR, 0.05, 2, 66],
		[FastNoiseLite.TYPE_PERLIN, 0.028, 2, 77],
		[FastNoiseLite.TYPE_SIMPLEX, 0.018, 2, 88],
	]
	var noises: Array = []
	for entry in seeds:
		var noise := FastNoiseLite.new()
		noise.noise_type = entry[0]
		noise.frequency = entry[1]
		noise.fractal_octaves = entry[2]
		noise.seed = entry[3] + world_seed
		noises.append(noise)
	return noises


func _height_at(noises: Array, x: int, z: int) -> int:
	var continent: float = noises[0].get_noise_2d(float(x), float(z))
	var ridge_raw: float = noises[1].get_noise_2d(float(x), float(z))
	var detail: float = noises[2].get_noise_2d(float(x), float(z))
	var height := 34.0 + continent * 12.0 * terrain_scale
	var mountain := maxf(continent - 0.12, 0.0) * 2.4
	var ridge := 1.0 - absf(ridge_raw)
	height += ridge * ridge * mountain * 36.0 * maxf(terrain_scale, 0.5)
	height += detail * 2.6 * terrain_scale
	var biome := _biome_at(noises, x, z)
	if biome == BIOME_DESERT:
		height = 33.0 + (height - 34.0) * 0.35
	elif biome == BIOME_SWAMP:
		height = minf(height, float(SEA_LEVEL) + 3.0) - 1.0
	elif biome == BIOME_SNOW:
		height += mountain * 5.0
	if height > float(SEA_LEVEL) - 1.5 and height < float(SEA_LEVEL) + 1.5:
		if height < float(SEA_LEVEL):
			height = float(SEA_LEVEL) - 1.0
		else:
			height = float(SEA_LEVEL) + 1.0
	return clampi(roundi(height), 4, WORLD_HEIGHT - 24)


func _biome_at(noises: Array, x: int, z: int) -> int:
	var temperature: float = noises[3].get_noise_2d(float(x), float(z))
	var humidity: float = noises[4].get_noise_2d(float(x), float(z))
	if temperature < -0.35:
		return BIOME_SNOW
	if temperature > 0.3 and humidity < -0.1:
		return BIOME_DESERT
	if humidity > 0.4:
		return BIOME_SWAMP
	if humidity > 0.1:
		return BIOME_FOREST
	return BIOME_PLAINS


func _cave_at(noises: Array, x: int, y: int, z: int) -> bool:
	var fy := float(y) * 2.4
	var worm: float = noises[5].get_noise_3d(float(x), fy, float(z))
	var cheese: float = noises[6].get_noise_3d(float(x), fy * 0.62, float(z))
	return worm > 0.56 or cheese > 0.62


func _ore_at(x: int, y: int, z: int) -> int:
	var hashed := _hash3(x, y, z, 7)
	var roll := float(hashed % 100000) / 100000.0
	if y < 28 and roll < 0.0022:
		return BLOCK_GOLD_ORE
	if y < 48 and roll < 0.010:
		return BLOCK_IRON_ORE
	if y < 66 and roll < 0.022:
		return BLOCK_COAL_ORE
	if roll > 0.9965:
		return BLOCK_GRAVEL
	return BLOCK_STONE


func _hash3(x: int, y: int, z: int, salt: int) -> int:
	var value := x * 374761393 + y * 668265263 + z * 1442695041 + salt * 1013904223 + world_seed * 2654435761
	value = (value ^ (value >> 13)) * 1274126177
	value = value ^ (value >> 16)
	return value & 0x7FFFFFFF


func _rand01(x: int, y: int, z: int, salt: int) -> float:
	return float(_hash3(x, y, z, salt)) / 2147483647.0


func _job_generate(chunk_pos: Vector2i, edits: Dictionary, neighbors: Dictionary, slot: Dictionary = {}) -> Dictionary:
	var origin_x := chunk_pos.x * CHUNK_SIZE
	var origin_z := chunk_pos.y * CHUNK_SIZE
	var data := PackedByteArray()
	data.resize(CHUNK_AREA * WORLD_HEIGHT)
	var noises := _make_noise_set()
	var max_y := 0
	for local_z in CHUNK_SIZE:
		var world_z := origin_z + local_z
		for local_x in CHUNK_SIZE:
			var world_x := origin_x + local_x
			var biome := BIOME_PLAINS
			var height := 34
			if world_type != 1:
				biome = _biome_at(noises, world_x, world_z)
				height = _height_at(noises, world_x, world_z)
			var top := BLOCK_GRASS
			var sub := BLOCK_DIRT
			if biome == BIOME_DESERT:
				top = BLOCK_SAND
				sub = BLOCK_SAND
			elif biome == BIOME_SNOW:
				top = BLOCK_SNOW
			if biome != BIOME_SNOW and height > 74:
				top = BLOCK_SNOW
			if height < SEA_LEVEL:
				if height >= SEA_LEVEL - 3:
					top = BLOCK_SAND
				else:
					top = BLOCK_GRAVEL if _rand01(world_x, 0, world_z, 31) < 0.6 else BLOCK_CLAY
				sub = top
			elif height <= SEA_LEVEL + 1 and biome != BIOME_SNOW:
				top = BLOCK_SAND
				sub = BLOCK_SAND
			var column := local_x + local_z * DATA_STRIDE_Z
			for y in range(0, height + 1):
				var id := BLOCK_STONE
				if y == 0:
					id = BLOCK_BEDROCK
				elif y == 1 and _rand01(world_x, y, world_z, 3) < 0.45:
					id = BLOCK_BEDROCK
				elif y == height:
					id = top
				elif y >= height - 3:
					id = sub
				elif y > 3 and y < height - 1:
					if world_type != 1 and _cave_at(noises, world_x, y, world_z):
						continue
					id = _ore_at(world_x, y, world_z)
				data[column + y * DATA_STRIDE_Y] = id
			if height < SEA_LEVEL:
				for y in range(height + 1, SEA_LEVEL + 1):
					data[column + y * DATA_STRIDE_Y] = BLOCK_WATER
				max_y = maxi(max_y, SEA_LEVEL)
			else:
				max_y = maxi(max_y, height)
	max_y = _stamp_trees(noises, chunk_pos, data, max_y)
	for key in edits.keys():
		var block_position: Vector3i = key
		var local_x := block_position.x - origin_x
		var local_z := block_position.z - origin_z
		if local_x < 0 or local_x >= CHUNK_SIZE or local_z < 0 or local_z >= CHUNK_SIZE:
			continue
		if block_position.y < 0 or block_position.y >= WORLD_HEIGHT:
			continue
		var id: int = edits[key]
		data[local_x + local_z * DATA_STRIDE_Z + block_position.y * DATA_STRIDE_Y] = id
		if id != BLOCK_AIR:
			max_y = maxi(max_y, block_position.y)
	var result := _build_mesh_data(chunk_pos, data, max_y, neighbors)
	slot["result"] = result
	return result


func _stamp_trees(noises: Array, chunk_pos: Vector2i, data: PackedByteArray, max_y: int) -> int:
	if world_type == 1 or tree_density <= 0.0:
		return max_y
	var origin_x := chunk_pos.x * CHUNK_SIZE
	var origin_z := chunk_pos.y * CHUNK_SIZE
	for local_z in range(-2, CHUNK_SIZE + 2):
		var world_z := origin_z + local_z
		for local_x in range(-2, CHUNK_SIZE + 2):
			var world_x := origin_x + local_x
			var biome := _biome_at(noises, world_x, world_z)
			var density := 0.0
			match biome:
				BIOME_FOREST:
					density = 0.06
				BIOME_PLAINS:
					density = 0.012
				BIOME_SNOW:
					density = 0.05
				BIOME_SWAMP:
					density = 0.035
				BIOME_DESERT:
					density = 0.018
			density *= tree_density
			if density <= 0.0:
				continue
			if _rand01(world_x, 0, world_z, 101) > density:
				continue
			var height := _height_at(noises, world_x, world_z)
			if height <= SEA_LEVEL + 1 or height > 72:
				continue
			if _rand01(world_x, 1, world_z, 55) > 0.7:
				continue
			match biome:
				BIOME_DESERT:
					max_y = _stamp_cactus(local_x, height, local_z, world_x, world_z, data, max_y)
				BIOME_SNOW:
					max_y = _stamp_spruce(local_x, height, local_z, world_x, world_z, data, max_y)
				BIOME_FOREST:
					if _rand01(world_x, 2, world_z, 88) < 0.3:
						max_y = _stamp_birch(local_x, height, local_z, world_x, world_z, data, max_y)
					else:
						max_y = _stamp_oak(local_x, height, local_z, world_x, world_z, data, max_y)
				_:
					max_y = _stamp_oak(local_x, height, local_z, world_x, world_z, data, max_y)
	return max_y


func _stamp(data: PackedByteArray, local_x: int, y: int, local_z: int, id: int) -> void:
	if local_x < 0 or local_x >= CHUNK_SIZE or local_z < 0 or local_z >= CHUNK_SIZE:
		return
	if y < 0 or y >= WORLD_HEIGHT:
		return
	data[local_x + local_z * DATA_STRIDE_Z + y * DATA_STRIDE_Y] = id


func _stamp_oak(local_x: int, ground_y: int, local_z: int, world_x: int, world_z: int, data: PackedByteArray, max_y: int) -> int:
	var trunk := 4 + int(_rand01(world_x, 2, world_z, 77) * 3.0)
	var top_y := ground_y + trunk
	for offset in range(1, trunk + 1):
		_stamp(data, local_x, ground_y + offset, local_z, BLOCK_LOG)
	for layer in range(-2, 2):
		var y := top_y + layer
		var radius := 2 if layer < 0 else 1
		for dx in range(-radius, radius + 1):
			for dz in range(-radius, radius + 1):
				if dx == 0 and dz == 0 and layer < 1:
					continue
				if absi(dx) == radius and absi(dz) == radius:
					if layer >= 0 or _rand01(world_x + dx, y, world_z + dz, 41) < 0.5:
						continue
				_stamp(data, local_x + dx, y, local_z + dz, BLOCK_LEAVES)
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			if absi(dx) + absi(dz) <= 1:
				_stamp(data, local_x + dx, top_y + 2, local_z + dz, BLOCK_LEAVES)
	return maxi(max_y, top_y + 2)


func _stamp_birch(local_x: int, ground_y: int, local_z: int, world_x: int, world_z: int, data: PackedByteArray, max_y: int) -> int:
	var trunk := 5 + int(_rand01(world_x, 3, world_z, 79) * 3.0)
	var top_y := ground_y + trunk
	for offset in range(1, trunk + 1):
		_stamp(data, local_x, ground_y + offset, local_z, BLOCK_BIRCH_LOG)
	for layer in range(-2, 2):
		var y := top_y + layer
		var radius := 1 if layer > -2 else 2
		for dx in range(-radius, radius + 1):
			for dz in range(-radius, radius + 1):
				if dx == 0 and dz == 0 and layer < 1:
					continue
				if absi(dx) + absi(dz) > radius + 1:
					continue
				_stamp(data, local_x + dx, y, local_z + dz, BLOCK_BIRCH_LEAVES)
	_stamp(data, local_x, top_y + 1, local_z, BLOCK_BIRCH_LEAVES)
	return maxi(max_y, top_y + 1)


func _stamp_spruce(local_x: int, ground_y: int, local_z: int, world_x: int, world_z: int, data: PackedByteArray, max_y: int) -> int:
	var trunk := 6 + int(_rand01(world_x, 4, world_z, 91) * 4.0)
	for offset in range(1, trunk + 1):
		_stamp(data, local_x, ground_y + offset, local_z, BLOCK_SPRUCE_LOG)
	for offset in range(2, trunk + 1):
		var y := ground_y + offset
		var taper := float(trunk - offset) / float(trunk)
		var radius := 0
		if taper > 0.55:
			radius = 2
		elif taper > 0.2:
			radius = 1
		for dx in range(-radius, radius + 1):
			for dz in range(-radius, radius + 1):
				if dx == 0 and dz == 0:
					continue
				if absi(dx) + absi(dz) > radius + 1:
					continue
				if radius == 2 and absi(dx) == 2 and absi(dz) == 2:
					continue
				_stamp(data, local_x + dx, y, local_z + dz, BLOCK_SPRUCE_LEAVES)
	_stamp(data, local_x, ground_y + trunk + 1, local_z, BLOCK_SPRUCE_LEAVES)
	return maxi(max_y, ground_y + trunk + 1)


func _stamp_cactus(local_x: int, ground_y: int, local_z: int, world_x: int, world_z: int, data: PackedByteArray, max_y: int) -> int:
	if local_x >= 0 and local_x < CHUNK_SIZE and local_z >= 0 and local_z < CHUNK_SIZE:
		if data[local_x + local_z * DATA_STRIDE_Z + ground_y * DATA_STRIDE_Y] != BLOCK_SAND:
			return max_y
	var height := 1 + int(_rand01(world_x, 5, world_z, 13) * 3.0)
	for offset in range(1, height + 1):
		_stamp(data, local_x, ground_y + offset, local_z, BLOCK_CACTUS)
	return maxi(max_y, ground_y + height)


func _build_mesh_data(chunk_pos: Vector2i, data: PackedByteArray, max_y: int, neighbors: Dictionary) -> Dictionary:
	max_y = clampi(max_y + 1, 1, WORLD_HEIGHT - 2)
	var pad_height := max_y + 3
	var padded := PackedByteArray()
	padded.resize(PAD_W * PAD_W * pad_height)
	for pad_y in range(0, pad_height):
		var y := pad_y - 1
		for pad_z in range(0, PAD_W):
			var local_z := pad_z - 1
			for pad_x in range(0, PAD_W):
				var local_x := pad_x - 1
				var id := 0
				if local_x >= 0 and local_x < CHUNK_SIZE and local_z >= 0 and local_z < CHUNK_SIZE:
					if y >= 0 and y < WORLD_HEIGHT:
						id = data[local_x + local_z * DATA_STRIDE_Z + y * DATA_STRIDE_Y]
				else:
					var dx := 0
					var dz := 0
					if pad_x == 0:
						dx = -1
					elif pad_x == PAD_W - 1:
						dx = 1
					if pad_z == 0:
						dz = -1
					elif pad_z == PAD_W - 1:
						dz = 1
					var neighbor: Dictionary = neighbors.get(Vector2i(dx, dz), {})
					if not neighbor.is_empty() and y >= 0 and y <= int(neighbor["max_y"]):
						var neighbor_data: PackedByteArray = neighbor["data"]
						var neighbor_x := local_x - dx * CHUNK_SIZE
						var neighbor_z := local_z - dz * CHUNK_SIZE
						id = neighbor_data[neighbor_x + neighbor_z * DATA_STRIDE_Z + y * DATA_STRIDE_Y]
				padded[pad_x + pad_z * PAD_STRIDE_Z + pad_y * PAD_STRIDE_Y] = id
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
	for y in range(0, max_y + 1):
		for local_z in CHUNK_SIZE:
			for local_x in CHUNK_SIZE:
				var pad_index := (local_x + 1) + (local_z + 1) * PAD_STRIDE_Z + (y + 1) * PAD_STRIDE_Y
				var id := padded[pad_index]
				if id == BLOCK_AIR:
					continue
				if id == BLOCK_WATER:
					_append_water_block(padded, pad_index, local_x, y, local_z, water_verts, water_normals, water_uvs, water_colors, water_indices)
					continue
				var is_opaque: bool = _block_opaque[id] == 1
				for face in 6:
					var normal: Vector3i = FACE_NORMALS[face]
					var neighbor_index := pad_index + normal.x + normal.z * PAD_STRIDE_Z + normal.y * PAD_STRIDE_Y
					var neighbor_id := padded[neighbor_index]
					if is_opaque:
						if _block_opaque[neighbor_id] == 1:
							continue
					else:
						if _block_opaque[neighbor_id] == 1:
							continue
						if neighbor_id == id and (_block_flags[id] & FLAG_LEAVES) == 0:
							continue
					_append_face(face, pad_index, local_x, y, local_z, id, padded, verts, normals, uvs, colors, indices, collision)
	var result := {
		"data": data,
		"max_y": max_y,
		"verts": verts,
		"normals": normals,
		"uvs": uvs,
		"colors": colors,
		"indices": indices,
		"collision": collision,
		"wverts": water_verts,
		"wnormals": water_normals,
		"wuvs": water_uvs,
		"wcolors": water_colors,
		"windices": water_indices,
		"mask": int(neighbors.get("mask", 0)),
	}
	return result


func _append_face(face: int, pad_index: int, local_x: int, y: int, local_z: int, block_id: int, padded: PackedByteArray, verts: PackedVector3Array, normals: PackedVector3Array, uvs: PackedVector2Array, colors: PackedColorArray, indices: PackedInt32Array, collision: PackedVector3Array) -> void:
	var normal: Vector3i = FACE_NORMALS[face]
	var shade: float = FACE_SHADE[face]
	var tile: int = _block_tile_side[block_id]
	if face == 0:
		tile = _block_tile_top[block_id]
	elif face == 1:
		tile = _block_tile_bottom[block_id]
	var uv_origin: Vector2 = _tile_uv_origin[tile]
	var base := verts.size()
	var face_verts: Array = FACE_VERTS[face]
	var face_uvs: Array = FACE_UVS[face]
	for corner in 4:
		var offset: Vector3i = face_verts[corner]
		var position := Vector3(local_x + offset.x, y + offset.y, local_z + offset.z)
		verts.append(position)
		normals.append(Vector3(normal))
		var uv: Vector2 = face_uvs[corner]
		uvs.append(uv_origin + Vector2(uv.x * _tile_uv_size.x, uv.y * _tile_uv_size.y))
		var ao := 1.0
		var samples: Array = _face_ao_offsets[face][corner]
		var occlusion := 0
		for sample in samples:
			var sample_offset: Vector3i = sample
			var sample_index := pad_index + sample_offset.x + sample_offset.z * PAD_STRIDE_Z + sample_offset.y * PAD_STRIDE_Y
			if _block_opaque[padded[sample_index]] == 1:
				occlusion += 1
		ao = AO_LEVELS[3 - occlusion]
		var light := shade * ao
		colors.append(Color(light, light, light, 1.0))
	var p0: Vector3 = verts[base]
	var p1: Vector3 = verts[base + 1]
	var p2: Vector3 = verts[base + 2]
	var p3: Vector3 = verts[base + 3]
	indices.append_array(PackedInt32Array([base, base + 2, base + 1, base, base + 3, base + 2]))
	collision.append_array(PackedVector3Array([p0, p2, p1, p0, p3, p2]))


func _append_water_block(padded: PackedByteArray, pad_index: int, local_x: int, y: int, local_z: int, water_verts: PackedVector3Array, water_normals: PackedVector3Array, water_uvs: PackedVector2Array, water_colors: PackedColorArray, water_indices: PackedInt32Array) -> void:
	var above := padded[pad_index + PAD_STRIDE_Y]
	var top := 0.9 if above != BLOCK_WATER else 1.0
	if above != BLOCK_WATER and _block_opaque[above] == 0:
		_append_water_face(0, local_x, y, local_z, top, water_verts, water_normals, water_uvs, water_colors, water_indices)
	for face in range(2, 6):
		var normal: Vector3i = FACE_NORMALS[face]
		var neighbor_index := pad_index + normal.x + normal.z * PAD_STRIDE_Z + normal.y * PAD_STRIDE_Y
		var neighbor := padded[neighbor_index]
		if neighbor == BLOCK_WATER or _block_opaque[neighbor] == 1:
			continue
		_append_water_face(face, local_x, y, local_z, top, water_verts, water_normals, water_uvs, water_colors, water_indices)


func _append_water_face(face: int, local_x: int, y: int, local_z: int, top: float, verts: PackedVector3Array, normals: PackedVector3Array, uvs: PackedVector2Array, colors: PackedColorArray, indices: PackedInt32Array) -> void:
	var normal: Vector3i = FACE_NORMALS[face]
	var base := verts.size()
	var face_verts: Array = FACE_VERTS[face]
	var shade := 1.0 if face == 0 else 0.92
	for corner in 4:
		var offset: Vector3i = face_verts[corner]
		verts.append(Vector3(local_x + offset.x, y + (top if offset.y == 1 else 0.0), local_z + offset.z))
		normals.append(Vector3(normal))
		uvs.append(Vector2(local_x + offset.x, local_z + offset.z))
		colors.append(Color(shade, shade, shade, 1.0))
	indices.append_array(PackedInt32Array([base, base + 2, base + 1, base, base + 3, base + 2]))


func _chunk_for_position(world_position: Vector3) -> Vector2i:
	return Vector2i(
		floori(world_position.x / float(CHUNK_SIZE)),
		floori(world_position.z / float(CHUNK_SIZE))
	)


func get_spawn_position() -> Vector3:
	for radius in range(0, 64):
		for dx in range(-radius, radius + 1):
			for dz in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dz)) != radius:
					continue
				var biome := _biome_at(_noise, dx, dz)
				if biome == BIOME_SWAMP:
					continue
				var height := _height_at(_noise, dx, dz)
				if height > SEA_LEVEL + 1:
					return Vector3(float(dx) + 0.5, float(height) + 2.5, float(dz) + 0.5)
	return Vector3(0.5, SEA_LEVEL + 12.0, 0.5)


func get_block_world(block_position: Vector3i) -> int:
	if block_position.y < 0 or block_position.y >= WORLD_HEIGHT:
		return BLOCK_AIR
	var chunk_position := Vector2i(floori(float(block_position.x) / float(CHUNK_SIZE)), floori(float(block_position.z) / float(CHUNK_SIZE)))
	var entry: Dictionary = _chunks.get(chunk_position, {})
	if entry.is_empty():
		return BLOCK_AIR
	var local_x := block_position.x - chunk_position.x * CHUNK_SIZE
	var local_z := block_position.z - chunk_position.y * CHUNK_SIZE
	return (entry["data"] as PackedByteArray)[local_x + local_z * DATA_STRIDE_Z + block_position.y * DATA_STRIDE_Y]


func is_water_at(world_position: Vector3) -> bool:
	return get_block_world(Vector3i(floori(world_position.x), floori(world_position.y), floori(world_position.z))) == BLOCK_WATER


func break_block(block_position: Vector3i) -> int:
	if block_position.y <= 0:
		return BLOCK_AIR
	var chunk_position := Vector2i(floori(float(block_position.x) / float(CHUNK_SIZE)), floori(float(block_position.z) / float(CHUNK_SIZE)))
	var entry: Dictionary = _chunks.get(chunk_position, {})
	if entry.is_empty():
		return BLOCK_AIR
	var local_x := block_position.x - chunk_position.x * CHUNK_SIZE
	var local_z := block_position.z - chunk_position.y * CHUNK_SIZE
	var index := local_x + local_z * DATA_STRIDE_Z + block_position.y * DATA_STRIDE_Y
	var block_id: int = entry["data"][index]
	if block_id == BLOCK_AIR or block_id == BLOCK_WATER:
		return BLOCK_AIR
	if (_block_flags[block_id] & FLAG_UNBREAKABLE) != 0:
		return BLOCK_AIR
	entry["data"][index] = BLOCK_AIR
	_edited_blocks[block_position] = BLOCK_AIR
	_touch_chunk(chunk_position, local_x, local_z)
	return block_id


func place_block(block_position: Vector3i, block_id: int) -> bool:
	if block_id <= BLOCK_AIR or block_id >= _block_names.size():
		return false
	if block_position.y < 0 or block_position.y >= WORLD_HEIGHT:
		return false
	var chunk_position := Vector2i(floori(float(block_position.x) / float(CHUNK_SIZE)), floori(float(block_position.z) / float(CHUNK_SIZE)))
	var entry: Dictionary = _chunks.get(chunk_position, {})
	if entry.is_empty():
		return false
	var local_x := block_position.x - chunk_position.x * CHUNK_SIZE
	var local_z := block_position.z - chunk_position.y * CHUNK_SIZE
	var index := local_x + local_z * DATA_STRIDE_Z + block_position.y * DATA_STRIDE_Y
	if entry["data"][index] != BLOCK_AIR:
		return false
	entry["data"][index] = block_id
	_edited_blocks[block_position] = block_id
	_touch_chunk(chunk_position, local_x, local_z)
	return true


func _touch_chunk(chunk_position: Vector2i, local_x: int, local_z: int) -> void:
	_chunk_edit_version[chunk_position] = _chunk_edit_version.get(chunk_position, 0) + 1
	_queue_rebuild(chunk_position)
	if local_x == 0:
		_queue_rebuild(chunk_position + Vector2i(-1, 0))
	elif local_x == CHUNK_SIZE - 1:
		_queue_rebuild(chunk_position + Vector2i(1, 0))
	if local_z == 0:
		_queue_rebuild(chunk_position + Vector2i(0, -1))
	elif local_z == CHUNK_SIZE - 1:
		_queue_rebuild(chunk_position + Vector2i(0, 1))


func get_blocks_material() -> Material:
	return _blocks_mat


func make_block_mesh(block_id: int) -> ArrayMesh:
	if block_id <= BLOCK_AIR or block_id >= _block_names.size():
		block_id = BLOCK_GRASS
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	for face in 6:
		var normal: Vector3i = FACE_NORMALS[face]
		var tile: int = _block_tile_side[block_id]
		if face == 0:
			tile = _block_tile_top[block_id]
		elif face == 1:
			tile = _block_tile_bottom[block_id]
		var uv_origin: Vector2 = _tile_uv_origin[tile]
		var base := verts.size()
		var face_verts: Array = FACE_VERTS[face]
		var face_uvs: Array = FACE_UVS[face]
		var shade: float = FACE_SHADE[face]
		for corner in 4:
			var offset: Vector3i = face_verts[corner]
			verts.append(Vector3(offset.x, offset.y, offset.z) - Vector3(0.5, 0.5, 0.5))
			normals.append(Vector3(normal))
			var uv: Vector2 = face_uvs[corner]
			uvs.append(uv_origin + Vector2(uv.x * _tile_uv_size.x, uv.y * _tile_uv_size.y))
			colors.append(Color(shade, shade, shade, 1.0))
		indices.append_array(PackedInt32Array([base, base + 2, base + 1, base, base + 3, base + 2]))
	return _arrays_to_mesh(verts, normals, uvs, colors, indices, _blocks_mat)


func get_block_name(block_id: int) -> String:
	if block_id <= BLOCK_AIR or block_id >= _block_names.size():
		return "AIR"
	return _block_names[block_id]


func get_biome_name(world_position: Vector3) -> String:
	match _biome_at(_noise, floori(world_position.x), floori(world_position.z)):
		BIOME_FOREST:
			return "FOREST"
		BIOME_DESERT:
			return "DESERT"
		BIOME_SNOW:
			return "SNOWY TUNDRA"
		BIOME_SWAMP:
			return "SWAMP"
	return "PLAINS"


func get_loaded_chunk_count() -> int:
	return _chunks.size()
