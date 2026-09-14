class_name PhotoMode
extends Node

## F1 hides the HUD, F2 saves a clean PNG to user://screenshots/, and P swaps
## the render camera for a detached free camera. Built on the
## game/shadow_capture.gd precedent: an opt-in node added by Main that owns its
## key handling, reports through status_requested, and writes to user://.
##
## Main listens to camera_mode_changed to move world streaming, weather, and
## player control with the active camera; this node only owns presentation and
## input. mouse_sensitivity_provider is injected so the node stays free of
## autoloads and can be exercised headlessly.

signal status_requested(message: String)
signal camera_mode_changed(active: bool, camera: Camera3D)

const SCREENSHOT_ROOT := "user://screenshots"
const FREE_SPEED := 9.0
const FREE_ACCEL := 45.0
const FREE_BOOST_MULTIPLIER := 5.0
const FOV_MIN := 20.0
const FOV_MAX := 110.0
const FOV_STEP := 2.0
const PITCH_LIMIT := 1.553343
const DEFAULT_SENSITIVITY := 0.0025

var mouse_sensitivity_provider: Callable = Callable()

var _player_camera: Camera3D
var _hud_root: Control
var _camera: Camera3D
var _hud_visible := true
var _hud_restore := true
var _camera_active := false
var _capturing := false
var _velocity := Vector3.ZERO
var _yaw := 0.0
var _pitch := 0.0


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


## Binds the player camera and HUD and creates the free camera. Safe to call
## before the node enters the tree.
func initialize(player_camera: Camera3D, hud_root: Control) -> void:
	_player_camera = player_camera
	_hud_root = hud_root
	_camera = Camera3D.new()
	_camera.name = "FreeCamera"
	_camera.current = false
	add_child(_camera)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("hud_toggle"):
		get_viewport().set_input_as_handled()
		toggle_hud()
		return
	if event.is_action_pressed("screenshot"):
		get_viewport().set_input_as_handled()
		capture_screenshot()
		return
	if event.is_action_pressed("photo_camera"):
		if not get_tree().paused:
			get_viewport().set_input_as_handled()
			set_free_camera(not _camera_active)
		return
	if not _camera_active:
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		set_free_camera(false)
		return
	# The player node is frozen, but keep its interactions from reopening under
	# the detached camera.
	if event.is_action_pressed("inventory"):
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_look(event.relative)
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			get_viewport().set_input_as_handled()
			_zoom(-FOV_STEP)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			get_viewport().set_input_as_handled()
			_zoom(FOV_STEP)


func _process(delta: float) -> void:
	if not _camera_active or get_tree().paused:
		return
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var wish := _camera.global_transform.basis * Vector3(input.x, 0.0, input.y)
	var vertical := Input.get_action_strength("fly_up") - Input.get_action_strength("fly_down")
	wish += Vector3.UP * vertical
	if wish.length_squared() > 1.0:
		wish = wish.normalized()
	var boost := FREE_BOOST_MULTIPLIER if Input.is_action_pressed("fly_boost") else 1.0
	_apply_free_movement(wish, boost, delta)


## Frame-rate independent free movement, separate from Input so the headless
## verifier can drive it directly.
func _apply_free_movement(direction: Vector3, boost: float, delta: float) -> void:
	if _camera == null:
		return
	var speed := FREE_SPEED * boost
	var accel := FREE_ACCEL * boost
	_velocity.x = move_toward(_velocity.x, direction.x * speed, accel * delta)
	_velocity.y = move_toward(_velocity.y, direction.y * speed, accel * delta)
	_velocity.z = move_toward(_velocity.z, direction.z * speed, accel * delta)
	_camera.global_position += _velocity * delta


func _look(relative: Vector2) -> void:
	if _camera == null:
		return
	var sensitivity := DEFAULT_SENSITIVITY
	if mouse_sensitivity_provider.is_valid():
		sensitivity = float(mouse_sensitivity_provider.call())
	_yaw = wrapf(_yaw - relative.x * sensitivity, -PI, PI)
	_pitch = clampf(_pitch - relative.y * sensitivity, -PITCH_LIMIT, PITCH_LIMIT)
	_camera.rotation = Vector3(_pitch, _yaw, 0.0)


func _zoom(amount: float) -> void:
	if _camera == null:
		return
	_camera.fov = clampf(_camera.fov + amount, FOV_MIN, FOV_MAX)


