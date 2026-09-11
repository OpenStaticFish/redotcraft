class_name BlockRegistry
extends RefCounted

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

const TEXTURE_ROOT := "res://assets/placeholders/zigcraft/default/"
const WATER_TEXTURE_PATH := TEXTURE_ROOT + "water.png"
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

var material: StandardMaterial3D
var water_material: Material
var tile_uv_size := Vector2.ZERO

var _flags: PackedByteArray = PackedByteArray()
var _opaque: PackedByteArray = PackedByteArray()
var _tile_top: PackedInt32Array = PackedInt32Array()
var _tile_side: PackedInt32Array = PackedInt32Array()
var _tile_bottom: PackedInt32Array = PackedInt32Array()
var _names: PackedStringArray = PackedStringArray()
var _tile_uv_origin: PackedVector2Array = PackedVector2Array()


func _init() -> void:
	var tile_lookup := _build_atlas()
	_build_block_tables(tile_lookup)
	_load_water_material()


func is_valid_id(block_id: int) -> bool:
	return block_id > BLOCK_AIR and block_id < _names.size()


func get_block_name(block_id: int) -> String:
	if not is_valid_id(block_id):
		return "AIR"
	return _names[block_id]


func is_opaque(block_id: int) -> bool:
	return block_id >= 0 and block_id < _opaque.size() and _opaque[block_id] == 1


func has_flag(block_id: int, flag: int) -> bool:
	return block_id >= 0 and block_id < _flags.size() and (_flags[block_id] & flag) != 0


func is_breakable(block_id: int) -> bool:
	if not is_valid_id(block_id):
		return false
	if block_id == BLOCK_WATER:
		return false
	return not has_flag(block_id, FLAG_UNBREAKABLE)


func tile_for(block_id: int, face: int) -> int:
	if face == 0:
		return _tile_top[block_id]
	if face == 1:
		return _tile_bottom[block_id]
	return _tile_side[block_id]


func tile_uv_origin(tile: int) -> Vector2:
	return _tile_uv_origin[tile]


func _build_atlas() -> Dictionary:
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
		var texture_name := texture_names[index]
		var image := _load_image(TEXTURE_ROOT + texture_name)
		var column := index % ATLAS_COLUMNS
		var row := floori(float(index) / float(ATLAS_COLUMNS))
		var destination := Vector2i(column * TILE_PX, row * TILE_PX)
		atlas.blit_rect(image, Rect2i(0, 0, TILE_PX, TILE_PX), destination)
		if TEXTURE_TINTS.has(texture_name):
			_tint_atlas_region(atlas, destination, TEXTURE_TINTS[texture_name])
		tile_lookup[texture_name] = index
	atlas.fix_alpha_edges()
	atlas.generate_mipmaps()
	var atlas_texture := ImageTexture.create_from_image(atlas)
	var total_tiles := texture_names.size()
	_tile_uv_origin.resize(total_tiles)
	tile_uv_size = Vector2(
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
	material = StandardMaterial3D.new()
	material.albedo_texture = atlas_texture
	material.albedo_color = Color.WHITE
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	material.alpha_scissor_threshold = 0.5
	material.vertex_color_use_as_albedo = true
	material.roughness = 1.0
	material.metallic = 0.0
	material.metallic_specular = 0.05
	return tile_lookup


func _load_image(path: String) -> Image:
	var texture := load(path) as Texture2D
	if texture == null:
		push_warning("Block texture missing, using placeholder: %s" % path)
		var fallback := Image.create(TILE_PX, TILE_PX, false, Image.FORMAT_RGBA8)
		fallback.fill(Color.MAGENTA)
		return fallback
	var image := texture.get_image()
	if image.is_compressed():
		image.decompress()
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	return image


func _tint_atlas_region(atlas: Image, origin: Vector2i, tint: Color) -> void:
	for y in TILE_PX:
		for x in TILE_PX:
			var pixel := atlas.get_pixel(origin.x + x, origin.y + y)
			atlas.set_pixel(origin.x + x, origin.y + y, Color(pixel.r * tint.r, pixel.g * tint.g, pixel.b * tint.b, pixel.a))


func _build_block_tables(tile_lookup: Dictionary) -> void:
	var max_id := BLOCK_DEFS.size()
	_flags.resize(max_id)
	_opaque.resize(max_id)
	_tile_top.resize(max_id)
	_tile_side.resize(max_id)
	_tile_bottom.resize(max_id)
	_names.resize(max_id)
	for def in BLOCK_DEFS:
		var id: int = def[0]
		_names[id] = def[1]
		_flags[id] = def[5]
		_opaque[id] = 1 if (int(def[5]) & FLAG_OPAQUE) != 0 else 0
		_tile_top[id] = tile_lookup.get(def[2], 0)
		_tile_side[id] = tile_lookup.get(def[3], 0)
		_tile_bottom[id] = tile_lookup.get(def[4], 0)


func _load_water_material() -> void:
	var shader := load(WATER_SHADER_PATH) as Shader
	var texture := load(WATER_TEXTURE_PATH) as Texture2D
	if shader:
		var shader_material := ShaderMaterial.new()
		shader_material.shader = shader
		if texture:
			shader_material.set_shader_parameter("water_texture", texture)
		water_material = shader_material
		return
	var fallback := StandardMaterial3D.new()
	fallback.albedo_color = Color("#3f8fdd")
	if texture:
		fallback.albedo_texture = texture
	fallback.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fallback.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	water_material = fallback
