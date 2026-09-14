extends SceneTree

## One-off generator for RedotCraft's placeholders under
## assets/placeholders/underwater/. Deterministic output so regenerating
## produces identical PNGs.

const SIZE := 64
const OUTPUT_DIR := "res://assets/placeholders/underwater"
const CAVE_OUTPUT_DIR := "res://assets/placeholders/caves"

var _rng := RandomNumberGenerator.new()


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CAVE_OUTPUT_DIR))
	_rng.seed = 0xC0A1
	_save("coral_substrate.png", _coral_substrate())
	_save("sponge.png", _sponge())
	_save("seagrass.png", _seagrass())
	_save("kelp.png", _kelp())
	_save("coral_fan.png", _coral_fan())
	_save("coral_branch.png", _coral_branch())
	_save("anemone.png", _anemone())
	_save_cave("dripstone.png", _stone_texture(Color("#745b48"), Color("#9a795c"), Color("#493a31")))
	_save_cave("moss.png", _stone_texture(Color("#416637"), Color("#668d4c"), Color("#293f29")))
	_save_cave("deepstone.png", _stone_texture(Color("#202732"), Color("#35404c"), Color("#111720")))
	_save_cave("sculk.png", _speckled_texture(Color("#10272b"), Color("#1b7a83"), Color("#48b2a2")))
	_save_cave("calcite.png", _stone_texture(Color("#d5d0c2"), Color("#eee9da"), Color("#aaa99f")))
	_save_cave("geode_shell.png", _stone_texture(Color("#303640"), Color("#4e5965"), Color("#20242d")))
	_save_cave("amethyst.png", _speckled_texture(Color("#684b86"), Color("#a779cf"), Color("#d5b4f0")))
	_save_cave("cave_moss.png", _cave_moss())
	_save_cave("crystal_bud.png", _crystal_bud())
	print("UNDERWATER TEXTURES: done")
	quit()


func _new_image() -> Image:
	var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	return image


func _save(name: String, image: Image) -> void:
	var path := "%s/%s" % [OUTPUT_DIR, name]
	var error := image.save_png(path)
	if error != OK:
		push_error("failed to save %s (%d)" % [path, error])
	else:
		print("saved ", path)


func _save_cave(name: String, image: Image) -> void:
	var path := "%s/%s" % [CAVE_OUTPUT_DIR, name]
	var error := image.save_png(path)
	if error != OK:
		push_error("failed to save %s (%d)" % [path, error])
	else:
		print("saved ", path)


func _stone_texture(base: Color, light: Color, dark: Color) -> Image:
	var image := _new_image()
	image.fill(base)
	for index in 110:
		var color := light if index % 3 == 0 else dark
		_disc(image, _rng.randi_range(0, SIZE - 1), _rng.randi_range(0, SIZE - 1), _rng.randf_range(0.8, 3.4), color)
	return image


func _speckled_texture(base: Color, middle: Color, bright: Color) -> Image:
	var image := _stone_texture(base, middle, base.darkened(0.25))
	for index in 42:
		var x := _rng.randi_range(1, SIZE - 2)
		var y := _rng.randi_range(1, SIZE - 2)
		_put(image, x, y, bright)
		if index % 3 == 0:
			_put(image, x + 1, y, middle)
	return image


func _cave_moss() -> Image:
	var image := _new_image()
	var colors := [Color("#86b85c"), Color("#5f9142"), Color("#b0d978")]
	for strand in 11:
		var x := 4 + strand * 5 + _rng.randi_range(-1, 1)
		var top := _rng.randi_range(5, 28)
		_blade(image, float(x), top, SIZE - 1, 1, _rng.randf_range(1.0, 2.5), colors)
	return image


