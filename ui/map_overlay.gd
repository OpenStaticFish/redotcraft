class_name MapOverlay
extends CanvasLayer
## Full-screen interactive map (M) that expands the HUD minimap's
## WorldgenOverlay modes into a large, zoomable atlas.
##
## View model: `_view_center`/`_view_span` describe the world square mapped
## onto the map frame, so the player marker and any baked raster are positioned
## through the same north-up transform (`ui/map_view.gd`). The wheel zooms
## around the cursor with a short exponential settle, and left-drag pans 1:1
## with the pointer; both update the view immediately and only schedule a new
## worker raster once the gesture settles (or, while dragging, once the view
## leaves the baked coverage), so interaction never waits on sampling.
##
## Modal by construction: while open it pauses the tree and frees the mouse,
## and it owns ui_cancel plus the map keys itself because Main cannot process
## input while paused. Opening the inventory closes it first so exactly one
## screen owns the pause state.
##
## Wired by game/main.gd:
##   var overlay: MapOverlay = MapOverlayScene.instantiate()
##   add_child(overlay)
##   overlay.initialize(world, player)
## Main calls open() on the `map_overlay` action.

signal closed

const MAP_MODES: Array[String] = WorldgenOverlay.MAP_MODES

const MAP_SAMPLES := 128
const MAP_DETAIL := 128
const VIEW_MIN_SPAN := 128.0
const VIEW_MAX_SPAN := 1536.0
const VIEW_DEFAULT_SPAN := 512.0
## Rasters cover more than the visible view so panning stays filled between
## resamples.
const RASTER_MARGIN := 1.5
const RASTER_SPAN_TOLERANCE := 0.25
const RASTER_PAN_THRESHOLD := 0.15
const ZOOM_STEP := 1.25
const ZOOM_SMOOTH_RATE := 16.0
## Arrow-key pan speed, in view spans per second.
const PAN_SPAN_PER_SECOND := 0.9
const SETTLE_SECONDS := 0.15
const REFRESH_INTERVAL := 0.25
const MAP_PADDING_X := 96.0
const MAP_PADDING_Y := 220.0
const MAP_MIN_SIZE := 320.0
const MAP_MAX_SIZE := 640.0

var _world: VoxelWorld
var _player: Player
var _mode_index := 0
var _view_center := Vector2.ZERO
var _view_span := VIEW_DEFAULT_SPAN
var _view_span_target := VIEW_DEFAULT_SPAN
var _zooming := false
var _zoom_anchor_screen := Vector2.ZERO
var _zoom_anchor_world := Vector2.ZERO
var _dragging := false
var _panning := false
var _drag_screen := Vector2.ZERO
var _drag_center := Vector2.ZERO
var _settle := 0.0
var _refresh_accum := 0.0
var _map_pending := false
var _has_raster := false
var _baked_center := Vector2.ZERO
var _baked_span := 0.0
var _baked_mode := ""
var _baked_stride := 0
var _caption_span := 0
var _dim: ColorRect
var _panel: PanelContainer
var _mode_label: Label
var _map_clip: Control
var _map_image: TextureRect
var _marker: Node2D
var _caption: Label
var _position_label: Label


func _ready() -> void:
	_build_ui()
	visible = false
	get_viewport().size_changed.connect(_on_viewport_resized)


func initialize(world: VoxelWorld, player: Player) -> void:
	_world = world
	_player = player


func open() -> void:
	if visible:
		return
	visible = true
	get_tree().paused = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_apply_size()
	Motion.dim_in(_dim)
	Motion.pop_in(_panel)
	_focus_player()
	_update_header()
	# The map surface is the modal's focus owner so ui_cancel/focus routing has
	# a concrete target, matching the other modals.
	_map_clip.grab_focus()
	_request_raster()


func close() -> void:
	if not visible:
		return
	visible = false
	_dragging = false
	_zooming = false
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	get_tree().paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	closed.emit()


func cycle_mode() -> void:
	_mode_index = wrapi(_mode_index + 1, 0, MAP_MODES.size())
	_update_header()
	if visible:
		_settle = SETTLE_SECONDS


func get_mode() -> String:
	return MAP_MODES[_mode_index]


func is_pending() -> bool:
	return _map_pending


func get_view_span() -> float:
	return _view_span


## Centers on the player at the default zoom. Called on every open so a stale
## pan from a previous visit never reappears.
func _focus_player() -> void:
	if _player == null:
		return
	_view_center = Vector2(floori(_player.global_position.x), floori(_player.global_position.z))
	_view_span = VIEW_DEFAULT_SPAN
	_view_span_target = VIEW_DEFAULT_SPAN
	_zooming = false
	_dragging = false
	_panning = false
	_settle = 0.0


## Mouse gestures live in `_input` so the modal dim cannot swallow them before
## the overlay sees them; keys stay in `_unhandled_input` for cancel routing.
func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_zoom_at(event.position, 1.0 / ZOOM_STEP)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_zoom_at(event.position, ZOOM_STEP)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed and _map_clip.get_global_rect().has_point(event.position):
				_begin_drag(event.position)
				get_viewport().set_input_as_handled()
			elif not event.pressed and _dragging:
				_end_drag()
				get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _dragging:
		var display := _map_clip.size
		if display.x > 0.0:
			var per_pixel := _view_span / display.x
			_view_center = _drag_center - (event.position - _drag_screen) * per_pixel
			_settle = SETTLE_SECONDS
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("map_overlay") or event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("minimap_mode"):
		cycle_mode()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("map_zoom_in"):
		_zoom_at_view_center(1.0 / ZOOM_STEP)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("map_zoom_out"):
		_zoom_at_view_center(ZOOM_STEP)
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not visible:
		return
	_animate_zoom(delta)
	# Arrow keys pan continuously at a speed proportional to the current zoom.
	var pan := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	_panning = pan.length_squared() > 0.0
	if _panning:
		_view_center += pan * (_view_span * PAN_SPAN_PER_SECOND) * delta
	_update_view()
	if _map_pending:
		_refresh_accum += delta
		if _refresh_accum >= REFRESH_INTERVAL:
			_refresh_accum = 0.0
			_request_raster()
		return
	if _zooming:
		return
	if _dragging or _panning:
		if _needs_raster():
			_request_raster()
		return
	if _settle > 0.0:
		_settle -= delta
		return
	if _needs_raster():
		_request_raster()


func _begin_drag(screen_position: Vector2) -> void:
	_view_span = _view_span_target
	_zooming = false
	_dragging = true
	_drag_screen = screen_position
	_drag_center = _view_center
	Input.set_default_cursor_shape(Input.CURSOR_MOVE)


func _end_drag() -> void:
	_dragging = false
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	_settle = SETTLE_SECONDS


## Zooms around the cursor: the world point under the pointer stays put while
## `_view_span` eases toward the new target in `_animate_zoom`.
func _zoom_at(screen_position: Vector2, factor: float) -> void:
	var display := _map_clip.size
	if display.x < 1.0 or display.y < 1.0:
		return
	var point := screen_position - _map_clip.global_position
	point.x = clampf(point.x, 0.0, display.x)
	point.y = clampf(point.y, 0.0, display.y)
	_zoom_anchor_screen = point
	_zoom_anchor_world = _view_center + (point - display * 0.5) / display * _view_span
	_view_span_target = clampf(_view_span_target * factor, VIEW_MIN_SPAN, VIEW_MAX_SPAN)
	_zooming = not is_equal_approx(_view_span_target, _view_span)
	_settle = SETTLE_SECONDS


## Keyboard zoom anchor: the middle of the frame.
func _zoom_at_view_center(factor: float) -> void:
	_zoom_at(_map_clip.global_position + _map_clip.size * 0.5, factor)


func _animate_zoom(delta: float) -> void:
	if not _zooming:
		return
	_view_span = lerpf(_view_span, _view_span_target, 1.0 - exp(-delta * ZOOM_SMOOTH_RATE))
	if absf(_view_span - _view_span_target) <= _view_span_target * 0.002:
		_view_span = _view_span_target
		_zooming = false
		_settle = SETTLE_SECONDS
	var display := _map_clip.size
	if display.x > 0.0:
		_view_center = _zoom_anchor_world - (_zoom_anchor_screen - display * 0.5) / display * _view_span


## Places the baked raster and the marker through the current view transform.
## Runs every frame; only string formatting is throttled by the span guard.
func _update_view() -> void:
	if _map_clip == null:
		return
	var display := _map_clip.size
	if display.x < 1.0 or display.y < 1.0:
		return
	if _has_raster:
		var half := _baked_span * 0.5
		var top_left := MapView.world_to_view(
			_baked_center.x - half, _baked_center.y - half,
			_view_center, _view_span, display)
		var pixels := _baked_span / _view_span * display.x
		_map_image.position = top_left
		_map_image.size = Vector2(pixels, pixels)
		_update_caption()
	if _player == null:
		return
	var point := MapView.world_to_view(
		_player.global_position.x, _player.global_position.z,
		_view_center, _view_span, display)
	_marker.visible = MapView.visible_in_view(point, display)
	if not _marker.visible:
		return
	_marker.position = point
	_marker.rotation = -_player.global_rotation.y


func _update_caption() -> void:
	if _map_pending or not _has_raster:
		return
	var span_blocks := roundi(_view_span)
	if span_blocks == _caption_span:
		return
	_caption_span = span_blocks
	_caption.text = "%d b across  ·  1 px = %d b" % [span_blocks, maxi(_baked_stride, 1)]


## A raster is stale when the mode changed, the view outgrew its coverage, or
## the view center drifted past the margin the raster was expanded with.
##
## The span check compares against the span the request will actually bake, not
## the raw target: the world API quantizes pixels to whole strides, so the
## produced span is always MAP_SAMPLES * stride. Comparing the unquantized
## target would never converge at deep zoom (where one stride step exceeds the
## tolerance) and would rebuild the texture every frame.
func _needs_raster() -> bool:
	if not _has_raster:
		return true
	if _baked_mode != MAP_MODES[_mode_index]:
		return true
	var quantized := float(MAP_SAMPLES * _raster_stride())
	if absf(_baked_span - quantized) > quantized * RASTER_SPAN_TOLERANCE:
		return true
	return (_view_center - _baked_center).length() > _baked_span * RASTER_PAN_THRESHOLD


## Stride the next request will ask for; shared so the staleness check and the
## request can never disagree about the baked span.
func _raster_stride() -> int:
	return clampi(roundi(_view_span * RASTER_MARGIN / float(MAP_SAMPLES)), 1, 32)


## Starts or polls the worker raster for the current view; the world API keeps
## a single diagnostic task in flight, so callers poll while it is pending.
func _request_raster() -> void:
	if _player == null or _world == null:
		_caption.text = "initialize(world, player) pending"
		return
	if not _world.has_method("request_debug_map"):
		_caption.text = "request_debug_map() unavailable on VoxelWorld"
		return
	var center := Vector2i(roundi(_view_center.x), roundi(_view_center.y))
	var stride := _raster_stride()
	var payload: Variant = _world.call(
		"request_debug_map", MAP_MODES[_mode_index], center, MAP_SAMPLES, stride, MAP_DETAIL)
	if not (payload is Dictionary):
		_caption.text = "map unavailable"
		return
	var dictionary: Dictionary = payload
	if bool(dictionary.get("pending", false)):
		_map_pending = true
		_caption.text = "%s sampling…" % MAP_MODES[_mode_index].to_upper()
		return
	var texture := MapView.texture_from_payload(dictionary)
	if texture == null:
		_map_pending = false
		_caption.text = "invalid map payload"
		return
	_map_pending = false
	_map_image.texture = texture
	var payload_stride := int(dictionary.get("stride", stride))
	_baked_center = Vector2(center)
	_baked_span = float(int(dictionary.get("width", 0)) * payload_stride)
	_baked_mode = MAP_MODES[_mode_index]
	_baked_stride = payload_stride
	_has_raster = true
	_caption_span = 0
	_update_caption()
	_position_label.text = "%s  ·  XYZ %d %d %d" % [
		_world.get_biome_name(_player.global_position),
		floori(_player.global_position.x),
		floori(_player.global_position.y),
		floori(_player.global_position.z)]
	_update_view()


func _update_header() -> void:
	if _mode_label == null:
		return
	_mode_label.text = "%s  %d/%d" % [
		MAP_MODES[_mode_index].to_upper(), _mode_index + 1, MAP_MODES.size()]


## Fits the square map to the viewport; rounded to a multiple of 16 so the
## stretched texel grid stays crisp at both detail levels.
func _apply_size() -> void:
	var viewport := get_viewport().get_visible_rect().size
	var available := minf(viewport.x - MAP_PADDING_X, viewport.y - MAP_PADDING_Y)
	var side := clampf(floorf(maxf(available, MAP_MIN_SIZE) / 16.0) * 16.0, MAP_MIN_SIZE, MAP_MAX_SIZE)
	_map_clip.custom_minimum_size = Vector2(side, side)


## Re-fits the frame when the window changes size while the atlas is open.
func _on_viewport_resized() -> void:
	if visible:
		_apply_size()


func _build_ui() -> void:
	var root: Control = $Root
	UITheme.apply(root)

	_dim = ColorRect.new()
	_dim.name = "Dim"
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.color = Color(UITheme.VOID.r, UITheme.VOID.g, UITheme.VOID.b, 0.78)
	root.add_child(_dim)

	var center := CenterContainer.new()
	center.name = "Center"
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)

	_panel = PanelContainer.new()
	_panel.name = "Panel"
	_panel.add_theme_stylebox_override("panel", UITheme.modal_style())
	center.add_child(_panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_panel.add_child(box)

	box.add_child(UITheme.eyebrow("Atlas"))
	var heading := UITheme.heading("World Map")
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	box.add_child(heading)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	box.add_child(header)
	_mode_label = Label.new()
	_mode_label.name = "Mode"
	_mode_label.add_theme_font_override("font", UITheme.font_semi())
	UITheme.apply_font_size(_mode_label, 13)
	_mode_label.add_theme_color_override("font_color", UITheme.EMBER)
	_mode_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_mode_label)
	_update_header()

	var frame := PanelContainer.new()
	frame.name = "MapFrame"
	var frame_style := UITheme.panel_style(
		Color(UITheme.SURFACE_LOW.r, UITheme.SURFACE_LOW.g, UITheme.SURFACE_LOW.b, 0.9), UITheme.LINE, 1, 6)
	frame_style.content_margin_left = 3.0
	frame_style.content_margin_right = 3.0
	frame_style.content_margin_top = 3.0
	frame_style.content_margin_bottom = 3.0
	frame.add_theme_stylebox_override("panel", frame_style)
	box.add_child(frame)

	_map_clip = Control.new()
	_map_clip.name = "MapClip"
	_map_clip.custom_minimum_size = Vector2(MAP_MIN_SIZE, MAP_MIN_SIZE)
	_map_clip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_map_clip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_map_clip.clip_contents = true
	_map_clip.focus_mode = Control.FOCUS_ALL
	_map_clip.mouse_filter = Control.MOUSE_FILTER_STOP
	_map_clip.mouse_default_cursor_shape = Control.CURSOR_MOVE
	frame.add_child(_map_clip)

	_map_image = TextureRect.new()
	_map_image.name = "Map"
	_map_image.set_anchors_preset(Control.PRESET_FULL_RECT)
	_map_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_map_image.stretch_mode = TextureRect.STRETCH_SCALE
	_map_image.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_map_image.texture = MapView.placeholder_texture()
	_map_clip.add_child(_map_image)

	_marker = Node2D.new()
	_marker.name = "Marker"
	_marker.visible = false
	var marker_shadow := Polygon2D.new()
	marker_shadow.polygon = PackedVector2Array([
		Vector2(0.0, -9.5), Vector2(7.4, 7.4), Vector2(0.0, 4.0), Vector2(-7.4, 7.4)])
	marker_shadow.color = Color(0.0, 0.0, 0.0, 0.55)
	_marker.add_child(marker_shadow)
	var marker_arrow := Polygon2D.new()
	marker_arrow.polygon = PackedVector2Array([
		Vector2(0.0, -7.6), Vector2(5.6, 5.6), Vector2(0.0, 2.8), Vector2(-5.6, 5.6)])
	marker_arrow.color = UITheme.EMBER_HI
	_marker.add_child(marker_arrow)
	_map_clip.add_child(_marker)

	var compass := Label.new()
	compass.name = "Compass"
	compass.text = "N"
	compass.set_anchors_preset(Control.PRESET_TOP_WIDE)
	compass.offset_top = 3.0
	compass.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	compass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	compass.add_theme_font_override("font", UITheme.font_semi())
	UITheme.apply_font_size(compass, 13)
	compass.add_theme_color_override("font_color", Color(UITheme.INK_DIM.r, UITheme.INK_DIM.g, UITheme.INK_DIM.b, 0.7))
	compass.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.85))
	compass.add_theme_constant_override("shadow_offset_x", 1)
	compass.add_theme_constant_override("shadow_offset_y", 1)
	_map_clip.add_child(compass)

	_caption = Label.new()
	_caption.name = "Caption"
	_caption.add_theme_font_override("font", UITheme.font_semi())
	UITheme.apply_font_size(_caption, 13)
	_caption.add_theme_color_override("font_color", UITheme.MUTED)
	_caption.text = "map unavailable"
	box.add_child(_caption)

	_position_label = Label.new()
	_position_label.name = "Position"
	_position_label.add_theme_font_override("font", UITheme.font_semi())
	UITheme.apply_font_size(_position_label, 13)
	_position_label.add_theme_color_override("font_color", UITheme.CYAN)
	_position_label.text = " "
	box.add_child(_position_label)

	var hint := Label.new()
	hint.name = "Hint"
	hint.text = "scroll or + / - zoom  ·  drag or arrow keys pan  ·  N mode  ·  M / ESC close"
	hint.add_theme_font_override("font", UITheme.font_semi())
	UITheme.apply_font_size(hint, 12)
	hint.add_theme_color_override("font_color", UITheme.FAINT)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(hint)
