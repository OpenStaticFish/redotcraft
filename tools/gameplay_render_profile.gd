## Rendered gameplay profiler for the production Main scene.
##
## Requires a real Forward+ display and deliberately refuses headless mode:
##   redot --path . res://tools/gameplay_render_profile.tscn
##
## It instantiates game/main.tscn and replaces its root script *before* adding
## it to the tree. The replacement preserves normal startup while overriding
## persistence and onboarding hooks, so it never creates/saves a world, writes
## settings.cfg, or records first-run hints. It profiles unbatched Full Detail
## at RD10 and RD16 using a fixed seed, noon camera, and 1280x720 window.
##
## RenderingServer's viewport CPU/GPU render-time queries are collected after
## frame_post_draw. Wall frame intervals are reported separately and must not
## be interpreted as GPU times.
extends Node

const MainScene := preload("res://game/main.tscn")

const SEED := 918273
const VIEWPORT_SIZE := Vector2i(1280, 720)
const RENDER_DISTANCES := [10, 16]
const WARMUP_FRAMES := 60
const SAMPLE_FRAMES := 120
const SETTLE_TIMEOUT_SECONDS := 180.0
const NOON_HOUR := 12.0


## This only changes Main's persistence-facing seams. It intentionally lets
## Main._ready(), _apply_config(), world streaming, weather, HUD, environment,
## lights, and normal scene setup run unchanged.
class IsolatedProfileMain extends Main:
	func _prepare_world_storage() -> Dictionary:
		_game_mode = GameMode.SURVIVAL
		_world_storage = null
		return {}


	func _flush_world_save() -> bool:
		return true


	func _exit_tree() -> void:
		get_tree().paused = false


	func _build_first_run_hints() -> void:
		# Never attach the recorder that can update GameConfig.first_run_hints.
		_first_run_hints = null


var _main: Main
var _viewport: Viewport
var _viewport_rid: RID
var _timing_api_available := false
var _saved_game_config := {}
var _saved_window := {}


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("GAMEPLAY RENDER PROFILE requires a real display; headless frames have no rendered viewport timing")
		get_tree().quit(2)
		return
	_save_process_state()
	_configure_isolated_fixture()
	var failed := false
	var failure_reason := ""
	for render_distance in RENDER_DISTANCES:
		var result := await _profile_distance(render_distance)
		if not bool(result.get("ok", false)):
			failed = true
			failure_reason = String(result.get("error", "unknown failure"))
			break
	_restore_process_state()
	if failed:
		push_error("GAMEPLAY RENDER PROFILE: FAIL (%s)" % failure_reason)
		get_tree().quit(1)
	else:
		print("GAMEPLAY RENDER PROFILE: COMPLETE")
		get_tree().quit(0)


func _save_process_state() -> void:
	var window := get_window()
	_saved_window = {
		"size": window.size,
		"mode": DisplayServer.window_get_mode(),
		"vsync": DisplayServer.window_get_vsync_mode(),
		"max_fps": Engine.max_fps,
		"mouse_mode": Input.get_mouse_mode(),
	}
	_saved_game_config = {
		"settings": GameConfig.settings.duplicate(true),
		"graphics": GameConfig.graphics.duplicate(true),
		"world": GameConfig.world.duplicate(true),
		"active_world_id": GameConfig.active_world_id,
		"active_world_metadata": GameConfig.active_world_metadata.duplicate(true),
		"pending_game_mode": GameConfig.pending_game_mode,
	}


func _configure_isolated_fixture() -> void:
	# Do not call GameConfig.set_setting(): a few setting paths save immediately.
	# Replacing these in-memory dictionaries leaves the user's config untouched.
	GameConfig.settings = GameConfig.DEFAULT_SETTINGS.duplicate(true)
	GameConfig.graphics = GameConfig.GRAPHICS_PRESETS[GameConfig.PRESET_MEDIUM].duplicate(true)
	GameConfig.world = GameConfig.DEFAULT_WORLD.duplicate(true)
	GameConfig.world["seed"] = SEED
	GameConfig.world["world_type"] = 0
	GameConfig.world["tree_density"] = 1.0
	GameConfig.settings["lod_mode"] = GameConfig.LOD_MODE_FULL
	GameConfig.settings["lod_batching"] = false
	GameConfig.settings["vsync"] = DisplayServer.VSYNC_DISABLED
	GameConfig.settings["fps_cap"] = 0
	GameConfig.settings["dynamic_resolution"] = false
	GameConfig.settings["autosave_interval"] = 0
	GameConfig.active_world_id = ""
	GameConfig.active_world_metadata.clear()
	GameConfig.pending_game_mode = GameMode.SURVIVAL
	var window := get_window()
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	window.size = VIEWPORT_SIZE


