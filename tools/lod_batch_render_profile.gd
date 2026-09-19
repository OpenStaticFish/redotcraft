## Rendered Forward+ A/B profiler for compact Balanced-LOD batching.
##
## Run only with a real display/Forward+ renderer; headless execution deliberately
## refuses to print performance numbers because it submits no rendered frames:
##   redot --path . res://tools/lod_batch_render_profile.tscn
##
## The fixture uses a fixed viewport, seed, camera, and render settings. It
## samples renderer counters after frame_post_draw. Draw calls and primitives
## are actual rendered-frame values. Frame time is wall-clock presented-frame
## interval, not a GPU timestamp query; it includes engine/main-thread work and
## is affected by the display server and driver.
extends Node

const SEED := 918273
const BALANCED_DISTANCES := [10, 16]
const NORMAL_DISTANCES := [10, 16]
const PROFILE_VIEWPORT := Vector2i(1280, 720)
const WARMUP_FRAMES := 30
const SAMPLE_FRAMES := 120
const SETTLE_SECONDS := 90.0
const BATCH_SETTLE_SECONDS := 45.0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("LOD BATCH RENDER PROFILE requires a display; headless counters are not rendered measurements")
		get_tree().quit(2)
		return
	var prior_vsync := DisplayServer.window_get_vsync_mode()
	var prior_max_fps := Engine.max_fps
	var window := get_window()
	var prior_size := window.size
	var viewport := get_viewport()
	var prior_taa := viewport.use_taa
	var prior_scale := viewport.scaling_3d_scale
	var prior_scaling_mode := viewport.scaling_3d_mode
	var prior_msaa := viewport.msaa_3d
	# Remove the fixed presentation cadence so the sampled wall-frame interval can
	# expose an A/B difference. This remains a frame interval rather than a GPU
	# timestamp; renderer counters below are the authoritative draw measurements.
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	window.size = PROFILE_VIEWPORT
	viewport.use_taa = false
	viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	viewport.scaling_3d_scale = 1.0
	viewport.msaa_3d = Viewport.MSAA_DISABLED
	await get_tree().process_frame
	var normal := "--normal" in OS.get_cmdline_user_args()
	var include_rd24 := "--rd24" in OS.get_cmdline_user_args()
	var distances: Array[int] = []
	var source_distances: Array = NORMAL_DISTANCES if normal else BALANCED_DISTANCES
	for distance in source_distances:
		distances.append(distance)
	if include_rd24:
		distances.append(24)
	var profile_failed := false
	print("LOD BATCH RENDER PROFILE")
	print("  renderer: %s" % RenderingServer.get_rendering_device().get_device_name())
	print("  display: %s; viewport: %s; seed: %d; fixture: %s Balanced LOD" % [
		DisplayServer.get_name(), PROFILE_VIEWPORT, SEED, "normal" if normal else "flat"])
	for distance in distances:
		var world := VoxelWorld.new()
		add_child(world)
		world.configure({"seed": SEED, "world_type": 0 if normal else 1,
			"tree_density": 1.0 if normal else 0.0}, distance,
			VoxelWorld.LOD_MODE_BALANCED)
		var target := Node3D.new()
		target.position = Vector3(0.5, 64.0, 0.5)
		add_child(target)
		world.setup_player(target)
		var camera := Camera3D.new()
		camera.position = Vector3(0.0, 118.0, float(distance * 16 + 45))
		camera.fov = 66.0
		camera.far = float((distance + 2) * VoxelDefs.CHUNK_SIZE * 3)
		camera.current = true
		add_child(camera)
		camera.look_at(Vector3(0.0, 30.0, 0.0), Vector3.UP)
		var sun := DirectionalLight3D.new()
		sun.rotation_degrees = Vector3(-55.0, -25.0, 0.0)
		add_child(sun)
		var settled := await _wait_for_settle(world)
		if not settled:
			push_error("LOD batch render profile timed out at RD%d: %s" % [distance, world.get_worldgen_stats()])
			await _cleanup(world, target, camera, sun)
			profile_failed = true
			continue
		world.set_lod_batching_enabled(false)
		var off_first := await _sample()
		world.set_lod_batching_enabled(true)
		if not await _wait_for_batches(world):
			push_error("LOD batch render profile did not settle batches at RD%d: %s" % [distance, world.get_lod_batch_stats()])
			await _cleanup(world, target, camera, sun)
			profile_failed = true
			continue
		var on := await _sample()
		var on_batches := int(world.get_lod_batch_stats()["batches"])
		world.set_lod_batching_enabled(false)
		var off_control := await _sample()
		print("  RD%d OFF draws %.1f primitives %.1f p50/p95/p99 %.2f/%.2f/%.2f ms | ON draws %.1f primitives %.1f p50/p95/p99 %.2f/%.2f/%.2f ms | OFF control %.2f/%.2f/%.2f ms | batches %d" % [
			distance, off_first.draw_calls, off_first.primitives, off_first.p50_ms, off_first.p95_ms, off_first.p99_ms,
			on.draw_calls, on.primitives, on.p50_ms, on.p95_ms, on.p99_ms,
			off_control.p50_ms, off_control.p95_ms, off_control.p99_ms,
			on_batches,
		])
		await _cleanup(world, target, camera, sun)
	DisplayServer.window_set_vsync_mode(prior_vsync)
	Engine.max_fps = prior_max_fps
	window.size = prior_size
	viewport.use_taa = prior_taa
	viewport.scaling_3d_mode = prior_scaling_mode
	viewport.scaling_3d_scale = prior_scale
	viewport.msaa_3d = prior_msaa
	print("LOD BATCH RENDER PROFILE: %s" % ("FAIL" if profile_failed else "COMPLETE"))
	get_tree().quit(1 if profile_failed else 0)


