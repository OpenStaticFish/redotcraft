## Headless regression check for photo mode: HUD toggle state, detached camera
## handoff, mouse look and movement, screenshot naming, and the input bindings.
## Run:
##   redot --headless --path . --script res://tools/photo_mode_verify.gd
##
## PhotoMode takes all of its dependencies as arguments (no autoloads), so a
## --script SceneTree can exercise it directly. Screenshots themselves need a
## renderer and are covered by the naming helper plus a live pass instead.
extends SceneTree

var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var root_node := Node3D.new()
	root.add_child(root_node)
	var player := Node3D.new()
	player.name = "Player"
	root_node.add_child(player)
	var player_camera := Camera3D.new()
	player_camera.fov = 76.0
	player_camera.far = 500.0
	player.add_child(player_camera)
	player_camera.global_position = Vector3(4.0, 5.0, 6.0)
	var hud := Control.new()
	hud.name = "HudRoot"
	root_node.add_child(hud)

	var photo := PhotoMode.new()
	photo.initialize(player_camera, hud)
	photo.mouse_sensitivity_provider = func() -> float: return 0.0025
	root_node.add_child(photo)

	# HUD toggle keeps the root visibility and the tracked state in sync.
	_expect(photo.is_hud_visible(), "HUD should start visible")
	photo.toggle_hud()
	_expect(not photo.is_hud_visible() and not hud.visible, "toggle should hide the HUD root")
	photo.toggle_hud()
	_expect(photo.is_hud_visible() and hud.visible, "toggle should restore the HUD root")

	# Detached camera handoff inherits the player pose and hides the HUD.
	photo.set_free_camera(true)
	_expect(photo.is_camera_active(), "free camera did not activate")
	_expect(photo.get_camera() != null, "free camera was not created")
	_expect(photo.get_camera().current, "free camera is not current")
	_expect(not player_camera.current, "player camera stayed current")
	_expect(not hud.visible, "entering photo mode should hide the HUD")
	_expect(photo.get_camera().global_position.is_equal_approx(player_camera.global_position),
		"free camera did not start at the player camera")
	_expect(is_equal_approx(photo.get_camera().fov, player_camera.fov),
		"free camera did not inherit the player FOV")

	# Mouse look turns the camera and clamps pitch.
	var before := photo.get_camera().rotation
	photo._look(Vector2(10.0, -5.0))
	_expect(photo.get_camera().rotation.y < before.y, "look did not yaw the camera")
	_expect(photo.get_camera().rotation.x > before.x, "look did not pitch the camera")
	for i in 200:
		photo._look(Vector2(0.0, -50.0))
	_expect(absf(photo.get_camera().rotation.x) <= PhotoMode.PITCH_LIMIT + 0.001,
		"pitch was not clamped")
	photo._look(Vector2(0.0, 100000.0))
	_expect(absf(photo.get_camera().rotation.x) <= PhotoMode.PITCH_LIMIT + 0.001,
		"pitch was not clamped downward")

	# Free movement and boost.
	var start := photo.get_camera().global_position
	photo._apply_free_movement(Vector3.FORWARD, 1.0, 0.25)
	var normal_step := photo.get_camera().global_position.distance_to(start)
	_expect(normal_step > 0.0, "free camera did not move")
	photo._velocity = Vector3.ZERO
	var boosted_start := photo.get_camera().global_position
	photo._apply_free_movement(Vector3.FORWARD, PhotoMode.FREE_BOOST_MULTIPLIER, 0.25)
	_expect(photo.get_camera().global_position.distance_to(boosted_start) > normal_step,
		"boost should move the free camera faster")

	# Wheel zoom clamps to the FOV range.
	for i in 200:
		photo._zoom(-PhotoMode.FOV_STEP)
	_expect(is_equal_approx(photo.get_camera().fov, PhotoMode.FOV_MIN), "zoom-in did not clamp")
	for i in 200:
		photo._zoom(PhotoMode.FOV_STEP)
	_expect(is_equal_approx(photo.get_camera().fov, PhotoMode.FOV_MAX), "zoom-out did not clamp")

	# Exiting restores the player camera and the HUD state from before entry.
	photo.set_free_camera(false)
	_expect(not photo.is_camera_active(), "free camera did not deactivate")
	_expect(player_camera.current, "player camera did not become current again")
	_expect(hud.visible, "exiting photo mode should restore the HUD")

	# F1 inside photo mode is an explicit choice and survives the exit.
	photo.set_free_camera(true)
	_expect(not hud.visible, "HUD should hide again on the next entry")
	photo.toggle_hud()
	_expect(photo.is_hud_visible() and hud.visible, "F1 should show the HUD in photo mode")
	photo.set_free_camera(false)
	_expect(photo.is_hud_visible() and hud.visible, "exiting should keep the F1 choice")

	# Key bindings route through the InputMap actions.
	for action in ["hud_toggle", "screenshot", "photo_camera"]:
		_expect(InputMap.has_action(action), "missing input action %s" % action)
	if InputMap.has_action("hud_toggle"):
		var events := InputMap.action_get_events("hud_toggle")
		_expect(events.size() == 1 and events[0].keycode == KEY_F1, "hud_toggle should be F1")
	if InputMap.has_action("screenshot"):
		var events := InputMap.action_get_events("screenshot")
		_expect(events.size() == 1 and events[0].keycode == KEY_F2, "screenshot should be F2")
	if InputMap.has_action("photo_camera"):
		var events := InputMap.action_get_events("photo_camera")
		_expect(events.size() == 1 and events[0].physical_keycode == KEY_P, "photo_camera should be P")
	_send_action("hud_toggle")
	await process_frame
	_expect(not photo.is_hud_visible() and not hud.visible, "hud_toggle action did not hide the HUD")
	_send_action("hud_toggle")
	await process_frame
	_expect(photo.is_hud_visible(), "hud_toggle action did not restore the HUD")
	_send_action("photo_camera")
	await process_frame
	_expect(photo.is_camera_active(), "photo_camera action did not activate the free camera")
	_send_action("photo_camera")
	await process_frame
	_expect(not photo.is_camera_active(), "photo_camera action did not deactivate the free camera")

	# Screenshot paths are timestamped and never overwrite.
	var directory := "user://photo_mode_verify"
	DirAccess.make_dir_recursive_absolute(directory)
	var stamp := "verify-%d" % Time.get_ticks_msec()
	var first_path := PhotoMode.screenshot_path(directory, stamp)
	_expect(first_path.ends_with("screenshot_%s.png" % stamp), "screenshot path lost its timestamp")
	var file := FileAccess.open(first_path, FileAccess.WRITE)
	_expect(file != null, "could not create a placeholder screenshot")
	if file != null:
		file.store_string("placeholder")
		file.close()
	var second_path := PhotoMode.screenshot_path(directory, stamp)
	_expect(second_path != first_path, "screenshot path should get a suffix instead of overwriting")
	_expect(second_path.ends_with("_2.png"), "screenshot suffix should be numeric")
	DirAccess.remove_absolute(first_path)

	if _failures == 0:
		print("PHOTO MODE VERIFY: PASS")
		quit(0)
		return
	print("PHOTO MODE VERIFY: FAIL (%d)" % _failures)
	quit(1)


func _send_action(action: String) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	event = InputEventAction.new()
	event.action = action
	event.pressed = false
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("photo_mode_verify: %s" % message)
