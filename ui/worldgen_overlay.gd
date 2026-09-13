class_name WorldgenOverlay
extends CanvasLayer
## Minimal F3-style worldgen diagnostics overlay. Off by default, nonmodal.
##
## Intended wiring from game/main.gd (see report):
##   var overlay: WorldgenOverlay = WorldgenOverlayScene.instantiate()
##   add_child(overlay)
##   overlay.initialize(world, player)
##   overlay.status_requested.connect(set_status)
##   # bind keys (e.g. F3 / F4) in Main to overlay.toggle() / overlay.cycle_mode()
##
## Nonmodal by construction: it never pauses the tree, never touches the mouse
## mode, and handles no input at all (every Control uses MOUSE_FILTER_IGNORE),
## so it can never fight Player's Esc handling or capture the mouse.
##
## VoxelWorld API this expects -- probed at runtime with has_method(), so the
## game keeps running (with graceful fallback text) until the methods land:
##   get_worldgen_stats() -> Dictionary
##   request_debug_map(mode: String, center: Vector2i, sample_size: int,
##                      stride: int) -> Dictionary
## The map payload provides `pixels: PackedColorArray`, `width: int` and
## `height: int`, and is assumed to span width * stride blocks centered on
## `center` (that assumption drives the player marker and the span caption).
##
## Cost model: the debug map is only rebuilt on open, on mode change, and when
## the player moves RECENTER_BLOCKS or more from the last map center. Metrics
## text refreshes on a TEXT_REFRESH_INTERVAL throttle, never per frame.

signal status_requested(message: String)

const MAP_MODES: Array[String] = [
	"biome", "height", "raw_height", "slope", "temperature", "moisture",
	"continentalness", "river", "profile",
]
const WORLD_TYPE_NAMES: Array[String] = ["normal", "flat", "amplified"]

const MAP_DISPLAY_SIZE := 256.0
const MAP_STRIDE := 4
const RECENTER_BLOCKS := 64
const TEXT_REFRESH_INTERVAL := 0.25
const MAX_STAT_LINES := 8
const MAX_KEY_LENGTH := 20
const MAX_VALUE_LENGTH := 28

var _world: VoxelWorld
var _player: Player
var _mode_index := 0
var _map_center := Vector2i(1 << 30, 1 << 30)
var _map_span := Vector2i.ZERO
var _refresh_accum := 0.0
var _map_pending := false

var _panel: PanelContainer
var _mode_label: Label
var _position_label: Label
var _stats_label: Label
var _map_rect: TextureRect
var _marker: Label
var _map_caption: Label


func _ready() -> void:
	_build_ui()
	visible = false


## Bind the overlay to the live world and player. Safe to call before the
## overlay enters the tree; the first refresh happens on open.
func initialize(world: VoxelWorld, player: Player) -> void:
	_world = world
	_player = player
	_refresh_accum = 0.0
	if visible:
		_refresh_all()


func toggle() -> void:
	visible = not visible
	if visible:
		_refresh_all()
	status_requested.emit("Worldgen overlay %s" % ("on" if visible else "off"))


func cycle_mode() -> void:
	_mode_index = wrapi(_mode_index + 1, 0, MAP_MODES.size())
	_update_mode_label()
	if visible:
		_rebuild_map()
	status_requested.emit("Worldgen map: %s (%d/%d)" % [
		MAP_MODES[_mode_index], _mode_index + 1, MAP_MODES.size()])


func get_mode() -> String:
	return MAP_MODES[_mode_index]


func _process(delta: float) -> void:
	if not visible:
		return
	_refresh_accum += delta
	if _refresh_accum < TEXT_REFRESH_INTERVAL:
		return
	_refresh_accum = 0.0
	_refresh_text()
	_update_marker()
	if _map_pending:
		_rebuild_map()
	_maybe_recenter()


func _refresh_all() -> void:
	_refresh_text()
	_rebuild_map()


## Rebuilds the map when the player has wandered RECENTER_BLOCKS from the
## center the current map was baked for. Cheap distance check, runs at the
## text throttle rate, never per frame.
func _maybe_recenter() -> void:
	if _player == null or _world == null or not _world.has_method("request_debug_map"):
		return
	var center := _player_block_center()
	if maxi(absi(center.x - _map_center.x), absi(center.y - _map_center.y)) < RECENTER_BLOCKS:
		return
	_rebuild_map()


func _player_block_center() -> Vector2i:
	return Vector2i(floori(_player.global_position.x), floori(_player.global_position.z))