func _profile_distance(render_distance: int) -> Dictionary:
	GameConfig.settings["render_distance"] = render_distance
	var scene_root := MainScene.instantiate() as Node3D
	if scene_root == null:
		return {"ok": false, "error": "could not instantiate game/main.tscn"}
	# This must happen before add_child() so Main startup follows the isolated
	# overrides from its first _ready call.
	scene_root.set_script(IsolatedProfileMain)
	_main = scene_root as Main
	add_child(_main)
	# Desktop input must not move the stream center or open a paused modal during
	# an unattended measurement. Keep Main's normal presentation updates running.
	_main.player.set_physics_process(false)
	_main.player.set_process_unhandled_input(false)
	_main.set_process_unhandled_input(false)
	_main._photo_mode.set_process_unhandled_input(false)
	_main.get_node("ShadowCapture").set_process_unhandled_input(false)
	_main.get_node("ShadowCapture").set_process_unhandled_key_input(false)
	await get_tree().process_frame
	_viewport = get_viewport()
	_viewport_rid = _viewport.get_viewport_rid()
	_timing_api_available = _has_viewport_timing_api()
	if _timing_api_available:
		RenderingServer.viewport_set_measure_render_time(_viewport_rid, true)
	if not await _wait_for_world_settle(_main.world):
		await _dispose_main()
		return {"ok": false, "error": "RD%d did not settle within %.0f seconds" % [render_distance, SETTLE_TIMEOUT_SECONDS]}
	_pin_render_state()
	await _wait_rendered_frames(WARMUP_FRAMES)
	_print_fixture_header(render_distance)
	# All supported production quality effects are on for this first reference.
	_print_sample("RD%d reference (all medium effects on)" % render_distance, await _sample())
	# The production settings expose SSAO and SSIL as one switch; all other
	# phases toggle exactly one setting and use off -> on -> off control.
	for effect in ["shadows", "ssao_ssil", "ssr", "volumetric_fog"]:
		_set_effect(effect, false)
		_print_sample("RD%d %s off" % [render_distance, _effect_label(effect)], await _sample())
		_set_effect(effect, true)
		_print_sample("RD%d %s on" % [render_distance, _effect_label(effect)], await _sample())
		_set_effect(effect, false)
		_print_sample("RD%d %s off control" % [render_distance, _effect_label(effect)], await _sample())
		_set_effect(effect, true)
	await _dispose_main()
	return {"ok": true}


func _wait_for_world_settle(world: VoxelWorld) -> bool:
	var deadline := Time.get_ticks_msec() + int(SETTLE_TIMEOUT_SECONDS * 1000.0)
	while Time.get_ticks_msec() < deadline:
		await get_tree().create_timer(0.25).timeout
		var progress := world.get_streaming_progress()
		if not _main._world_entry_waiting and world._pending.is_empty() and world._gen_queue.is_empty() \
				and world._mesh_queue.is_empty() and world._generated.is_empty() and world._commit_queue.is_empty() \
				and int(progress.get("loaded", 0)) == int(progress.get("total", -1)):
			return true
	return false


func _pin_render_state() -> void:
	var day_night := _main.get_node("DayNight") as DayNightCycle
	day_night.auto_advance = false
	day_night.set_time(NOON_HOUR)
	var camera := _main.player.camera
	# Safe-spawn selection depends on worker completion order; use the immutable
	# generator spawn instead so repeated runs use the same camera transform.
	var anchor := _main.world.get_spawn_position()
	camera.top_level = true
	camera.global_position = anchor + Vector3(0.0, 34.0, 74.0)
	camera.look_at(anchor + Vector3(0.0, 20.0, 0.0), Vector3.UP)
	camera.fov = GameConfig.get_fov()
	# Main has already applied the Medium preset to the actual scene. Pin the
	# viewport size but retain its real FSR/TAA/MSAA selection from that preset.
	get_window().size = VIEWPORT_SIZE


func _has_viewport_timing_api() -> bool:
	return ClassDB.class_has_method(&"RenderingServer", &"viewport_set_measure_render_time") \
		and ClassDB.class_has_method(&"RenderingServer", &"viewport_get_measured_render_time_cpu") \
		and ClassDB.class_has_method(&"RenderingServer", &"viewport_get_measured_render_time_gpu")


func _set_effect(effect: String, enabled: bool) -> void:
	var environment := _main.get_node("WorldEnvironment").environment as Environment
	match effect:
		"shadows":
			(_main.get_node("Sun") as DirectionalLight3D).shadow_enabled = enabled
		"ssao_ssil":
			environment.ssao_enabled = enabled
			environment.ssil_enabled = enabled
		"ssr":
			environment.ssr_enabled = enabled
		"volumetric_fog":
			environment.volumetric_fog_enabled = enabled


func _effect_label(effect: String) -> String:
	match effect:
		"shadows": return "sun shadows"
		"ssao_ssil": return "SSAO+SSIL"
		"ssr": return "SSR"
		"volumetric_fog": return "volumetric fog"
	return effect