func _crystal_bud() -> Image:
	var image := _new_image()
	var dark := Color("#66458f")
	var body := Color("#a06ed1")
	var light := Color("#dfc1ff")
	for crystal in 5:
		var center := 11 + crystal * 10 + _rng.randi_range(-2, 2)
		var top := _rng.randi_range(7, 28)
		for y in range(top, SIZE):
			var t := float(y - top) / float(SIZE - top)
			var half_width := maxi(1, roundi(3.0 * t))
			for x in range(center - half_width, center + half_width + 1):
				_put(image, x, y, light if x == center - half_width else (dark if x == center + half_width else body))
	return image


func _put(image: Image, x: int, y: int, color: Color) -> void:
	if x >= 0 and x < SIZE and y >= 0 and y < SIZE:
		image.set_pixel(x, y, color)


func _disc(image: Image, center_x: int, center_y: int, radius: float, color: Color) -> void:
	var limit := int(ceilf(radius))
	for dy in range(-limit, limit + 1):
		for dx in range(-limit, limit + 1):
			var distance := sqrt(float(dx * dx + dy * dy))
			if distance <= radius:
				_put(image, center_x + dx, center_y + dy, color)


func _rect(image: Image, x0: int, y0: int, x1: int, y1: int, color: Color) -> void:
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			_put(image, x, y, color)


func _shade(color: Color, amount: float) -> Color:
	return Color(clampf(color.r + amount, 0.0, 1.0), clampf(color.g + amount, 0.0, 1.0), clampf(color.b + amount, 0.0, 1.0), color.a)


## Mottled grey-rose reef rock with pale encrusting spots and dark pits.
func _coral_substrate() -> Image:
	var image := _new_image()
	var base := Color(0.56, 0.45, 0.44)
	var blotch := Color(0.47, 0.37, 0.38)
	var pale := Color(0.7, 0.6, 0.57)
	var pit := Color(0.34, 0.27, 0.29)
	image.fill(base)
	for index in 90:
		var x := _rng.randi_range(0, SIZE - 1)
		var y := _rng.randi_range(0, SIZE - 1)
		var radius := _rng.randf_range(2.0, 6.0)
		_disc(image, x, y, radius, blotch if index % 3 != 0 else _shade(blotch, 0.04))
	for index in 60:
		var x := _rng.randi_range(0, SIZE - 1)
		var y := _rng.randi_range(0, SIZE - 1)
		_disc(image, x, y, _rng.randf_range(0.8, 2.2), pale)
	for index in 22:
		var x := _rng.randi_range(0, SIZE - 1)
		var y := _rng.randi_range(0, SIZE - 1)
		_disc(image, x, y, _rng.randf_range(1.0, 2.6), pit)
	return image


## Porous golden sponge.
func _sponge() -> Image:
	var image := _new_image()
	var base := Color(0.74, 0.56, 0.2)
	var pore := Color(0.45, 0.32, 0.11)
	var rim := Color(0.88, 0.72, 0.34)
	image.fill(base)
	for index in 80:
		var x := _rng.randi_range(0, SIZE - 1)
		var y := _rng.randi_range(0, SIZE - 1)
		_disc(image, x, y, _rng.randf_range(1.0, 3.2), pore)
	for index in 40:
		var x := _rng.randi_range(0, SIZE - 1)
		var y := _rng.randi_range(0, SIZE - 1)
		_disc(image, x, y, _rng.randf_range(0.7, 1.6), rim)
	return image


## Wavy blade drawn as a vertical run of pixels with a lean.
func _blade(image: Image, base_x: float, top_y: int, bottom_y: int, width: int, lean: float, colors: Array) -> void:
	var length := maxi(bottom_y - top_y, 1)
	for y in range(top_y, bottom_y + 1):
		var t := float(y - top_y) / float(length)
		var x := int(round(base_x + sin(t * PI * 1.2) * lean))
		var taper := width
		if t < 0.18:
			taper = maxi(1, width - 2)
		var band := 0
		if t < 0.35:
			band = 0
		elif t < 0.75:
			band = 1
		else:
			band = 2
		for offset in range(-taper, taper + 1):
			_put(image, x + offset, y, colors[band])


## A stand of green blades, transparent background (cross-block texture).
func _seagrass() -> Image:
	var image := _new_image()
	var colors := [Color(0.42, 0.74, 0.4), Color(0.3, 0.62, 0.32), Color(0.22, 0.47, 0.26)]
	for index in 7:
		var base_x := 8.0 + float(index) * 8.0 + _rng.randf_range(-1.5, 1.5)
		var top_y := _rng.randi_range(12, 34)
		_blade(image, base_x, top_y, SIZE - 1, _rng.randi_range(1, 2), _rng.randf_range(1.0, 3.5), colors)
	return image


## Tall olive fronds, transparent background (cross-block texture).
func _kelp() -> Image:
	var image := _new_image()
	var colors := [Color(0.5, 0.6, 0.22), Color(0.4, 0.5, 0.17), Color(0.28, 0.35, 0.12)]
	for index in 4:
		var base_x := 10.0 + float(index) * 15.0 + _rng.randf_range(-2.0, 2.0)
		_blade(image, base_x, _rng.randi_range(1, 6), SIZE - 1, _rng.randi_range(2, 3), _rng.randf_range(2.5, 5.0), colors)
	return image


## Rounded pink fan built from stacked arcs over a stub trunk.
func _coral_fan() -> Image:
	var image := _new_image()
	var body := Color(0.86, 0.44, 0.57)
	var edge := Color(0.62, 0.29, 0.42)
	var tip := Color(0.96, 0.65, 0.74)
	var center_x := SIZE / 2
	_rect(image, center_x - 2, 46, center_x + 2, SIZE - 1, edge)
	for layer in 5:
		var radius := 20.0 - float(layer) * 3.4
		var center_y := 44 - layer * 2
		for step in 18:
			var angle := PI + float(step) * PI / 17.0
			var x := int(round(float(center_x) + cos(angle) * radius))
			var y := int(round(float(center_y) + sin(angle) * radius * 0.85))
			var color := tip if layer == 0 else (body if layer % 2 == 0 else edge)
			_disc(image, x, y, 1.2, color)
	return image


## Thick orange branches with rounded tips.
func _coral_branch() -> Image:
	var image := _new_image()
	var body := Color(0.9, 0.56, 0.24)
	var edge := Color(0.66, 0.38, 0.15)
	var tip := Color(0.97, 0.72, 0.38)
	var trunk_x := SIZE / 2
	for y in range(34, SIZE):
		_disc(image, trunk_x, y, 3.0, edge)
		_disc(image, trunk_x - 1, y - 1, 1.6, body)
	var branches := [[-12, 30], [13, 26], [-7, 18], [8, 14]]
	for branch in branches:
		var end_x: int = trunk_x + int(branch[0])
		var end_y: int = int(branch[1])
		for step in range(0, 40):
			var t := float(step) / 39.0
			var x := int(round(lerpf(float(trunk_x), float(end_x), t)))
			var y := int(round(lerpf(32.0, float(end_y), t)))
			_disc(image, x, y, 2.4, body)
			_disc(image, x, y + 1, 1.6, edge)
		_disc(image, end_x, end_y, 3.2, tip)
	return image


## Pale-tipped tentacles over a low mound.
func _anemone() -> Image:
	var image := _new_image()
	var body := Color(0.58, 0.4, 0.78)
	var edge := Color(0.42, 0.28, 0.6)
	var tip := Color(0.84, 0.75, 0.95)
	var center_x := SIZE / 2
	for y in range(52, SIZE):
		_disc(image, center_x, y, 6.0 - float(y - 52) * 0.4, edge)
	for index in 9:
		var base_x := float(center_x - 12 + index * 3)
		var top_y := 18 + _rng.randi_range(0, 12)
		var length := SIZE - 6 - top_y
		for step in range(length):
			var t := float(step) / float(maxi(length, 1))
			var x := int(round(base_x + sin(t * PI * 1.6 + float(index)) * 2.5))
			var y := top_y + step
			_put(image, x, y, tip if t > 0.75 else body)
			_put(image, x + 1, y, edge if t < 0.75 else tip)
	return image