func _refresh_text() -> void:
	if _position_label == null:
		return
	if _player == null or _world == null:
		_position_label.text = "initialize(world, player) pending"
		_stats_label.text = ""
		return
	var config: Dictionary = GameConfig.world
	var coords := Vector3i(
		floori(_player.global_position.x),
		floori(_player.global_position.y),
		floori(_player.global_position.z))
	_position_label.text = "%s\nXYZ %d %d %d  ·  %s" % [
		"seed %d  ·  %s  ·  scale %.2f" % [
			int(config.get("seed", 0)),
			WORLD_TYPE_NAMES[clampi(int(config.get("world_type", 0)), 0, WORLD_TYPE_NAMES.size() - 1)],
			clampf(float(config.get("terrain_scale", 1.0)), 0.0, 99.0)],
		coords.x, coords.y, coords.z,
		_world.get_biome_name(_player.global_position),
	]
	_stats_label.text = "\n".join(_collect_stat_lines())


func _collect_stat_lines() -> PackedStringArray:
	var lines := PackedStringArray()
	if _world == null or not _world.has_method("get_worldgen_stats"):
		lines.append("get_worldgen_stats() unavailable on VoxelWorld")
		return lines
	var stats: Variant = _world.call("get_worldgen_stats")
	if not (stats is Dictionary):
		lines.append("get_worldgen_stats() returned %s" % str(typeof(stats)))
		return lines
	var dictionary: Dictionary = stats
	if dictionary.is_empty():
		lines.append("no stats reported")
		return lines
	var shown := 0
	for key in dictionary.keys():
		if shown >= MAX_STAT_LINES:
			lines.append("+%d more" % (dictionary.size() - MAX_STAT_LINES))
			break
		lines.append("%s  %s" % [
			_elide(str(key).capitalize(), MAX_KEY_LENGTH),
			_format_stat_value(dictionary[key])])
		shown += 1
	return lines


func _format_stat_value(value: Variant) -> String:
	if value is bool:
		return "yes" if value else "no"
	if value is float:
		return "%.2f" % value
	if value is int:
		return str(value)
	if value is Vector2 or value is Vector2i:
		return "%s" % str(value)
	return _elide(str(value), MAX_VALUE_LENGTH)


func _elide(text: String, limit: int) -> String:
	if text.length() <= limit:
		return text
	return text.substr(0, limit) + "…"


## Requests and renders the debug map for the current mode, centered on the
## player. Only called on open, on mode change, and on recenter.
func _rebuild_map() -> void:
	if _map_rect == null:
		return
	_update_mode_label()
	if _player == null or _world == null:
		_map_caption.text = "initialize(world, player) pending"
		return
	if not _world.has_method("request_debug_map"):
		_map_caption.text = "request_debug_map() unavailable on VoxelWorld"
		_map_center = _player_block_center()
		return
	var center := _player_block_center()
	_map_center = center
	var payload: Variant = _world.call(
		"request_debug_map", MAP_MODES[_mode_index], center,
		int(MAP_DISPLAY_SIZE), MAP_STRIDE)
	if not (payload is Dictionary):
		_map_caption.text = "invalid debug map payload"
		return
	var dictionary: Dictionary = payload
	if bool(dictionary.get("pending", false)):
		_map_pending = true
		_map_caption.text = "%s map sampling…" % MAP_MODES[_mode_index].to_upper()
		return
	var pixels: Variant = dictionary.get("pixels", PackedColorArray())
	var width := int(dictionary.get("width", 0))
	var height := int(dictionary.get("height", 0))
	if not (pixels is PackedColorArray) or width <= 0 or height <= 0 \
			or (pixels as PackedColorArray).size() < width * height:
		_map_caption.text = "invalid debug map payload"
		return
	_map_pending = false
	var colors: PackedColorArray = pixels
	var payload_stride := clampi(int(dictionary.get("stride", MAP_STRIDE)), 1, 32)
	var image := Image.create_from_data(width, height, false, Image.FORMAT_RGBA8, _to_rgba8(colors))
	_map_rect.texture = ImageTexture.create_from_image(image)
	_map_span = Vector2i(width * payload_stride, height * payload_stride)
	_map_caption.text = "%s  ·  %d×%d blocks  ·  1px = %db  ·  center %d, %d" % [
		MAP_MODES[_mode_index].to_upper(),
		_map_span.x, _map_span.y, payload_stride, center.x, center.y]
	_update_marker()


## Positions the "+" player marker on the map. Runs at the text throttle rate;
## hidden while only the placeholder checkerboard is shown.
func _update_marker() -> void:
	if _marker == null or _player == null or _map_span.x <= 0 or _map_span.y <= 0:
		return
	var origin := Vector2(
		float(_map_center.x) - float(_map_span.x) * 0.5,
		float(_map_center.y) - float(_map_span.y) * 0.5)
	var point := Vector2(
		(_player.global_position.x - origin.x) / float(_map_span.x),
		(_player.global_position.z - origin.y) / float(_map_span.y))
	if point.x < 0.0 or point.x > 1.0 or point.y < 0.0 or point.y > 1.0:
		_marker.visible = false
		return
	_marker.visible = true
	var display := _map_rect.size
	if display.x < 1.0 or display.y < 1.0:
		display = Vector2(MAP_DISPLAY_SIZE, MAP_DISPLAY_SIZE)
	_marker.position = Vector2(point.x * display.x, point.y * display.y) \
		- _marker.get_minimum_size() * 0.5


