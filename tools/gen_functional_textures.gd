extends SceneTree

const OUTPUT := "res://assets/placeholders/functional"
const SIZE := 64
const WOOD := Color("b98c54")
const WOOD_LIGHT := Color("cca466")
const WOOD_DARK := Color("715033")
const WOOD_DEEP := Color("513722")
const IRON := Color("b8c1c4")
const IRON_DARK := Color("3a4146")
const STONE := Color("777a7c")
const STONE_DARK := Color("373b3d")


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	_write("crafting_top.png", _crafting_top())
	_write("crafting_side.png", _crafting_side())
	_write("crafting_bottom.png", _planks(WOOD.darkened(0.16)))
	_write("chest_top.png", _chest_top())
	_write("chest_side.png", _chest_side())
	_write("chest_bottom.png", _planks(Color("8b673c")))
	_write("furnace_top.png", _stone(false))
	_write("furnace_side.png", _furnace_side())
	_write("furnace_bottom.png", _stone(true))
	_write("door_lower.png", _door(false))
	_write("door_upper.png", _door(true))
	_write("ladder.png", _ladder())
	_write("sign.png", _sign())
	_write("bed_top.png", _bed_top())
	_write("bed_side.png", _bed_side())
	_write("bed_bottom.png", _planks(WOOD.darkened(0.22)))
	print("Generated functional block textures in %s" % OUTPUT)
	quit()


func _image(color: Color) -> Image:
	var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	image.fill(color)
	return image


func _planks(base: Color = WOOD) -> Image:
	var image := _image(base)
	for y in SIZE:
		for x in SIZE:
			if y % 16 == 0 or (x + int(y / 16) * 23) % 48 == 0:
				image.set_pixel(x, y, WOOD_DARK)
			elif (x * 13 + y * 7) % 31 == 0:
				image.set_pixel(x, y, base.lightened(0.08))
	return image


func _crafting_top() -> Image:
	var image := _planks()
	image.fill_rect(Rect2i(0, 0, 64, 4), WOOD_DEEP)
	image.fill_rect(Rect2i(0, 60, 64, 4), WOOD_DEEP)
	image.fill_rect(Rect2i(0, 0, 4, 64), WOOD_DEEP)
	image.fill_rect(Rect2i(60, 0, 4, 64), WOOD_DEEP)
	for line in [22, 42]:
		image.fill_rect(Rect2i(line, 5, 3, 54), WOOD_DARK)
		image.fill_rect(Rect2i(5, line, 54, 3), WOOD_DARK)
	image.fill_rect(Rect2i(9, 9, 9, 9), IRON_DARK)
	image.fill_rect(Rect2i(31, 29, 4, 15), WOOD_DEEP)
	image.fill_rect(Rect2i(27, 28, 12, 4), IRON)
	return image


func _crafting_side() -> Image:
	var image := _planks()
	image.fill_rect(Rect2i(0, 0, 64, 9), WOOD_DARK)
	image.fill_rect(Rect2i(8, 17, 6, 36), WOOD_DEEP)
	image.fill_rect(Rect2i(45, 17, 7, 36), WOOD_DEEP)
	image.fill_rect(Rect2i(13, 21, 34, 5), IRON_DARK)
	image.fill_rect(Rect2i(27, 25, 5, 25), IRON)
	image.fill_rect(Rect2i(21, 47, 17, 5), IRON_DARK)
	return image


func _chest_top() -> Image:
	var image := _planks(Color("916a3d"))
	image.fill_rect(Rect2i(27, 0, 10, 64), IRON_DARK)
	image.fill_rect(Rect2i(30, 0, 4, 64), IRON)
	for y in [9, 53]:
		image.fill_rect(Rect2i(4, y, 56, 3), WOOD_LIGHT)
	return image


func _chest_side() -> Image:
	var image := _planks(Color("916a3d"))
	image.fill_rect(Rect2i(0, 27, 64, 4), WOOD_DEEP)
	image.fill_rect(Rect2i(28, 0, 8, 64), IRON_DARK)
	image.fill_rect(Rect2i(25, 23, 14, 13), IRON)
	image.fill_rect(Rect2i(30, 28, 4, 8), IRON_DARK)
	image.fill_rect(Rect2i(3, 3, 58, 3), WOOD_LIGHT)
	return image


