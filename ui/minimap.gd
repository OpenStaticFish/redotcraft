class_name Minimap
extends CanvasLayer
## Compact corner minimap fed by the WorldgenOverlay map modes.
##
## Nonmodal HUD layer: it handles no input itself (Main binds M/N), never
## pauses the tree, and never touches the mouse mode. The raster is only
## sampled on open, on mode change, when the player wanders RECENTER_BLOCKS
## from the baked center, and while an asynchronous worker request is pending;
## the player marker follows the live transform every frame.
##
## Wired by game/main.gd:
##   var minimap: Minimap = MinimapScene.instantiate()
##   add_child(minimap)
##   minimap.initialize(world, player)
##   minimap.status_requested.connect(set_status)
##
## VoxelWorld API (shared with WorldgenOverlay, probed with has_method so the
## game keeps running with a fallback caption until it lands):
##   request_debug_map(mode, center, sample_size, stride) -> Dictionary
## The payload's `pixels`/`width`/`height` make an image spanning
## width * stride blocks centered on the request center; `pending = true`
## means the worker is still sampling and the caller should poll again.

signal status_requested(message: String)

## Keep the mode list identical to the F3 overlay instead of duplicating it.
const MAP_MODES: Array[String] = WorldgenOverlay.MAP_MODES

const MAP_DISPLAY_SIZE := 156.0
## 64x64 rasters over a 256-block span: twice the old view at four times the
## pixels. The worker downshifts the final-height family to keep its refresh
## responsive.
const MAP_SAMPLES := 64
const MAP_STRIDE := 4
const MAP_DETAIL := 64
const RECENTER_BLOCKS := 64
const REFRESH_INTERVAL := 0.25

var _world: VoxelWorld
var _player: Player
var _mode_index := 0
var _map_center := Vector2i(1 << 30, 1 << 30)
var _map_span := Vector2i.ZERO
var _map_pending := false
var _refresh_accum := 0.0

var _panel: PanelContainer
var _mode_label: Label
var _map_rect: TextureRect
var _caption: Label
var _marker: Node2D


func _ready() -> void:
	_build_ui()
	visible = false


## Bind the minimap to the live world and player. Safe to call before the
## minimap enters the tree; the first raster is requested on open.
func initialize(world: VoxelWorld, player: Player) -> void:
	_world = world
	_player = player
	_refresh_accum = 0.0
	if visible:
		_rebuild_map()


func toggle() -> void:
	visible = not visible
	if visible:
		_rebuild_map()
	status_requested.emit("Minimap %s · N changes map mode" % ("on" if visible else "off"))


func cycle_mode() -> void:
	_mode_index = wrapi(_mode_index + 1, 0, MAP_MODES.size())
	_update_mode_label()
	if visible:
		_rebuild_map()
	status_requested.emit("Minimap map: %s (%d/%d)" % [
		MAP_MODES[_mode_index], _mode_index + 1, MAP_MODES.size()])


func get_mode() -> String:
	return MAP_MODES[_mode_index]


func is_pending() -> bool:
	return _map_pending


func _process(delta: float) -> void:
	if not visible:
		return
	_update_marker()
	if get_tree().paused:
		return
	_refresh_accum += delta
	if _refresh_accum < REFRESH_INTERVAL:
		return
	_refresh_accum = 0.0
	if _map_pending:
		_rebuild_map()
		return
	_maybe_recenter()


## Requests a fresh raster when the player has wandered RECENTER_BLOCKS from
## the center the current map was baked for. Cheap distance check, runs at the
## refresh throttle rate, never per frame.
func _maybe_recenter() -> void:
	if _player == null or _world == null:
		return
	var center := _player_block_center()
	if maxi(absi(center.x - _map_center.x), absi(center.y - _map_center.y)) < RECENTER_BLOCKS:
		return
	_rebuild_map()


func _player_block_center() -> Vector2i:
	return Vector2i(floori(_player.global_position.x), floori(_player.global_position.z))