func _sample() -> Dictionary:
	await _wait_rendered_frames(WARMUP_FRAMES)
	var wall_ms: Array[float] = []
	var cpu_ms: Array[float] = []
	var gpu_ms: Array[float] = []
	var draw_calls := 0.0
	var primitives := 0.0
	for _frame in SAMPLE_FRAMES:
		var started := Time.get_ticks_usec()
		await RenderingServer.frame_post_draw
		wall_ms.append(float(Time.get_ticks_usec() - started) / 1000.0)
		if _timing_api_available:
			cpu_ms.append(RenderingServer.viewport_get_measured_render_time_cpu(_viewport_rid))
			gpu_ms.append(RenderingServer.viewport_get_measured_render_time_gpu(_viewport_rid))
		draw_calls += float(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
		primitives += float(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))
	return {
		"wall": _summarize(wall_ms),
		"cpu": _summarize(cpu_ms),
		"gpu": _summarize(gpu_ms),
		"cpu_state": _timing_state(cpu_ms),
		"gpu_state": _timing_state(gpu_ms),
		"draw_calls": draw_calls / float(SAMPLE_FRAMES),
		"primitives": primitives / float(SAMPLE_FRAMES),
	}


func _wait_rendered_frames(frames: int) -> void:
	for _frame in frames:
		await RenderingServer.frame_post_draw


func _summarize(samples: Array[float]) -> Dictionary:
	if samples.is_empty():
		return {"p50": NAN, "p95": NAN}
	var sorted := samples.duplicate()
	sorted.sort()
	return {"p50": _percentile(sorted, 0.50), "p95": _percentile(sorted, 0.95)}


func _timing_state(samples: Array[float]) -> String:
	if not _timing_api_available:
		return "unavailable (engine lacks viewport timing API)"
	for sample in samples:
		if absf(sample) > 0.000001:
			return "measured"
	# A numeric zero is not silently called an unavailable timer. On a backend
	# without timestamps it is an ambiguous reported value and the report says so.
	return "reported-zero (API exists; backend/driver supplied 0.0)"


func _percentile(sorted: Array[float], percentile: float) -> float:
	var index := clampi(ceili(float(sorted.size()) * percentile) - 1, 0, sorted.size() - 1)
	return sorted[index]


func _print_fixture_header(render_distance: int) -> void:
	print("GAMEPLAY RENDER PROFILE")
	print("  renderer=%s driver=%s adapter=%s vendor=%s" % [
		RenderingServer.get_current_rendering_method(), RenderingServer.get_current_rendering_driver_name(),
		RenderingServer.get_video_adapter_name(), RenderingServer.get_video_adapter_vendor()])
	print("  RD%d Full Detail, unbatched, seed=%d, viewport=%s, noon=%.1f, medium preset (3D scale %.2f, TAA requested=%s, MSAA=%d)" % [
		render_distance, SEED, VIEWPORT_SIZE, NOON_HOUR, _viewport.scaling_3d_scale,
		str(_viewport.use_taa), _viewport.msaa_3d])
	print("  %d warmup + %d sampled rendered frames/phase; viewport timing API=%s" % [
		WARMUP_FRAMES, SAMPLE_FRAMES, str(_timing_api_available)])
	print("  camera transform=%s" % _main.player.camera.global_transform)


func _print_sample(label: String, sample: Dictionary) -> void:
	var wall: Dictionary = sample["wall"]
	var cpu: Dictionary = sample["cpu"]
	var gpu: Dictionary = sample["gpu"]
	print("  %s | draws %.1f primitives %.1f | viewport CPU %s %.3f/%.3f ms | GPU %s %.3f/%.3f ms | wall %.3f/%.3f ms" % [
		label, float(sample["draw_calls"]), float(sample["primitives"]), String(sample["cpu_state"]),
		float(cpu["p50"]), float(cpu["p95"]), String(sample["gpu_state"]), float(gpu["p50"]),
		float(gpu["p95"]), float(wall["p50"]), float(wall["p95"])])


func _dispose_main() -> void:
	if _timing_api_available and _viewport_rid.is_valid():
		RenderingServer.viewport_set_measure_render_time(_viewport_rid, false)
	if _main != null and is_instance_valid(_main):
		_main.queue_free()
		await get_tree().process_frame
	_main = null


func _restore_process_state() -> void:
	GameConfig.settings = _saved_game_config["settings"]
	GameConfig.graphics = _saved_game_config["graphics"]
	GameConfig.world = _saved_game_config["world"]
	GameConfig.active_world_id = String(_saved_game_config["active_world_id"])
	GameConfig.active_world_metadata = _saved_game_config["active_world_metadata"]
	GameConfig.pending_game_mode = int(_saved_game_config["pending_game_mode"])
	var window := get_window()
	window.size = _saved_window["size"]
	DisplayServer.window_set_mode(int(_saved_window["mode"]))
	DisplayServer.window_set_vsync_mode(int(_saved_window["vsync"]))
	Engine.max_fps = int(_saved_window["max_fps"])
	Input.set_mouse_mode(int(_saved_window["mouse_mode"]))
