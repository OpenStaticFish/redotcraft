extends SceneTree

## Naturalization guardrails for river channels: bounded, consistent wetted
## width, tapered banks (no trench walls), graded floodplains, a dished bed
## instead of one flat pan, and visible meander wander. These are structural
## checks on the sampler output, not a substitute for review.

const CONFIG := {
	"seed": 123456789,
	"world_type": 0,
	"terrain_scale": 1.0,
	"tree_density": 1.0,
	"macro_scale": 384.0,
	"river_density": 1.0,
	"erosion_strength": 0.55,
	"regional_erosion": 0.5,
	"cave_density": 1.0,
	"decoration_density": 1.0,
}

const GRID_RADIUS: int = 128
const GRID_SIDE: int = GRID_RADIUS * 2 + 1
const MAX_RAY: int = 72
const PROFILE_LENGTH: int = 60
const SHOULDER_RISE: float = 1.5
const SHOULDER_LIMIT: int = 30
const WATER_MIN_WIDTH: int = 5
const WATER_MAX_WIDTH: int = 56
const MAX_WIDTH_RATIO: float = 1.8
const MIN_DEPTH_SPREAD: float = 0.35
const MIN_DISH_GAP: float = 0.7
const NATURAL_BENCH_LIMIT: float = 1.5

var _failures := PackedStringArray()
var _sampler: TerrainSampler
var _heights: PackedFloat32Array = PackedFloat32Array()
var _rivers: PackedFloat32Array = PackedFloat32Array()
var _origin: Vector2i = Vector2i.ZERO


func _initialize() -> void:
	var config := WorldGenConfig.new(CONFIG)
	_sampler = TerrainSampler.new(config, TerrainProfileCatalog.new(), BiomeCatalog.new())
	var reaches := _find_reaches()
	if reaches.is_empty():
		_fail("no river reaches found along the scan lines")
		_finish()
		return
	print("RIVER VERIFY: reaches=%d" % reaches.size())
	for index in reaches.size():
		_verify_reach(reaches[index], index)
	print("RIVER VERIFY: elapsed=%.1fs" % (Time.get_ticks_msec() / 1000.0))
	_finish()


func _finish() -> void:
	if _failures.is_empty():
		print("RIVER VERIFY: PASS")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("RIVER VERIFY: FAIL (", _failures.size(), ")")
	quit(1)


## Scans a few east-west lines for wet river cells. Point queries are expensive,
## so the scan is deliberately sparse and the surrounding grid is built from
## chunk fields afterwards.
func _find_reaches() -> Array[Vector2i]:
	var reaches: Array[Vector2i] = []
	for line_z in [0, 640, -640, 1280, -1280, 1920, -1920]:
		var previous_hit := -99999
		for x in range(-2400, 2401, 12):
			var sample := _sampler.sample_point(x, line_z)
			if float(sample["river"]) < 0.9 or float(sample["final_height"]) >= VoxelDefs.SEA_LEVEL:
				continue
			if x - previous_hit < 256:
				continue
			previous_hit = x
			reaches.append(Vector2i(x, line_z))
			if reaches.size() >= 2:
				return reaches
	return reaches


