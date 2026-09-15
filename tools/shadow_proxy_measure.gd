## Controlled A/B measurement for the leaf shadow proxy. Loads the real gameplay
## scene with a flat world, builds a leaf canopy over flat ground, parks the
## camera and sun at fixed poses, and measures shadow-region temporal MAD across
## sun steps — once with the proxy off and once on, in the same run so nothing
## else varies. Writes frames to user://shadow_proxy_measure/ and prints the two
## numbers. Requires a rendering display (not headless):
##   redot --path . res://tools/shadow_proxy_measure.tscn
extends Node

const FRAMES_PER_PHASE := 12
const OUTPUT_DIR := "user://shadow_proxy_measure"
const SUN_ELEVATION_START := 30.0
const SUN_ELEVATION_STEP := 0.1
const SUN_YAW := -35.0
const CANOPY_RADIUS := 8
const GROUND_RADIUS := 26
const CANOPY_HEIGHT_OFFSET := 4

var _main: Node3D
var _world: VoxelWorld
var _sun: DirectionalLight3D
var _camera: Camera3D
var _material: ShaderMaterial
var _base := Vector3.ZERO


func _ready() -> void:
	_main = load("res://game/main.tscn").instantiate()
	# Flat world keeps the canopy shadow on a stable, unbroken surface.
	GameConfig.world["world_type"] = 1
	GameConfig.world["seed"] = 918273
	GameConfig.world["tree_density"] = 0.0
	GameConfig.set_setting("render_distance", 4)
	add_child(_main)
	_run.call_deferred()


func _run() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	_world = _main.get_node("World") as VoxelWorld
	_sun = _main.get_node("Sun") as DirectionalLight3D
	var player = _main.get_node("Player")
	_camera = player.camera as Camera3D
	_material = _world.get_registry().material as ShaderMaterial
	# Let the flat spawn chunks stream in, then flatten the area and lay a canopy.
	await _wait_seconds(8.0)
	_base = Vector3(roundi(player.global_position.x) + 0.5, float(VoxelDefs.SEA_LEVEL + 1), roundi(player.global_position.z) + 0.5)
	_sculpt_canopy(Vector3i(_base))
	await _wait_seconds(3.0)
	# Park the camera in a fixed oblique pose framing the shadow footprint. The
	# camera is held at a fixed world pose for both phases, so the only variable
	# is the proxy; the sun sweep moves the shadow through the framed ground.
	player.set_physics_process(false)
	player.set_process_input(false)
	_camera.top_level = true
	_sun.directional_shadow_max_distance = 120.0
	_sun.shadow_blur = 0.5
	_sun.light_angular_distance = 0.0
	RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM)
	# Screen-space and volumetric effects add their own temporal noise; the
	# reported A/B isolates the shadow-map sampler.
	var environment: Environment = _main.get_node("WorldEnvironment").environment
	environment.ssao_enabled = false
	environment.ssil_enabled = false
	environment.sdfgi_enabled = false
	environment.volumetric_fog_enabled = false
	environment.ssr_enabled = false
	environment.glow_enabled = false
	var mid_elevation := SUN_ELEVATION_START + (FRAMES_PER_PHASE - 1) * SUN_ELEVATION_STEP * 0.5
	_sun.rotation_degrees = Vector3(-mid_elevation, SUN_YAW, 0.0)
	await _wait_seconds(0.5)
	var shadow_center := _shadow_center(mid_elevation)
	# Tight, low view across the shadow boundary so the edge fills the frame.
	var edge := shadow_center + Vector3(0.0, 0.0, float(CANOPY_RADIUS))
	_camera.global_position = edge + Vector3(0.0, 1.6, 7.0)
	_camera.look_at(edge + Vector3(0.0, 0.2, -2.0), Vector3.UP)
	_camera.fov = 40.0
	await _wait_seconds(1.0)
	var viewport := get_viewport()
	var results := {}
	for taa in [false, true]:
		viewport.use_taa = taa
		viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		viewport.scaling_3d_scale = 1.0
		await _wait_seconds(0.5)
		# off, off again (control for run-to-run noise), then on.
		results[taa] = [await _measure(false, taa), await _measure(false, taa), await _measure(true, taa)]
	print("SHADOW PROXY MEASURE (off -> off(control) -> on):")
	print("  no TAA: %.4f -> %.4f -> %.4f" % results[false])
	print("  TAA:    %.4f -> %.4f -> %.4f" % results[true])
	get_tree().quit(0)


