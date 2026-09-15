extends SceneTree

## One-off generator for RedotCraft's fire placeholder under
## assets/placeholders/fire/. The block shader stretches and wavers this sheet,
## so a single deterministic set of flame tongues is enough for the animated
## cross-block flame. Hottest at the base, cooling to red tips.

const SIZE := 64
const OUTPUT_DIR := "res://assets/placeholders/fire"

var _rng := RandomNumberGenerator.new()


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	_rng.seed = 0xF17E
	_save("fire.png", _fire())
	_save("smoke.png", _smoke())
	print("FIRE TEXTURE: done")
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


func _fire() -> Image:
	var image := _new_image()
	# A low ember bed across the cell base ties the tongues together.
	for x in SIZE:
		var bed := 3 + _rng.randi_range(0, 2)
		for y in range(SIZE - bed, SIZE):
			_put(image, x, y, _flame_color(0.2), 0.75)
	# Overlapping tongues of varying height; each is thick at the base and
	# tapers and sways toward a cooling red tip.
	var count := 7
	for index in count:
		var center := (float(index) + 0.5) * (float(SIZE) / float(count)) + _rng.randf_range(-2.5, 2.5)
		var height := _rng.randf_range(34.0, 58.0)
		var sway := _rng.randf_range(-3.5, 3.5)
		var half_base := _rng.randf_range(4.0, 6.5)
		_tongue(image, center, height, sway, half_base)
	# A few sparks breaking off above the flames.
	for index in 6:
		var x := _rng.randi_range(3, SIZE - 4)
		var y := _rng.randi_range(2, 20)
		_disc(image, x, y, _rng.randf_range(0.7, 1.6), Color(1.0, 0.66, 0.18, 0.9))
	return image


## Soft billowy grey puff for the smoke overlay, masked to a round falloff.
func _smoke() -> Image:
	var image := _new_image()
	var base := Color(0.16, 0.16, 0.18)
	for index in 30:
		var x := SIZE / 2 + _rng.randi_range(-15, 15)
		var y := SIZE / 2 + _rng.randi_range(-15, 15)
		_soft_disc(image, x, y, _rng.randf_range(6.0, 16.0), _rng.randf_range(0.12, 0.34))
	for y in SIZE:
		for x in SIZE:
			var distance := Vector2(float(x), float(y)).distance_to(Vector2(SIZE * 0.5, SIZE * 0.5)) / (SIZE * 0.5)
			var mask := clampf(1.0 - distance, 0.0, 1.0)
			var pixel := image.get_pixel(x, y)
			image.set_pixel(x, y, Color(base.r, base.g, base.b, pixel.a * mask))
	return image


## Accumulates a soft additive blob so overlapping puffs build a billowy edge.
func _soft_disc(image: Image, center_x: int, center_y: int, radius: float, strength: float) -> void:
	var limit := int(ceilf(radius))
	for dy in range(-limit, limit + 1):
		for dx in range(-limit, limit + 1):
			var distance := sqrt(float(dx * dx + dy * dy))
			if distance > radius:
				continue
			var x := center_x + dx
			var y := center_y + dy
			if x < 0 or x >= SIZE or y < 0 or y >= SIZE:
				continue
			var falloff := 1.0 - distance / radius
			var alpha := clampf(image.get_pixel(x, y).a + strength * falloff, 0.0, 1.0)
			image.set_pixel(x, y, Color(1, 1, 1, alpha))


## Warm yellow base cooling through orange into a red tip.
func _flame_color(t: float) -> Color:
	if t < 0.42:
		return Color(1.0, 0.74, 0.2).lerp(Color(1.0, 0.44, 0.06), t / 0.42)
	return Color(1.0, 0.44, 0.06).lerp(Color(0.6, 0.08, 0.03), (t - 0.42) / 0.58)


func _tongue(image: Image, center: float, height: float, sway: float, half_base: float) -> void:
	var pixels := int(height)
	for step in pixels:
		var t := float(step) / float(maxi(pixels - 1, 1))
		var y := SIZE - 1 - step
		var x := center + sway * t + sin(t * 3.4) * 1.6
		var half := maxf(0.4, half_base * (1.0 - t * t))
		var alpha := 1.0
		if t > 0.82:
			alpha = clampf((1.0 - t) / 0.18, 0.0, 1.0)
		for offset in range(-int(ceilf(half)), int(ceilf(half)) + 1):
			if absf(float(offset)) > half:
				continue
			# Erode the outer edges a little so the silhouette is ragged.
			if absf(float(offset)) > half - 1.0 and _rng.randf() < 0.35:
				continue
			_put(image, int(round(x)) + offset, y, _flame_color(t), alpha)


func _put(image: Image, x: int, y: int, color: Color, alpha: float) -> void:
	if x < 0 or x >= SIZE or y < 0 or y >= SIZE:
		return
	var existing := image.get_pixel(x, y)
	if existing.a > alpha:
		return
	image.set_pixel(x, y, Color(color.r, color.g, color.b, alpha))


func _disc(image: Image, center_x: int, center_y: int, radius: float, color: Color) -> void:
	var limit := int(ceilf(radius))
	for dy in range(-limit, limit + 1):
		for dx in range(-limit, limit + 1):
			if sqrt(float(dx * dx + dy * dy)) > radius:
				continue
			_put(image, center_x + dx, center_y + dy, color, color.a)