func _wait_for_settle(world: VoxelWorld) -> bool:
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < SETTLE_SECONDS * 1000.0:
		await get_tree().create_timer(0.25).timeout
		if world._pending.is_empty() and world._gen_queue.is_empty() and world._mesh_queue.is_empty() \
				and world._generated.is_empty() and world._commit_queue.is_empty() \
				and int(world.get_streaming_progress()["loaded"]) == world._desired.size():
			return true
	return false


func _wait_for_batches(world: VoxelWorld) -> bool:
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < BATCH_SETTLE_SECONDS * 1000.0:
		await get_tree().process_frame
		if world._lod_batch_refill_complete and world._lod_batch_queue.is_empty():
			return true
	return false


func _sample() -> Dictionary:
	for _frame in WARMUP_FRAMES:
		await RenderingServer.frame_post_draw
	var draws := 0.0
	var primitives := 0.0
	var frame_samples: Array[float] = []
	for _frame in SAMPLE_FRAMES:
		var started := Time.get_ticks_usec()
		await RenderingServer.frame_post_draw
		frame_samples.append(float(Time.get_ticks_usec() - started) / 1000.0)
		draws += float(RenderingServer.get_rendering_info(
			RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
		primitives += float(RenderingServer.get_rendering_info(
			RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))
	frame_samples.sort()
	return {
		"draw_calls": draws / float(SAMPLE_FRAMES),
		"primitives": primitives / float(SAMPLE_FRAMES),
		"p50_ms": _percentile(frame_samples, 0.50),
		"p95_ms": _percentile(frame_samples, 0.95),
		"p99_ms": _percentile(frame_samples, 0.99),
	}


func _percentile(sorted_samples: Array[float], percentile: float) -> float:
	if sorted_samples.is_empty():
		return 0.0
	var index := clampi(ceili(float(sorted_samples.size()) * percentile) - 1,
		0, sorted_samples.size() - 1)
	return sorted_samples[index]


func _cleanup(world: VoxelWorld, target: Node3D, camera: Camera3D, sun: DirectionalLight3D) -> void:
	world.queue_free()
	target.queue_free()
	camera.queue_free()
	sun.queue_free()
	await get_tree().process_frame
