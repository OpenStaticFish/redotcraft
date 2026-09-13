class_name BlockIcon
extends RefCounted

## Renders live block textures from the BlockRegistry's Texture2DArray into
## crisp isometric cube icons (top + two shaded sides) for the hotbar and
## inventory. Cross blocks (torches, plants) draw flat with their alpha.


const TOP_SHADE := 1.0
const LEFT_SHADE := 0.78
const RIGHT_SHADE := 0.56

static var _cache: Dictionary = {}


static func make_icon(registry: BlockRegistry, block_id: int, size: int = 48) -> Texture2D:
	if registry == null or not registry.is_valid_id(block_id):
		return null
	var key := "%d@%d" % [block_id, size]
	if _cache.has(key):
		return _cache[key]
	var texture: Texture2D = null
	if registry.has_flag(block_id, BlockRegistry.FLAG_CROSS):
		texture = _flat_icon(registry, block_id, size)
	else:
		texture = _cube_icon(registry, block_id, size)
	_cache[key] = texture
	return texture


static func _layer_image(registry: BlockRegistry, layer: int) -> Image:
	if layer < 0 or layer >= registry.texture_array.get_layers():
		return null
	var image := registry.texture_array.get_layer_data(layer)
	if image == null:
		return null
	if image.is_compressed():
		image.decompress()
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	return image


static func _flat_icon(registry: BlockRegistry, block_id: int, size: int) -> Texture2D:
	var source := _layer_image(registry, registry.layer_for(block_id, 2))
	if source == null:
		return null
	var margin := maxi(2, size / 8)
	var inner := size - margin * 2
	var image := source.duplicate()
	image.resize(inner, inner, Image.INTERPOLATE_NEAREST)
	var canvas := Image.create(size, size, false, Image.FORMAT_RGBA8)
	canvas.blend_rect(image, Rect2i(Vector2i.ZERO, Vector2i(inner, inner)), Vector2i(margin, margin))
	return ImageTexture.create_from_image(canvas)


static func _cube_icon(registry: BlockRegistry, block_id: int, size: int) -> Texture2D:
	var top := _layer_image(registry, registry.layer_for(block_id, 0))
	var side := _layer_image(registry, registry.layer_for(block_id, 2))
	if top == null or side == null:
		return null

	var canvas := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var pad := maxi(2, size / 14)
	var span := float(size - pad * 2)
	var center := float(size) * 0.5
	var quarter := span * 0.25

	for y in size:
		for x in size:
			var fx := float(x)
			var fy := float(y)
			var color := Color(0, 0, 0, 0)
			var dx := absf(fx - center) / (span * 0.5)
			var in_top := fx >= pad and fx <= float(size) - pad \
					and fy >= pad + dx * quarter and fy <= pad + span * 0.5 - dx * quarter
			if in_top:
				# Top diamond.
				var u := ((fx - center) / (span * 0.5) + (fy - pad) / quarter) * 0.5
				var v := ((fy - pad) / quarter - (fx - center) / (span * 0.5)) * 0.5
				color = _sample(top, u, v, TOP_SHADE)
			elif fx >= pad and fx < center:
				# Left face.
				var rel := (fx - pad) / span
				var top_edge := pad + span * 0.5 - (1.0 - 2.0 * rel) * quarter
				var bottom_edge := pad + span * 0.75 + rel * span * 0.5
				if fy >= top_edge and fy <= bottom_edge:
					color = _sample(side, rel * 2.0, (fy - top_edge) / (span * 0.5), LEFT_SHADE)
			elif fx > center and fx <= float(size) - pad:
				# Right face.
				var rel := ((fx - pad) / span - 0.5) * 2.0
				var top_edge := pad + span * 0.5 - rel * quarter
				var bottom_edge := pad + span - rel * quarter
				if fy >= top_edge and fy <= bottom_edge:
					color = _sample(side, rel, (fy - top_edge) / (span * 0.5), RIGHT_SHADE)
			canvas.set_pixel(x, y, color)
	return ImageTexture.create_from_image(canvas)


static func _sample(source: Image, u: float, v: float, shade: float) -> Color:
	var x := clampi(int(clampf(u, 0.0, 1.0) * float(source.get_width() - 1)), 0, source.get_width() - 1)
	var y := clampi(int(clampf(v, 0.0, 1.0) * float(source.get_height() - 1)), 0, source.get_height() - 1)
	var color := source.get_pixel(x, y)
	color = Color(color.r * shade, color.g * shade, color.b * shade, color.a)
	return color
