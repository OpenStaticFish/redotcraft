## Focused headless check for the read-only world-entry progress presentation.
## Run:
##   redot --headless --path . --script res://tools/loading_progress_verify.gd
extends SceneTree

var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var main_source := FileAccess.get_file_as_string("res://game/main.gd")
	_expect(main_source.contains("_pending_death_cause = \"Saved expedition\"")
		and main_source.contains("_photo_mode.set_process_unhandled_input(not _world_entry_waiting)")
		and main_source.contains("_photo_mode.set_process_unhandled_input(true)"),
		"world entry does not defer saved death or lock photo-mode input")
	var overlay: Control = load("res://ui/loading_overlay.gd").new()
	root.add_child(overlay)
	await process_frame
	overlay.set_progress({
		"loaded": 7, "total": 4225, "pending": 8, "queued": 4210,
		"generated": 4, "spawn_collision": 3, "spawn_total": 9,
		"initial_ready": false, "streaming": true,
	})
	_expect(overlay.get_node("Center/Panel/Box/Phase").text == "Preparing a safe spawn",
		"unsafe spawn phase was not shown")
	_expect("3 / 9" in overlay.get_node("Center/Panel/Box/ProgressText").text,
		"spawn collision progress missing")
	overlay.set_progress({
		"loaded": 1234, "total": 4225, "pending": 8, "queued": 2000,
		"generated": 6, "spawn_collision": 9, "spawn_total": 9,
		"initial_ready": true, "streaming": true,
	})
	_expect(overlay.get_node("Center/Panel/Box/Phase").text == "Spawn ready",
		"ready spawn did not transition to background streaming")
	_expect("1234 / 4225" in overlay.get_node("Center/Panel/Box/ProgressText").text,
		"high-distance horizon progress missing")
	overlay.complete()
	_expect(overlay.mouse_filter == Control.MOUSE_FILTER_IGNORE,
		"completed overlay still intercepts gameplay input")
	if _failures > 0:
		push_error("loading progress verifier failed: %d assertion(s)" % _failures)
		quit(1)
	else:
		print("loading progress verifier passed")
		quit(0)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