## Ground point hit by the shadow of the canopy slab center, from the canopy
## height above the ground and the sun's light direction.
func _shadow_center(elevation: float) -> Vector3:
	var light_dir := -_sun.global_transform.basis.z
	var height := float(CANOPY_HEIGHT_OFFSET)
	var horizontal := Vector3(light_dir.x, 0.0, light_dir.z)
	var vertical := maxf(-light_dir.y, 0.05)
	return _base + horizontal * (height / vertical)


## Builds an explicit flat platform plus a solid leaf slab above it, so the
## ground under the canopy gets a clean island of leaf shadow regardless of the
## generated terrain around it.
func _sculpt_canopy(base: Vector3i) -> void:
	for dz in range(-GROUND_RADIUS, GROUND_RADIUS + 1):
		for dx in range(-GROUND_RADIUS, GROUND_RADIUS + 1):
			for dy in range(-4, 0):
				_world.place_block(base + Vector3i(dx, dy, dz), BlockRegistry.BLOCK_STONE)
			_world.place_block(base + Vector3i(dx, 0, dz), BlockRegistry.BLOCK_GRASS)
	for dz in range(-CANOPY_RADIUS, CANOPY_RADIUS + 1):
		for dx in range(-CANOPY_RADIUS, CANOPY_RADIUS + 1):
			_world.place_block(base + Vector3i(dx, CANOPY_HEIGHT_OFFSET, dz), BlockRegistry.BLOCK_LEAVES)


func _measure(proxy_on: bool, taa: bool) -> float:
	if _material:
		_material.set_shader_parameter("solid_leaf_shadows", 1.0 if proxy_on else 0.0)
	DirAccess.make_dir_recursive_absolute(OUTPUT_DIR)
	var phase := "on" if proxy_on else "off"
	var taa_tag := "taa" if taa else "notaa"
	var images: Array[Image] = []
	for index in FRAMES_PER_PHASE:
		_sun.rotation_degrees = Vector3(-(SUN_ELEVATION_START + index * SUN_ELEVATION_STEP), SUN_YAW, 0.0)
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var image := get_viewport().get_texture().get_image()
		image.save_png("%s/%s_%s_%02d.png" % [OUTPUT_DIR, taa_tag, phase, index])
		images.append(image)
	var total := 0.0
	var pairs := 0
	for i in range(images.size() - 1):
		total += _frame_mad(images[i], images[i + 1])
		pairs += 1
	return total / maxf(float(pairs), 1.0)


## Mean absolute luminance difference between consecutive frames over the
## shadow boundary. Shadow interiors and fully lit ground are temporally stable,
## so only pixels whose luminance sits between the lit plateau and the shadow
## floor — the shadow edge band — are sampled, which is where the leaf cutout
## silhouette aliases.
func _frame_mad(a: Image, b: Image) -> float:
	var width := mini(a.get_width(), b.get_width())
	var height := mini(a.get_height(), b.get_height())
	var step := 2
	var luminances := PackedFloat32Array()
	var coords := PackedInt32Array()
	var py := 0
	while py < height:
		var px := 0
		while px < width:
			var color := a.get_pixel(px, py)
			luminances.append(0.2126 * color.r + 0.7152 * color.g + 0.0722 * color.b)
			coords.append(py * width + px)
			px += step
		py += step
	if luminances.is_empty():
		return 0.0
	var sorted := Array(luminances)
	sorted.sort()
	var low: float = sorted[int(sorted.size() * 0.1)]
	var high: float = sorted[int(sorted.size() * 0.9)]
	var band_low := low + (high - low) * 0.2
	var band_high := low + (high - low) * 0.8
	var sum := 0.0
	var count := 0
	for index in luminances.size():
		var value := luminances[index]
		if value < band_low or value > band_high:
			continue
		var point := coords[index]
		var color_b := b.get_pixel(point % width, point / width)
		var lb := 0.2126 * color_b.r + 0.7152 * color_b.g + 0.0722 * color_b.b
		sum += absf(value - lb)
		count += 1
	return sum / maxf(float(count), 1.0)


func _wait_seconds(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout
