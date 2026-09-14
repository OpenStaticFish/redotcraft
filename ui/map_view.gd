class_name MapView
extends RefCounted
## Shared math for the in-game map surfaces: the HUD corner minimap
## (`ui/minimap.gd`) and the full map overlay (`ui/map_overlay.gd`).
##
## Both surfaces render north-up: world +X is screen right and world +Z is
## screen down. `view_center`/`view_span` describe the world square mapped onto
## the display rect, so a baked raster can be placed by projecting its own
## center and half-span through the same transform.

## Projects a world position into map-local pixels. Returns (-1, -1) when the
## view is degenerate; callers hide their marker when the point falls outside
## the display rect. Static so tools can verify the math without a world.
static func world_to_view(world_x: float, world_z: float, view_center: Vector2, view_span: float, display: Vector2) -> Vector2:
	if view_span <= 0.0 or display.x <= 0.0 or display.y <= 0.0:
		return Vector2(-1.0, -1.0)
	return Vector2(
		display.x * 0.5 + (world_x - view_center.x) / view_span * display.x,
		display.y * 0.5 + (world_z - view_center.y) / view_span * display.y)


static func visible_in_view(point: Vector2, display: Vector2) -> bool:
	return point.x >= 0.0 and point.x <= display.x and point.y >= 0.0 and point.y <= display.y


## PackedColorArray packs four 32-bit floats per entry; Image FORMAT_RGBA8
## wants one byte per channel, so convert explicitly (deterministic regardless
## of PackedColorArray.to_byte_array() layout semantics).
static func to_rgba8(colors: PackedColorArray) -> PackedByteArray:
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


static func elide(text: String, limit: int) -> String:
	if text.length() <= limit:
		return text
	return text.substr(0, limit) + "…"
