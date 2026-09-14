## Headless check for the in-game map surfaces: the HUD minimap and the full
## map overlay follow the worldgen overlay's mode list, share the view
## projection, and pack map colors as RGBA8. The overlay's pause ownership and
## its zoom/pan view model are covered here too.
## Run:
##   redot --headless --path . --script res://tools/map_verify.gd
##
## Nodes stay untyped and scenes are loaded at runtime: a --script SceneTree
## parses before autoloads exist, so naming UI classes at parse time fails.
extends SceneTree

var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var overlay_script: GDScript = load("res://ui/worldgen_overlay.gd")
	var view_script: GDScript = load("res://ui/map_view.gd")
	var expected_modes: Array = overlay_script.MAP_MODES

	var minimap: Node = _add_scene("res://ui/minimap.tscn")
	_expect(minimap != null, "minimap scene failed to load")
	var map_overlay: Node = _add_scene("res://ui/map_overlay.tscn")
	_expect(map_overlay != null, "map overlay scene failed to load")
	await process_frame
	if minimap == null or map_overlay == null:
		_finish()
		return

	_expect(minimap.get_mode() == expected_modes[0], "minimap did not start on the biome map")
	_expect(map_overlay.get_mode() == expected_modes[0], "map overlay did not start on the biome map")
	for index in expected_modes.size():
		_expect(minimap.get_mode() == expected_modes[index],
			"minimap cycle %d produced %s, expected %s" % [index, minimap.get_mode(), expected_modes[index]])
		_expect(map_overlay.get_mode() == expected_modes[index],
			"map overlay cycle %d produced %s, expected %s" % [index, map_overlay.get_mode(), expected_modes[index]])
		minimap.cycle_mode()
		map_overlay.cycle_mode()
	_expect(minimap.get_mode() == expected_modes[0], "minimap mode cycle did not wrap")
	_expect(map_overlay.get_mode() == expected_modes[0], "map overlay mode cycle did not wrap")

	# Shared view projection: the view center is the rect center, the view
	# origin corner is the rect top-left, and off-view points hide the marker.
	var view_center := Vector2(100.0, -40.0)
	var view_span := 256.0
	var display := Vector2(496.0, 496.0)
	var middle: Vector2 = view_script.world_to_view(100.5, -39.5, view_center, view_span, display)
	_expect(middle.distance_to(display * 0.5) < 2.0, "view center projected to %s" % str(middle))
	var corner: Vector2 = view_script.world_to_view(-28.0, -168.0, view_center, view_span, display)
	_expect(corner.distance_to(Vector2.ZERO) < 0.01, "view origin projected to %s" % str(corner))
	var outside: Vector2 = view_script.world_to_view(-29.0, -168.0, view_center, view_span, display)
	_expect(not view_script.visible_in_view(outside, display), "off-view position should hide the marker")
	_expect(view_script.visible_in_view(Vector2.ZERO, display), "view corner should be visible")
	var unset: Vector2 = view_script.world_to_view(0.0, 0.0, Vector2.ZERO, 0.0, display)
	_expect(not view_script.visible_in_view(unset, display), "empty span should hide the marker")

	# Color packing: one RGBA8 byte per channel, rounded.
	var packed: PackedByteArray = view_script.to_rgba8(PackedColorArray([
		Color(1.0, 0.5, 0.0, 1.0), Color(0.0, 0.0, 0.0, 0.0)]))
	_expect(packed.size() == 8, "rgba8 packing produced %d bytes" % packed.size())
	_expect(packed[0] == 255 and packed[1] == 128 and packed[2] == 0 and packed[3] == 255
		and packed[4] == 0 and packed[7] == 0, "rgba8 packing values were %s" % str(packed))

	# Minimap is a passive HUD layer: starts hidden and only flips visibility.
	_expect(not minimap.visible, "minimap should start hidden")
	minimap.toggle()
	_expect(minimap.visible, "toggle did not show the minimap")
	minimap.toggle()
	_expect(not minimap.visible, "toggle did not hide the minimap")

	# The full map owns the pause state while it is open and gives its surface
	# the modal focus owner.
	_expect(not map_overlay.visible, "map overlay should start hidden")
	map_overlay.open()
	await process_frame
	_expect(map_overlay.visible, "open() did not show the map overlay")
	_expect(paused, "open() should pause the tree")
	_expect(map_overlay._map_clip.focus_mode == Control.FOCUS_ALL,
		"atlas map surface is not focusable")
	_expect(root.gui_get_focus_owner() == map_overlay._map_clip,
		"open() did not give the atlas surface focus")
	map_overlay.cycle_mode()
	_expect(map_overlay.get_mode() == expected_modes[1], "map overlay did not cycle while open")
	map_overlay.close()
	await process_frame
	_expect(not map_overlay.visible and not paused, "close() did not restore the tree")

	# The overlay view model: key zoom shrinks the span, left-drag pans 1:1,
	# held arrows pan continuously, and zoom clamps at the span limits.
	map_overlay.open()
	await process_frame
	await process_frame
	_expect(map_overlay._map_clip.size.x >= 1.0, "map clip did not lay out")
	var zoom_in := InputEventAction.new()
	zoom_in.action = "map_zoom_in"
	zoom_in.pressed = true
	map_overlay._unhandled_input(zoom_in)
	_expect(map_overlay._view_span_target < 512.0, "map_zoom_in did not shrink the view span")
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = map_overlay._map_clip.global_position + map_overlay._map_clip.size * 0.5
	map_overlay._input(press)
	_expect(map_overlay._dragging, "left press on the map did not start a drag")
	var before: Vector2 = map_overlay._view_center
	var motion := InputEventMouseMotion.new()
	motion.position = press.position + Vector2(60.0, 0.0)
	map_overlay._input(motion)
	_expect(map_overlay._view_center.x < before.x - 1.0, "rightward drag did not pan the view west")
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = motion.position
	map_overlay._input(release)
	_expect(not map_overlay._dragging, "release did not end the drag")
	var pan_before: Vector2 = map_overlay._view_center
	Input.action_press("ui_right")
	for index in 3:
		await process_frame
	Input.action_release("ui_right")
	_expect(map_overlay._view_center.x > pan_before.x + 1.0, "held ui_right did not pan the view east")
	for index in 40:
		map_overlay._zoom_at(map_overlay._map_clip.size * 0.5, 1.0 / 1.25)
	_expect(is_equal_approx(map_overlay._view_span_target, 128.0),
		"zoom-in target did not clamp at the minimum span")
	map_overlay.close()
	await process_frame

	# Raster convergence: the staleness check must compare the view against the
	# span the request will actually bake (whole strides), not the unquantized
	# target. At the minimum span the old comparison never matched, so the
	# atlas rebuilt its texture every idle frame.
	map_overlay.open()
	await process_frame
	await process_frame
	map_overlay._view_span = 128.0
	map_overlay._view_span_target = 128.0
	var min_stride: int = map_overlay._raster_stride()
	_expect(min_stride == 2, "minimum-span raster stride changed")
	map_overlay._zooming = false
	map_overlay._baked_mode = map_overlay.get_mode()
	map_overlay._baked_center = map_overlay._view_center
	map_overlay._baked_span = float(128 * min_stride)
	map_overlay._baked_stride = min_stride
	map_overlay._has_raster = true
	_expect(not map_overlay._needs_raster(),
		"quantized raster span should satisfy the staleness check at minimum zoom")
	map_overlay._baked_span += 128.0
	_expect(map_overlay._needs_raster(),
		"a raster one stride step off should still be considered stale")
	map_overlay._has_raster = false
	map_overlay.close()
	await process_frame

	_finish()


func _add_scene(path: String) -> Node:
	var scene: PackedScene = load(path)
	if scene == null:
		return null
	var node: Node = scene.instantiate()
	root.add_child(node)
	return node


func _finish() -> void:
	if _failures == 0:
		print("MAP VERIFY: PASS")
		quit(0)
		return
	print("MAP VERIFY: FAIL (%d)" % _failures)
	quit(1)


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("map_verify: %s" % message)