func _update_mode_label() -> void:
	if _mode_label == null:
		return
	_mode_label.text = "%s  %d/%d" % [
		MAP_MODES[_mode_index].to_upper(), _mode_index + 1, MAP_MODES.size()]


## PackedColorArray packs four 32-bit floats per entry; Image FORMAT_RGBA8
## wants one byte per channel, so convert explicitly (deterministic regardless
## of PackedColorArray.to_byte_array() layout semantics).
func _to_rgba8(colors: PackedColorArray) -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(colors.size() * 4)
	var write := 0
	for index in colors.size():
		var color: Color = colors[index]
		bytes[write] = int(clampf(color.r, 0.0, 1.0) * 255.0 + 0.5)
		bytes[write + 1] = int(clampf(color.g, 0.0, 1.0) * 255.0 + 0.5)
		bytes[write + 2] = int(clampf(color.b, 0.0, 1.0) * 255.0 + 0.5)
		bytes[write + 3] = int(clampf(color.a, 0.0, 1.0) * 255.0 + 0.5)
		write += 4
	return bytes


func _build_ui() -> void:
	var root: Control = $Root
	root.theme = UITheme.build()

	_panel = PanelContainer.new()
	_panel.name = "Panel"
	_panel.add_theme_stylebox_override("panel", UITheme.panel_style(UITheme.PANEL, UITheme.BORDER, 1, 8))
	root.add_child(_panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_panel.add_child(box)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	box.add_child(header)
	var title := Label.new()
	title.name = "Title"
	title.text = "WORLDGEN"
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", UITheme.TEAL)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_mode_label = Label.new()
	_mode_label.name = "Mode"
	_mode_label.add_theme_font_size_override("font_size", 14)
	_mode_label.add_theme_color_override("font_color", UITheme.MUTED)
	_mode_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	header.add_child(_mode_label)
	_update_mode_label()

	_position_label = Label.new()
	_position_label.name = "Position"
	_position_label.add_theme_font_size_override("font_size", 13)
	box.add_child(_position_label)

	_stats_label = Label.new()
	_stats_label.name = "Stats"
	_stats_label.add_theme_font_size_override("font_size", 13)
	_stats_label.add_theme_color_override("font_color", UITheme.MUTED)
	box.add_child(_stats_label)
	_refresh_text()

	box.add_child(_make_divider())

	var frame := PanelContainer.new()
	frame.name = "MapFrame"
	frame.add_theme_stylebox_override("panel", UITheme.panel_style(UITheme.PANEL_LIGHT, UITheme.BORDER, 1, 6))
	box.add_child(frame)
	_map_rect = TextureRect.new()
	_map_rect.name = "Map"
	_map_rect.custom_minimum_size = Vector2(MAP_DISPLAY_SIZE, MAP_DISPLAY_SIZE)
	_map_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_map_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_map_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_map_rect.texture = _make_placeholder_texture()
	frame.add_child(_map_rect)
	_marker = Label.new()
	_marker.name = "Marker"
	_marker.text = "+"
	_marker.add_theme_font_size_override("font_size", 20)
	_marker.add_theme_color_override("font_color", UITheme.INK)
	_marker.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.85))
	_marker.add_theme_constant_override("shadow_offset_x", 1)
	_marker.add_theme_constant_override("shadow_offset_y", 1)
	_marker.visible = false
	_map_rect.add_child(_marker)

	_map_caption = Label.new()
	_map_caption.name = "MapCaption"
	_map_caption.add_theme_font_size_override("font_size", 12)
	_map_caption.add_theme_color_override("font_color", UITheme.MUTED)
	_map_caption.text = "map unavailable"
	box.add_child(_map_caption)

	_ignore_mouse_recursively(root)
	_panel.reset_size()
	_panel.position = Vector2(16.0, 96.0)


func _make_divider() -> ColorRect:
	var divider := ColorRect.new()
	divider.color = Color(1.0, 1.0, 1.0, 0.08)
	divider.custom_minimum_size = Vector2(0.0, 1.0)
	return divider


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


## Nothing in this overlay may intercept the mouse: the root control covers
## the whole viewport, so every control must pass clicks through.
func _ignore_mouse_recursively(node: Node) -> void:
	if node is Control:
		(node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		_ignore_mouse_recursively(child)
