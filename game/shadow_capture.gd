extends Node

## Opt-in lossless capture of the user's actual scene, including while paused.
signal status_requested(message: String)

const FRAME_COUNT := 30
const SAMPLE_INTERVAL_MS := 67
const OUTPUT_ROOT := "user://shadow_captures"

var state_provider: Callable
var _capturing := false


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F9:
		get_viewport().set_input_as_handled()
		if not _capturing:
			capture()


func capture() -> void:
	if _capturing or not state_provider.is_valid():
		return
	_capturing = true
	var directory := "%s/%d_%d" % [OUTPUT_ROOT, int(Time.get_unix_time_from_system()), Time.get_ticks_msec()]
	var error := DirAccess.make_dir_recursive_absolute(directory)
	if error != OK:
		_finish("Shadow capture: cannot create output directory (%s)" % error_string(error))
		return
	status_requested.emit("Recording shadow frames — keep this view still for two seconds")
	var report: Dictionary = {"initial_state": state_provider.call(), "frames": []}
	var images: Array[Image] = []
	var next_sample_ms := Time.get_ticks_msec()
	while images.size() < FRAME_COUNT:
		await RenderingServer.frame_post_draw
		if Time.get_ticks_msec() < next_sample_ms:
			continue
		var image := get_viewport().get_texture().get_image()
		if image == null or image.is_empty():
			_finish("Shadow capture: viewport readback failed")
			return
		report["frames"].append({"ticks_ms": Time.get_ticks_msec(), "state": state_provider.call()})
		images.append(image)
		next_sample_ms = Time.get_ticks_msec() + SAMPLE_INTERVAL_MS
	# Keep PNG compression out of the sampling interval.
	status_requested.emit("Saving shadow capture…")
	for i in images.size():
		error = images[i].save_png("%s/frame_%03d.png" % [directory, i])
		if error != OK:
			_finish("Shadow capture: PNG write failed (%s)" % error_string(error))
			return
	var file := FileAccess.open(directory + "/state.json", FileAccess.WRITE)
	if file == null:
		_finish("Shadow capture: cannot write state.json")
		return
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	var absolute_path := ProjectSettings.globalize_path(directory)
	print("Shadow capture saved: ", absolute_path)
	_finish("Shadow capture saved in user://shadow_captures (F9 to capture again)")


func _finish(message: String) -> void:
	_capturing = false
	status_requested.emit(message)