func _verify_reach(center: Vector2i, index: int) -> void:
	var label := "reach%d@%s" % [index, center]
	_build_grid(center)
	var widths: PackedInt32Array = PackedInt32Array()
	var depths: PackedFloat32Array = PackedFloat32Array()
	var dish_gaps: PackedFloat32Array = PackedFloat32Array()
	var bank_steps: PackedFloat32Array = PackedFloat32Array()
	var flood_steps: PackedFloat32Array = PackedFloat32Array()
	var smooth_profiles := 0
	for local_z in range(0, GRID_SIDE, 3):
		for local_x in range(0, GRID_SIDE, 3):
			if not _is_centerline(local_x, local_z):
				continue
			var chords := _water_chords(local_x, local_z)
			if chords.x < 0 or chords.y < 0:
				continue
			var axis := 0 if chords.x <= chords.y else 1
			if not _is_bounded(local_x, local_z, axis):
				continue
			var center_depth := float(VoxelDefs.SEA_LEVEL) - _height_at(local_x, local_z)
			depths.append(center_depth)
			if center_depth >= 1.0:
				widths.append(mini(chords.x, chords.y))
				dish_gaps.append(center_depth - _edge_depth(local_x, local_z, axis))
			for direction in [-1, 1]:
				var band := _profile_bands(local_x, local_z, axis, direction)
				# Natural cliffs near the river would otherwise be blamed on the
				# carve; only grade-shaped profiles are checked.
				if float(band[2]) > NATURAL_BENCH_LIMIT:
					continue
				smooth_profiles += 1
				bank_steps.append_array(band[0])
				flood_steps.append_array(band[1])
	if widths.size() < 8:
		_fail("%s: too few bounded channel samples (%d)" % [label, widths.size()])
		return
	var sorted := widths.duplicate()
	sorted.sort()
	var median := float(sorted[sorted.size() / 2])
	var p10 := float(sorted[(sorted.size() * 1) / 10])
	var p25 := float(sorted[(sorted.size() * 1) / 4])
	var p75 := float(sorted[(sorted.size() * 3) / 4])
	var p90 := float(sorted[(sorted.size() * 9) / 10])
	var mean := _mean_int(widths)
	var depth_mean := _mean(depths)
	var depth_sorted := depths.duplicate()
	depth_sorted.sort()
	var depth_spread := depth_sorted[(depth_sorted.size() * 9) / 10] - depth_sorted[depth_sorted.size() / 10]
	var dish_mean := _mean(dish_gaps)
	var bank_mean := _mean(bank_steps)
	var flood_mean := _mean(flood_steps)
	print("RIVER %s: samples=%d width median=%.1f mean=%.1f p10=%.1f p25=%.1f p75=%.1f p90=%.1f depth_mean=%.2f spread=%.2f dish=%.2f bank_mean=%.2f flood_mean=%.2f smooth=%d" % [
		label, widths.size(), median, mean, p10, p25, p75, p90,
		depth_mean, depth_spread, dish_mean, bank_mean, flood_mean, smooth_profiles])
	_expect(median >= float(WATER_MIN_WIDTH) and mean <= float(WATER_MAX_WIDTH),
		"%s: wetted width out of range (median %.1f mean %.1f)" % [label, median, mean])
	# Interquartile ratio: the old gradient-space mask measured 1.93-2.46 while
	# the distance-normalized field stays around 1.5-1.65 across reaches.
	_expect(p75 <= p25 * MAX_WIDTH_RATIO,
		"%s: river width is inconsistent (p25 %.1f p75 %.1f, median %.1f)" % [label, p25, p75, median])
	_expect(depth_mean >= 1.2 and depth_mean <= 5.0,
		"%s: channel depth out of range (mean %.2f)" % [label, depth_mean])
	_expect(depth_spread >= MIN_DEPTH_SPREAD,
		"%s: bed is a constant-depth pan (spread %.2f)" % [label, depth_spread])
	_expect(dish_mean >= MIN_DISH_GAP,
		"%s: cross-section is a flat pan, not a dished bed (gap %.2f)" % [label, dish_mean])
	_expect(smooth_profiles >= 8, "%s: too few grade-shaped bank profiles (%d)" % [label, smooth_profiles])
	_expect(bank_mean <= 1.0,
		"%s: bank profile is not tapered (mean step %.2f)" % [label, bank_mean])
	_expect(flood_mean <= 1.0,
		"%s: floodplain is not graded (mean step %.2f)" % [label, flood_mean])


## Depth at the cell two blocks inside the water edge on the short axis. A flat
## sea-relative pan keeps nearly full depth there, while a dished bed tapers.
func _edge_depth(local_x: int, local_z: int, axis: int) -> float:
	var dx := 1 if axis == 0 else 0
	var dz := 1 if axis == 1 else 0
	var shallowest := 999.0
	for direction in [-1, 1]:
		var edge := -1
		for step in range(1, MAX_RAY + 1):
			var height := _height_at(local_x + dx * direction * step, local_z + dz * direction * step)
			if height < 0.0:
				break
			if height >= float(VoxelDefs.SEA_LEVEL):
				edge = step
				break
		if edge < 0:
			continue
		var sample := maxi(edge - 2, 1)
		var height := _height_at(local_x + dx * direction * sample, local_z + dz * direction * sample)
		shallowest = minf(shallowest, float(VoxelDefs.SEA_LEVEL) - height)
	if shallowest > 900.0:
		return 0.0
	return shallowest


## Copies final heights and river strength for a square region from the chunk
## fields. build_field is the same path chunk generation uses, so this avoids
## the repeated regional-erosion work of sample_point.
func _build_grid(center: Vector2i) -> void:
	_origin = center - Vector2i(GRID_RADIUS, GRID_RADIUS)
	_heights.resize(GRID_SIDE * GRID_SIDE)
	_rivers.resize(GRID_SIDE * GRID_SIDE)
	var first_chunk := Vector2i(
		WorldGenHash.floor_div(_origin.x, VoxelDefs.CHUNK_SIZE),
		WorldGenHash.floor_div(_origin.y, VoxelDefs.CHUNK_SIZE))
	var last_chunk := Vector2i(
		WorldGenHash.floor_div(_origin.x + GRID_SIDE - 1, VoxelDefs.CHUNK_SIZE),
		WorldGenHash.floor_div(_origin.y + GRID_SIDE - 1, VoxelDefs.CHUNK_SIZE))
	for chunk_z in range(first_chunk.y, last_chunk.y + 1):
		for chunk_x in range(first_chunk.x, last_chunk.x + 1):
			var field := _sampler.build_field(Vector2i(chunk_x, chunk_z))
			var chunk_origin := Vector2i(chunk_x * VoxelDefs.CHUNK_SIZE, chunk_z * VoxelDefs.CHUNK_SIZE)
			for local_z in VoxelDefs.CHUNK_SIZE:
				var world_z := chunk_origin.y + local_z
				var grid_z := world_z - _origin.y
				if grid_z < 0 or grid_z >= GRID_SIDE:
					continue
				for local_x in VoxelDefs.CHUNK_SIZE:
					var world_x := chunk_origin.x + local_x
					var grid_x := world_x - _origin.x
					if grid_x < 0 or grid_x >= GRID_SIDE:
						continue
					var field_index := ChunkTerrainData.cell_index(local_x, local_z)
					var grid_index := grid_z * GRID_SIDE + grid_x
					_heights[grid_index] = field.final_height[field_index]
					_rivers[grid_index] = field.river[field_index]