## Requests and renders the raster for the current mode, centered on the
## player. Only called on open, on mode change, on recenter, and while polling
## a pending worker result.
func _rebuild_map() -> void:
	if _map_rect == null:
		return
	_update_mode_label()
	if _player == null or _world == null:
		_caption.text = "initialize(world, player) pending"
		return
	if not _world.has_method("request_debug_map"):
		_caption.text = "request_debug_map() unavailable on VoxelWorld"
		return
	var center := _player_block_center()
	var payload: Variant = _world.call(
		"request_debug_map", MAP_MODES[_mode_index], center, MAP_SAMPLES, MAP_STRIDE, MAP_DETAIL)
	if not (payload is Dictionary):
		_caption.text = "map unavailable"
		return
	var dictionary: Dictionary = payload
	if bool(dictionary.get("pending", false)):
		_map_pending = true
		_caption.text = "%s sampling…" % MAP_MODES[_mode_index].to_upper()
		return
	var pixels: Variant = dictionary.get("pixels", PackedColorArray())
	var width := int(dictionary.get("width", 0))
	var height := int(dictionary.get("height", 0))
	if not (pixels is PackedColorArray) or width <= 0 or height <= 0 \
			or (pixels as PackedColorArray).size() < width * height:
		_map_pending = false
		_caption.text = "invalid map payload"
		return
	_map_pending = false
	_map_center = center
	var image := Image.create_from_data(width, height, false, Image.FORMAT_RGBA8, MapView.to_rgba8(pixels))
	_map_rect.texture = ImageTexture.create_from_image(image)
	var payload_stride := clampi(int(dictionary.get("stride", MAP_STRIDE)), 1, 64)
	_map_span = Vector2i(width * payload_stride, height * payload_stride)
	_caption.text = "%d×%d b · 1 px = %d b" % [_map_span.x, _map_span.y, payload_stride]
	_update_marker()


## Positions and rotates the arrow on the map: north-up, so the marker turns
## with the player body while the map stays fixed. Cheap per-frame math; hides
## the arrow until a raster has been baked and while the player is off-map.
func _update_marker() -> void:
	if _marker == null or _player == null or _map_span.x <= 0 or _map_span.y <= 0:
		return
	var display := _map_rect.size
	if display.x < 1.0 or display.y < 1.0:
		display = Vector2(MAP_DISPLAY_SIZE, MAP_DISPLAY_SIZE)
	var point := MapView.world_to_view(
		_player.global_position.x, _player.global_position.z,
		Vector2(_map_center), float(_map_span.x), display)
	_marker.visible = MapView.visible_in_view(point, display)
	if not _marker.visible:
		return
	_marker.position = point
	_marker.rotation = -_player.global_rotation.y


func _update_mode_label() -> void:
	if _mode_label == null:
		return
	_mode_label.text = "%s  %d/%d" % [
		MapView.elide(MAP_MODES[_mode_index].to_upper(), 12), _mode_index + 1, MAP_MODES.size()]


