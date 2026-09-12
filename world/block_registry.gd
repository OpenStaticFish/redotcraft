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
const BLOCK_TORCH := 27

const FLAG_OPAQUE := 1
const FLAG_CUTOUT := 2
const FLAG_UNBREAKABLE := 4
const FLAG_LEAVES := 8
const FLAG_EMISSIVE := 16
const FLAG_CROSS := 32

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
	[9, "GLOWSTONE", "glowstone.png", "glowstone.png", "glowstone.png", FLAG_OPAQUE | FLAG_EMISSIVE],
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
	[27, "TORCH", "torch.png", "torch.png", "torch.png", FLAG_CUTOUT | FLAG_CROSS | FLAG_EMISSIVE],
]

const TEXTURE_ROOT := "res://assets/placeholders/zigcraft/default/"
const WATER_TEXTURE_PATH := TEXTURE_ROOT + "water.png"
const WATER_SHADER_PATH := "res://assets/placeholders/zigcraft/water.gdshader"
const BLOCK_SHADER_PATH := "res://world/block.gdshader"
const TILE_PX := 64
const MAX_LIGHT_LEVEL := 15
const EMISSIVE_COLORS := {
	BLOCK_GLOWSTONE: Color(1.0, 0.78, 0.52),
	BLOCK_TORCH: Color(0.93, 0.68, 0.44),
}
const ATTENUATION_LEAVES := 3
const ATTENUATION_WATER := 2
const TEXTURE_TINTS := {
	"grass_top.png": Color(0.44, 0.84, 0.34),
	"leaves.png": Color(0.62, 1.15, 0.5),
	"spruce_leaves.png": Color(0.5, 1.05, 0.6),
	"birch_leaves.png": Color(0.78, 1.3, 0.55),
	"mycelium_top.png": Color(0.82, 0.68, 0.9),
	"sand.png": Color(0.98, 0.9, 0.64),
	"red_sand.png": Color(1.0, 0.84, 0.72),
}

var material: Material
var water_material: Material
var texture_array: Texture2DArray

var _flags: PackedByteArray = PackedByteArray()
var _opaque: PackedByteArray = PackedByteArray()
var _layer_top: PackedInt32Array = PackedInt32Array()
var _layer_side: PackedInt32Array = PackedInt32Array()
var _layer_bottom: PackedInt32Array = PackedInt32Array()
var _names: PackedStringArray = PackedStringArray()


func _init() -> void:
	var tile_lookup := _build_texture_array()
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


func light_attenuation(block_id: int) -> int:
	if is_opaque(block_id):
		return MAX_LIGHT_LEVEL
	if block_id == BLOCK_WATER:
		return ATTENUATION_WATER
	if has_flag(block_id, FLAG_LEAVES):
		return ATTENUATION_LEAVES
	return 0


func emission_color(block_id: int) -> Color:
	return EMISSIVE_COLORS.get(block_id, Color.BLACK)


func is_emissive(block_id: int) -> bool:
	return (has_flag(block_id, FLAG_EMISSIVE) or EMISSIVE_COLORS.has(block_id)) and is_valid_id(block_id)


func layer_for(block_id: int, face: int) -> int:
	if face == 0:
		return _layer_top[block_id]
	if face == 1:
		return _layer_bottom[block_id]
	return _layer_side[block_id]


func _build_texture_array() -> Dictionary:
	var texture_names: PackedStringArray = PackedStringArray()
	for def in BLOCK_DEFS:
		for index in range(2, 5):
			var name: String = def[index]
			if name != "" and not texture_names.has(name):
				texture_names.append(name)
	var images: Array[Image] = []
	var tile_lookup := {}
	for index in texture_names.size():
		var texture_name := texture_names[index]
		var image := _load_image(TEXTURE_ROOT + texture_name)
		if image.get_width() != TILE_PX or image.get_height() != TILE_PX:
			image.resize(TILE_PX, TILE_PX, Image.INTERPOLATE_NEAREST)
		if TEXTURE_TINTS.has(texture_name):
			_tint_image(image, TEXTURE_TINTS[texture_name])
		image.fix_alpha_edges()
		image.generate_mipmaps()
		images.append(image)
		tile_lookup[texture_name] = index
	texture_array = Texture2DArray.new()
	texture_array.create_from_images(images)
	_build_material(texture_array, images[0] if not images.is_empty() else null)
	return tile_lookup


func _build_material(array_texture: Texture2DArray, fallback_image: Image) -> void:
	var shader := load(BLOCK_SHADER_PATH) as Shader
	if shader:
		var shader_material := ShaderMaterial.new()
		shader_material.shader = shader
		shader_material.set_shader_parameter("albedo_texture", array_texture)
		material = shader_material
		return
	var fallback_texture: Texture2D = null
	if fallback_image != null:
		fallback_texture = ImageTexture.create_from_image(fallback_image)
	material = StandardMaterial3D.new()
	material.albedo_texture = fallback_texture
	material.albedo_color = Color.WHITE
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	material.alpha_scissor_threshold = 0.5
	material.vertex_color_use_as_albedo = true
	material.roughness = 1.0
	material.metallic = 0.0
	material.metallic_specular = 0.05


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


func _tint_image(image: Image, tint: Color) -> void:
	for y in image.get_height():
		for x in image.get_width():
			var pixel := image.get_pixel(x, y)
			image.set_pixel(x, y, Color(pixel.r * tint.r, pixel.g * tint.g, pixel.b * tint.b, pixel.a))


func _build_block_tables(tile_lookup: Dictionary) -> void:
	var max_id := BLOCK_DEFS.size()
	_flags.resize(max_id)
	_opaque.resize(max_id)
	_layer_top.resize(max_id)
	_layer_side.resize(max_id)
	_layer_bottom.resize(max_id)
	_names.resize(max_id)
	for def in BLOCK_DEFS:
		var id: int = def[0]
		_names[id] = def[1]
		_flags[id] = def[5]
		_opaque[id] = 1 if (int(def[5]) & FLAG_OPAQUE) != 0 else 0
		_layer_top[id] = tile_lookup.get(def[2], 0)
		_layer_side[id] = tile_lookup.get(def[3], 0)
		_layer_bottom[id] = tile_lookup.get(def[4], 0)


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