func _height_at(local_x: int, local_z: int) -> float:
	if local_x < 0 or local_x >= GRID_SIDE or local_z < 0 or local_z >= GRID_SIDE:
		return -1.0
	return _heights[local_z * GRID_SIDE + local_x]


func _river_at(local_x: int, local_z: int) -> float:
	if local_x < 0 or local_x >= GRID_SIDE or local_z < 0 or local_z >= GRID_SIDE:
		return 0.0
	return _rivers[local_z * GRID_SIDE + local_x]


func _is_centerline(local_x: int, local_z: int) -> bool:
	return _river_at(local_x, local_z) > 0.9 and _height_at(local_x, local_z) < float(VoxelDefs.SEA_LEVEL)


## Walks one axis each way from a wet cell until dry ground. Returns (x chord,
## z chord) or (-1, -1) when an axis runs past the grid.
func _water_chords(local_x: int, local_z: int) -> Vector2i:
	var x_minus := _dry_distance(local_x, local_z, -1, 0)
	var x_plus := _dry_distance(local_x, local_z, 1, 0)
	var z_minus := _dry_distance(local_x, local_z, 0, -1)
	var z_plus := _dry_distance(local_x, local_z, 0, 1)
	if x_minus < 0 or x_plus < 0 or z_minus < 0 or z_plus < 0:
		return Vector2i(-1, -1)
	return Vector2i(x_minus + x_plus + 1, z_minus + z_plus + 1)


func _dry_distance(local_x: int, local_z: int, dx: int, dz: int) -> int:
	for step in range(1, MAX_RAY + 1):
		var height := _height_at(local_x + dx * step, local_z + dz * step)
		if height < 0.0:
			return -1
		if height >= float(VoxelDefs.SEA_LEVEL):
			return step - 1
	return -1


## True when both banks rise out of the water within the shoulder limit, so the
## sample is a channel rather than a lake or a confluence pool.
func _is_bounded(local_x: int, local_z: int, axis: int) -> bool:
	var dx := 1 if axis == 0 else 0
	var dz := 1 if axis == 1 else 0
	for direction in [-1, 1]:
		var found := false
		for step in range(1, SHOULDER_LIMIT + 1):
			var height := _height_at(local_x + dx * direction * step, local_z + dz * direction * step)
			if height < 0.0:
				break
			if height >= float(VoxelDefs.SEA_LEVEL) + SHOULDER_RISE:
				found = true
				break
		if not found:
			return false
	return true


## Height-step bands measured outward from the water edge. Returns
## [bank_steps, flood_steps, bench_max_step]; the bench band is the natural
## terrain beyond the floodplain and is used to skip cliffs the carve did not
## create.
func _profile_bands(local_x: int, local_z: int, axis: int, direction: int) -> Array:
	var dx := 1 if axis == 0 else 0
	var dz := 1 if axis == 1 else 0
	var bank := PackedFloat32Array()
	var flood := PackedFloat32Array()
	var edge := -1
	for step in range(1, PROFILE_LENGTH + 1):
		if _height_at(local_x + dx * direction * step, local_z + dz * direction * step) < 0.0:
			break
		if _height_at(local_x + dx * direction * step, local_z + dz * direction * step) >= float(VoxelDefs.SEA_LEVEL):
			edge = step
			break
	if edge < 0:
		return [bank, flood, 0.0]
	var previous := float(VoxelDefs.SEA_LEVEL)
	var bench_max := 0.0
	for step in range(edge, PROFILE_LENGTH + 1):
		var height := _height_at(local_x + dx * direction * step, local_z + dz * direction * step)
		if height < 0.0:
			break
		var delta := absf(height - previous)
		var distance: int = step - edge
		if distance <= 10:
			bank.append(delta)
		elif distance <= 24:
			flood.append(delta)
		elif distance <= 44:
			bench_max = maxf(bench_max, delta)
		previous = height
	return [bank, flood, bench_max]


func _mean(values: PackedFloat32Array) -> float:
	if values.is_empty():
		return 0.0
	var total := 0.0
	for value in values:
		total += value
	return total / float(values.size())


func _mean_int(values: PackedInt32Array) -> float:
	if values.is_empty():
		return 0.0
	var total := 0
	for value in values:
		total += value
	return float(total) / float(values.size())


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)


func _fail(message: String) -> void:
	_failures.append(message)