func _stone(dark: bool) -> Image:
	var base := STONE.darkened(0.14) if dark else STONE
	var image := _image(base)
	for y in range(0, SIZE, 16):
		image.fill_rect(Rect2i(0, y, SIZE, 3), STONE_DARK)
		var offset := 16 if int(y / 16) % 2 == 1 else 0
		for x in range(offset, SIZE, 32):
			image.fill_rect(Rect2i(x, y, 3, 16), STONE_DARK)
	return image


func _furnace_side() -> Image:
	var image := _stone(false)
	image.fill_rect(Rect2i(17, 37, 30, 19), Color("25292b"))
	image.fill_rect(Rect2i(20, 41, 24, 12), Color("6f3021"))
	image.fill_rect(Rect2i(23, 46, 18, 7), Color("e26e2f"))
	image.fill_rect(Rect2i(29, 44, 8, 8), Color("ffc15a"))
	for y in [18, 24, 30]:
		image.fill_rect(Rect2i(22, y, 20, 3), STONE_DARK)
	return image


func _door(upper: bool) -> Image:
	var image := _image(WOOD)
	for x in [0, 21, 42, 61]:
		image.fill_rect(Rect2i(x, 0, 3, 64), WOOD_DARK)
	image.fill_rect(Rect2i(0, 0, 64, 4), WOOD_DEEP)
	image.fill_rect(Rect2i(0, 60, 64, 4), WOOD_DEEP)
	if upper:
		image.fill_rect(Rect2i(20, 12, 25, 24), WOOD_DEEP)
		for y in [15, 27]:
			for x in [23, 35]:
				image.fill_rect(Rect2i(x, y, 8, 8), Color("354957"))
				image.fill_rect(Rect2i(x + 1, y + 1, 3, 2), Color("a8c7d5"))
		image.fill_rect(Rect2i(50, 42, 7, 7), IRON)
	else:
		image.fill_rect(Rect2i(4, 45, 56, 5), WOOD_DEEP)
		image.fill_rect(Rect2i(4, 56, 56, 5), IRON_DARK)
	return image


func _ladder() -> Image:
	var image := _image(Color("604729"))
	image.fill_rect(Rect2i(6, 0, 8, 64), WOOD_DARK)
	image.fill_rect(Rect2i(50, 0, 8, 64), WOOD_DARK)
	for y in range(8, 64, 12):
		image.fill_rect(Rect2i(10, y, 44, 6), WOOD_LIGHT)
		image.fill_rect(Rect2i(10, y + 5, 44, 2), WOOD_DARK)
	return image


func _sign() -> Image:
	var image := _image(Color("c6a06b"))
	image.fill_rect(Rect2i(0, 0, 64, 5), WOOD_DARK)
	image.fill_rect(Rect2i(0, 59, 64, 5), WOOD_DARK)
	image.fill_rect(Rect2i(0, 0, 5, 64), WOOD_DARK)
	image.fill_rect(Rect2i(59, 0, 5, 64), WOOD_DARK)
	image.fill_rect(Rect2i(29, 8, 6, 6), IRON_DARK)
	for row in 3:
		var width := 39 - row * 5
		image.fill_rect(Rect2i(12 + row * 3, 23 + row * 10, width, 3), Color("67472c"))
	return image


func _bed_top() -> Image:
	var image := _image(Color("a9413d"))
	image.fill_rect(Rect2i(0, 0, 64, 19), Color("e8dfcf"))
	image.fill_rect(Rect2i(5, 3, 54, 12), Color("f6f0e5"))
	image.fill_rect(Rect2i(0, 18, 64, 3), Color("7d302e"))
	for diagonal in range(-64, 64, 12):
		for y in range(22, 64):
			var x := diagonal + y
			if x >= 0 and x < 64:
				image.set_pixel(x, y, Color("c25954"))
	return image


func _bed_side() -> Image:
	var image := _image(Color("a9413d"))
	image.fill_rect(Rect2i(0, 0, 64, 4), Color("d06b65"))
	image.fill_rect(Rect2i(0, 39, 64, 16), WOOD_DARK)
	image.fill_rect(Rect2i(4, 52, 9, 12), WOOD_DEEP)
	image.fill_rect(Rect2i(51, 52, 9, 12), WOOD_DEEP)
	return image


func _write(filename: String, image: Image) -> void:
	var error := image.save_png("%s/%s" % [OUTPUT, filename])
	if error != OK:
		push_error("Failed to save %s: %s" % [filename, error_string(error)])