func toggle_hud() -> void:
	set_hud_visible(not _hud_visible)


func set_hud_visible(visible: bool) -> void:
	_hud_visible = visible
	if _camera_active:
		# F1 inside photo mode is an explicit choice; keep it after exiting.
		_hud_restore = visible
	_apply_hud(visible)
	status_requested.emit("HUD %s — F1 toggles" % ("shown" if visible else "hidden"))


func is_hud_visible() -> bool:
	return _hud_visible


func set_free_camera(active: bool) -> void:
	if active == _camera_active or _camera == null or _player_camera == null:
		return
	_velocity = Vector3.ZERO
	if active:
		_hud_restore = _hud_visible
		_hud_visible = false
		_apply_hud(false)
		_camera.fov = _player_camera.fov
		_camera.far = _player_camera.far
		_camera.global_transform = _player_camera.global_transform
		_yaw = _camera.rotation.y
		_pitch = _camera.rotation.x
		_camera.current = true
		_player_camera.current = false
		_camera_active = true
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		status_requested.emit("Photo camera — WASD fly · SPACE/SHIFT up/down · CTRL boost · wheel zoom · ESC exit")
	else:
		_camera_active = false
		_camera.current = false
		_player_camera.current = true
		# The entry overwrote _hud_visible; re-sync it with the restored state
		# or the next F1/F2 would act on a stale value.
		_hud_visible = _hud_restore
		_apply_hud(_hud_restore)
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		status_requested.emit("Photo camera closed")
	camera_mode_changed.emit(active, _camera)


func is_camera_active() -> bool:
	return _camera_active


func get_camera() -> Camera3D:
	return _camera


## Captures the current frame without the HUD or any CanvasLayer UI so shots
## stay clean even when F1 left the interface visible or a modal is open. The
## one-frame hide is restored before the PNG is written, so the status toast
## and menus appear normally afterwards.
func capture_screenshot() -> void:
	if _capturing:
		return
	_capturing = true
	_apply_hud(false)
	var hidden_layers := _hide_canvas_layers()
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	_restore_canvas_layers(hidden_layers)
	_apply_hud(_hud_visible)
	if image == null or image.is_empty():
		_capturing = false
		status_requested.emit("Screenshot failed: viewport readback returned no image")
		return
	var error := DirAccess.make_dir_recursive_absolute(SCREENSHOT_ROOT)
	if error != OK:
		_capturing = false
		status_requested.emit("Screenshot failed: cannot create %s (%s)" % [SCREENSHOT_ROOT, error_string(error)])
		return
	var stamp := Time.get_datetime_string_from_system().replace(":", "-")
	var path := screenshot_path(SCREENSHOT_ROOT, stamp)
	error = image.save_png(path)
	_capturing = false
	if error != OK:
		status_requested.emit("Screenshot failed: PNG write error (%s)" % error_string(error))
		return
	print("Screenshot saved: ", ProjectSettings.globalize_path(path))
	status_requested.emit("Screenshot saved — %s" % path.get_file())


## Hides every visible CanvasLayer (HUD, pause menu, inventory, overlays) for
## the readback frame and returns the hidden set so the caller can restore it.
## Walking the tree keeps the node independent of which overlays Main owns.
func _hide_canvas_layers() -> Array[CanvasLayer]:
	var hidden: Array[CanvasLayer] = []
	_collect_hidden_layers(get_tree().root, hidden)
	return hidden


func _collect_hidden_layers(node: Node, hidden: Array[CanvasLayer]) -> void:
	for child in node.get_children():
		if child is CanvasLayer:
			var layer := child as CanvasLayer
			if layer.visible:
				layer.visible = false
				hidden.append(layer)
		_collect_hidden_layers(child, hidden)


func _restore_canvas_layers(hidden: Array[CanvasLayer]) -> void:
	for layer in hidden:
		if is_instance_valid(layer):
			layer.visible = true


## Timestamped path that never overwrites an existing capture. Static so the
## headless verifier can check naming without a renderer.
static func screenshot_path(directory: String, stamp: String) -> String:
	var path := "%s/screenshot_%s.png" % [directory, stamp]
	var suffix := 1
	while FileAccess.file_exists(path):
		suffix += 1
		path = "%s/screenshot_%s_%d.png" % [directory, stamp, suffix]
	return path


func _apply_hud(visible: bool) -> void:
	if _hud_root != null:
		_hud_root.visible = visible