func _build_ui() -> void:
	var root: Control = $Root
	root.theme = UITheme.build()

	_panel = PanelContainer.new()
	_panel.name = "Panel"
	var panel_style := UITheme.panel_style(
		Color(UITheme.SURFACE.r, UITheme.SURFACE.g, UITheme.SURFACE.b, 0.88), UITheme.LINE, 1, 8)
	panel_style.content_margin_left = 10.0
	panel_style.content_margin_right = 10.0
	panel_style.content_margin_top = 8.0
	panel_style.content_margin_bottom = 8.0
	_panel.add_theme_stylebox_override("panel", panel_style)
	# Anchor to the top-right, below the stats chip.
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.offset_left = -(MAP_DISPLAY_SIZE + 36.0)
	_panel.offset_right = -10.0
	_panel.offset_top = 80.0
	_panel.offset_bottom = 80.0
	root.add_child(_panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_panel.add_child(box)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	box.add_child(header)
	var title := Label.new()
	title.name = "Title"
	title.text = "MAP"
	title.add_theme_font_override("font", UITheme.font_eyebrow())
	title.add_theme_font_size_override("font_size", UITheme.SIZE_EYEBROW)
	title.add_theme_color_override("font_color", UITheme.EMBER)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_mode_label = Label.new()
	_mode_label.name = "Mode"
	_mode_label.add_theme_font_override("font", UITheme.font_semi())
	_mode_label.add_theme_font_size_override("font_size", 11)
	_mode_label.add_theme_color_override("font_color", UITheme.MUTED)
	_mode_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	header.add_child(_mode_label)
	_update_mode_label()

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

	_map_rect = TextureRect.new()
	_map_rect.name = "Map"
	_map_rect.custom_minimum_size = Vector2(MAP_DISPLAY_SIZE, MAP_DISPLAY_SIZE)
	_map_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_map_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_map_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_map_rect.texture = _make_placeholder_texture()
	frame.add_child(_map_rect)

	_marker = Node2D.new()
	_marker.name = "Marker"
	_marker.visible = false
	var marker_shadow := Polygon2D.new()
	marker_shadow.polygon = PackedVector2Array([
		Vector2(0.0, -7.5), Vector2(5.8, 6.4), Vector2(0.0, 3.4), Vector2(-5.8, 6.4)])
	marker_shadow.color = Color(0.0, 0.0, 0.0, 0.55)
	_marker.add_child(marker_shadow)
	var marker_arrow := Polygon2D.new()
	marker_arrow.polygon = PackedVector2Array([
		Vector2(0.0, -6.0), Vector2(4.4, 4.8), Vector2(0.0, 2.4), Vector2(-4.4, 4.8)])
	marker_arrow.color = UITheme.EMBER_HI
	_marker.add_child(marker_arrow)
	_map_rect.add_child(_marker)

	var compass := Label.new()
	compass.name = "Compass"
	compass.text = "N"
	compass.set_anchors_preset(Control.PRESET_TOP_WIDE)
	compass.offset_top = 1.0
	compass.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	compass.add_theme_font_override("font", UITheme.font_semi())
	compass.add_theme_font_size_override("font_size", 11)
	compass.add_theme_color_override("font_color", Color(UITheme.INK_DIM.r, UITheme.INK_DIM.g, UITheme.INK_DIM.b, 0.65))
	compass.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.8))
	compass.add_theme_constant_override("shadow_offset_x", 1)
	compass.add_theme_constant_override("shadow_offset_y", 1)
	_map_rect.add_child(compass)

	_caption = Label.new()
	_caption.name = "Caption"
	_caption.add_theme_font_size_override("font_size", 11)
	_caption.add_theme_color_override("font_color", UITheme.MUTED)
	_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_caption.text = "map unavailable"
	box.add_child(_caption)

	_ignore_mouse_recursively(root)


func _make_placeholder_texture() -> ImageTexture:
	var even := Color(0.05, 0.09, 0.10, 1.0)
	var odd := Color(0.07, 0.12, 0.13, 1.0)
	var bytes := PackedByteArray()
	bytes.resize(16 * 16 * 4)
	var write := 0
	for y in 16:
		for x in 16:
			var color := even if (((x >> 2) + (y >> 2)) % 2 == 0) else odd
			bytes[write] = int(color.r8)
			bytes[write + 1] = int(color.g8)
			bytes[write + 2] = int(color.b8)
			bytes[write + 3] = 255
			write += 4
	var image := Image.create_from_data(16, 16, false, Image.FORMAT_RGBA8, bytes)
	return ImageTexture.create_from_image(image)


## Nothing in this layer may intercept the mouse: the root control covers the
## whole viewport, so every control must pass clicks through.
func _ignore_mouse_recursively(node: Node) -> void:
	if node is Control:
		(node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		_ignore_mouse_recursively(child)
